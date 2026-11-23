import CoreLocation
import CoreWLAN
import Foundation

/// Native CoreWLAN + CoreLocation manager for live RF telemetry, Wi-Fi power control,
/// nearby network scanning, and association.
public final class WiFiController: NSObject, CLLocationManagerDelegate, CWEventDelegate, @unchecked Sendable {
    public var onEventChange: (@Sendable () -> Void)?
    public var onLocationAuthorizationChanged: (@Sendable (CLAuthorizationStatus) -> Void)?

    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private let timeoutLock = NSLock()
    private var locationPromptTimeout: DispatchWorkItem?

    public override init() {
        super.init()
        locationManager.delegate = self
        wifiClient.delegate = self
        try? wifiClient.startMonitoringEvent(with: .ssidDidChange)
        try? wifiClient.startMonitoringEvent(with: .bssidDidChange)
        try? wifiClient.startMonitoringEvent(with: .linkDidChange)
        try? wifiClient.startMonitoringEvent(with: .powerDidChange)
    }

    deinit {
        try? wifiClient.stopMonitoringAllEvents()
        wifiClient.delegate = nil
        locationManager.delegate = nil
    }

    public var locationAuthorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    public var locationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    public var hasLocationAccess: Bool {
        let s = locationManager.authorizationStatus
        return s == .authorizedAlways || s == .authorized
    }

    public func requestLocationAccess() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cancelLocationTimeout()
            self.locationManager.desiredAccuracy = kCLLocationAccuracyReduced
            self.locationManager.requestAlwaysAuthorization()
            // Starting updates guarantees macOS locationd presents the TCC prompt for LSUIElement menu bar apps.
            // Keep running until delegate responds (auth change, fix, or error), capped at 30s.
            self.locationManager.startUpdatingLocation()
            let timeout = DispatchWorkItem { [weak self] in
                self?.locationManager.stopUpdatingLocation()
            }
            self.timeoutLock.withLock { self.locationPromptTimeout = timeout }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: timeout)
        }
    }

    private func cancelLocationTimeout() {
        let item = timeoutLock.withLock { () -> DispatchWorkItem? in
            let existing = locationPromptTimeout
            locationPromptTimeout = nil
            return existing
        }
        item?.cancel()
    }

    /// Returns saved preferred Wi-Fi SSIDs from macOS CoreWLAN configuration.
    /// Unlike live scan SSIDs, saved profile names are readable even before Location Services is granted.
    public func knownNetworkSSIDs(limit: Int = 30) -> [String] {
        guard let iface = wifiClient.interface(),
              let profiles = iface.configuration()?.networkProfiles.array as? [CWNetworkProfile] else {
            return []
        }
        var seen: Set<String> = []
        var result: [String] = []
        for profile in profiles {
            guard let ssid = profile.ssid, !ssid.isEmpty, !seen.contains(ssid) else { continue }
            seen.insert(ssid)
            result.append(ssid)
            if result.count >= limit { break }
        }
        return result
    }

    public func currentSnapshot() -> WiFiSnapshot {
        guard let iface = wifiClient.interface() else {
            return WiFiSnapshot()
        }

        let power = iface.powerOn()
        let rssi = iface.rssiValue()
        let noise = iface.noiseMeasurement()
        let txRate = iface.transmitRate()
        let channelObj = iface.wlanChannel()
        let chNum = channelObj?.channelNumber ?? 0
        let band = Self.mapBand(channelObj?.channelBand)
        let width = Self.mapWidth(channelObj?.channelWidth)
        let security = Self.mapSecurity(iface.security())
        let phy = Self.mapPHY(iface.activePHYMode())
        let mac = iface.hardwareAddress()
        let ssid = iface.ssid()
        let bssid = iface.bssid()
        // Connected if SSID is present OR RSSI/channel indicates active association (even when Location redacts SSID)
        let connected = power && (ssid != nil || (rssi < 0 && chNum > 0))

        return WiFiSnapshot(
            interfaceName: iface.interfaceName ?? "en0",
            powerOn: power,
            isConnected: connected,
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            noise: noise,
            txRateMbps: txRate,
            channel: chNum,
            band: band,
            channelWidthMHz: width,
            phyGeneration: phy,
            security: security,
            hardwareMAC: mac,
            isPrivateMAC: SystemParsers.isLocallyAdministeredMAC(mac)
        )
    }

    public func setPower(_ on: Bool) throws {
        guard let iface = wifiClient.interface() else { return }
        try iface.setPower(on)
    }

    public struct ScanResult: Sendable {
        public let uniqueNetworks: [NearbyNetwork]
        public let allBSSIDs: [NearbyNetwork]
    }

    public func scanDetailed() async -> ScanResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let iface = self.wifiClient.interface(), iface.powerOn() else {
                    continuation.resume(returning: ScanResult(uniqueNetworks: [], allBSSIDs: []))
                    return
                }
                let currentSSID = iface.ssid()
                let currentBSSID = iface.bssid()
                let currentCh = iface.wlanChannel()?.channelNumber
                guard let found = try? iface.scanForNetworks(withName: nil) else {
                    continuation.resume(returning: ScanResult(uniqueNetworks: [], allBSSIDs: []))
                    return
                }

                var allBSSIDs: [NearbyNetwork] = []
                var bestBySSID: [String: NearbyNetwork] = [:]

                for net in found {
                    let ch = net.wlanChannel
                    let chNum = ch?.channelNumber ?? 0
                    let name = (net.ssid?.isEmpty == false) ? net.ssid! : "Hidden AP (Ch \(chNum))"
                    let isCur: Bool = {
                        if let cb = currentBSSID, let nb = net.bssid { return cb.lowercased() == nb.lowercased() }
                        if let cs = currentSSID, let ns = net.ssid { return cs == ns && chNum == currentCh }
                        return false
                    }()

                    let item = NearbyNetwork(
                        ssid: name,
                        bssid: net.bssid,
                        rssi: net.rssiValue,
                        channel: chNum,
                        channelWidthMHz: Self.mapWidth(ch?.channelWidth),
                        band: Self.mapBand(ch?.channelBand),
                        security: Self.inferNetworkSecurity(net),
                        isCurrent: isCur
                    )
                    allBSSIDs.append(item)

                    guard let realSSID = net.ssid, !realSSID.isEmpty else { continue }
                    if let existing = bestBySSID[realSSID] {
                        if item.isCurrent || (!existing.isCurrent && item.rssi > existing.rssi) {
                            bestBySSID[realSSID] = item
                        }
                    } else {
                        bestBySSID[realSSID] = item
                    }
                }

                let sortedUnique = bestBySSID.values.sorted { a, b in
                    if a.isCurrent != b.isCurrent { return a.isCurrent }
                    return a.rssi > b.rssi
                }
                let sortedAll = allBSSIDs.sorted { $0.rssi > $1.rssi }
                continuation.resume(returning: ScanResult(uniqueNetworks: sortedUnique, allBSSIDs: sortedAll))
            }
        }
    }

    public func scanNetworks() async -> [NearbyNetwork] {
        await scanDetailed().uniqueNetworks
    }

    /// Re-associates to the strongest BSSID (preferring 5/6 GHz) of the current SSID to fix sticky-client roaming.
    public func roamToBestAP(ssid: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let iface = self.wifiClient.interface() else {
                    continuation.resume(throwing: NSError(domain: "Aether", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Wi-Fi interface"]))
                    return
                }
                do {
                    let candidates = Array(try iface.scanForNetworks(withSSID: ssid.data(using: .utf8)))
                    // Prefer 6 GHz / 5 GHz with usable signal (>= -72 dBm), else strongest RSSI overall
                    let preferred = candidates.sorted { a, b in
                        let aBand = a.wlanChannel?.channelBand
                        let bBand = b.wlanChannel?.channelBand
                        let aFast = (aBand == .band5GHz || aBand == .band6GHz) && a.rssiValue >= -72
                        let bFast = (bBand == .band5GHz || bBand == .band6GHz) && b.rssiValue >= -72
                        if aFast != bFast { return aFast }
                        return a.rssiValue > b.rssiValue
                    }.first
                    guard let target = preferred else {
                        throw NSError(domain: "Aether", code: 2, userInfo: [NSLocalizedDescriptionKey: "No AP found for \(ssid)"])
                    }
                    // nil password uses saved macOS Keychain credentials
                    try iface.associate(to: target, password: nil)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func connect(ssid: String, password: String?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let iface = self.wifiClient.interface() else {
                    continuation.resume(throwing: NSError(domain: "Aether", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Wi-Fi interface available"]))
                    return
                }
                do {
                    let networks = try iface.scanForNetworks(withSSID: ssid.data(using: .utf8))
                    guard let target = networks.sorted(by: { $0.rssiValue > $1.rssiValue }).first else {
                        throw NSError(domain: "Aether", code: 2, userInfo: [NSLocalizedDescriptionKey: "Network \"\(ssid)\" not in range"])
                    }
                    try iface.associate(to: target, password: password?.isEmpty == true ? nil : password)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate & CWEventDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status != .notDetermined {
            cancelLocationTimeout()
            manager.stopUpdatingLocation()
        }
        onLocationAuthorizationChanged?(status)
        onEventChange?()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        cancelLocationTimeout()
        manager.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        cancelLocationTimeout()
        manager.stopUpdatingLocation()
    }

    public func ssidDidChangeForWiFiInterface(withName interfaceName: String) { onEventChange?() }
    public func bssidDidChangeForWiFiInterface(withName interfaceName: String) { onEventChange?() }
    public func linkDidChangeForWiFiInterface(withName interfaceName: String) { onEventChange?() }
    public func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { onEventChange?() }

    // MARK: - CoreWLAN Mappers

    private static func mapBand(_ band: CWChannelBand?) -> WiFiBand {
        guard let band else { return .unknown }
        switch band {
        case .band2GHz: return .band24
        case .band5GHz: return .band5
        case .band6GHz: return .band6
        default: return .unknown
        }
    }

    private static func mapWidth(_ width: CWChannelWidth?) -> Int {
        guard let width else { return 0 }
        switch width {
        case .width20MHz:  return 20
        case .width40MHz:  return 40
        case .width80MHz:  return 80
        case .width160MHz: return 160
        default: return 0
        }
    }

    private static func mapSecurity(_ sec: CWSecurity) -> WiFiSecurityKind {
        switch sec {
        case .none:           return .open
        case .WEP:            return .wep
        case .wpaPersonal, .wpaPersonalMixed: return .wpaPersonal
        case .wpa2Personal:   return .wpa2Personal
        case .wpa2Enterprise: return .wpa2Enterprise
        case .wpa3Personal:   return .wpa3Personal
        case .wpa3Enterprise: return .wpa3Enterprise
        case .wpa3Transition: return .wpa3Transition
        default:              return .unknown
        }
    }

    private static func inferNetworkSecurity(_ net: CWNetwork) -> WiFiSecurityKind {
        if net.supportsSecurity(.wpa3Enterprise) { return .wpa3Enterprise }
        if net.supportsSecurity(.wpa3Personal) { return .wpa3Personal }
        if net.supportsSecurity(.wpa3Transition) { return .wpa3Transition }
        if net.supportsSecurity(.wpa2Enterprise) { return .wpa2Enterprise }
        if net.supportsSecurity(.wpa2Personal) { return .wpa2Personal }
        if net.supportsSecurity(.wpaPersonal) { return .wpaPersonal }
        if net.supportsSecurity(.WEP) { return .wep }
        if net.supportsSecurity(.none) { return .open }
        return .unknown
    }

    private static func mapPHY(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11a:  return "Wi-Fi 2"
        case .mode11b:  return "Wi-Fi 1"
        case .mode11g:  return "Wi-Fi 3"
        case .mode11n:  return "Wi-Fi 4"
        case .mode11ac: return "Wi-Fi 5"
        case .mode11ax: return "Wi-Fi 6"
        default:
            if mode.rawValue >= 7 { return "Wi-Fi 7" }
            return "—"
        }
    }
}
