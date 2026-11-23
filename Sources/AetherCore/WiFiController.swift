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

        public init(uniqueNetworks: [NearbyNetwork], allBSSIDs: [NearbyNetwork]) {
            self.uniqueNetworks = uniqueNetworks
            self.allBSSIDs = allBSSIDs
        }
    }

    /// Structured, plain-English Wi-Fi association errors — never exposes cryptic CoreWLAN strings like `tmpErr`.
    public enum WiFiJoinError: LocalizedError, Equatable, Sendable {
        case noInterface
        case notInRange(ssid: String)
        case passwordRequired(ssid: String, isKnown: Bool, isSandboxed: Bool)
        case authenticationFailed(ssid: String)
        case timedOut(ssid: String)
        case busyOrTemporary(ssid: String)
        case permissionDenied(ssid: String)
        case failed(ssid: String, detail: String)

        public var needsPasswordPrompt: Bool {
            switch self {
            case .passwordRequired, .authenticationFailed:
                return true
            default:
                return false
            }
        }

        public var errorDescription: String? {
            switch self {
            case .noInterface:
                return "No Wi-Fi interface is available on this Mac."
            case .notInRange(let ssid):
                return "\"\(ssid)\" is out of range right now."
            case .passwordRequired(let ssid, let isKnown, let isSandboxed):
                if isKnown && isSandboxed {
                    return "macOS sandbox can't read saved Keychain passwords — enter the password once or join via macOS Wi-Fi."
                }
                if isKnown {
                    return "Couldn't unlock the saved password for \"\(ssid)\" — enter it below or join via macOS Wi-Fi."
                }
                return "Enter the Wi-Fi password for \"\(ssid)\"."
            case .authenticationFailed(let ssid):
                return "Incorrect password for \"\(ssid)\"."
            case .timedOut(let ssid):
                return "Timed out joining \"\(ssid)\" — if it's a Personal Hotspot, wake your iPhone or use macOS Wi-Fi."
            case .busyOrTemporary(let ssid):
                return "Wi-Fi radio was busy joining \"\(ssid)\" — try again or use macOS Wi-Fi."
            case .permissionDenied(let ssid):
                return "macOS requires System Settings permission to join \"\(ssid)\"."
            case .failed(let ssid, let detail):
                return "Couldn't join \"\(ssid)\" — \(detail)"
            }
        }
    }

    /// Reads macOS's in-memory CoreWLAN scan cache in <1ms so the Wi-Fi list populates immediately
    /// while a fresh active scan runs in the background.
    public func cachedScanDetailed() -> ScanResult {
        guard let iface = wifiClient.interface(), iface.powerOn(),
              let cached = iface.cachedScanResults(), !cached.isEmpty else {
            return ScanResult(uniqueNetworks: [], allBSSIDs: [])
        }
        return Self.buildScanResult(
            from: cached,
            currentSSID: iface.ssid(),
            currentBSSID: iface.bssid(),
            currentChannel: iface.wlanChannel()?.channelNumber
        )
    }

    /// Runs a fresh active Wi-Fi scan. Returns `nil` if the radio is busy and the scan fails
    /// (with no usable cache fallback) so callers never wipe an existing list to empty.
    public func scanDetailedFresh() async -> ScanResult? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let iface = self.wifiClient.interface() else {
                    continuation.resume(returning: ScanResult(uniqueNetworks: [], allBSSIDs: []))
                    return
                }
                guard iface.powerOn() else {
                    continuation.resume(returning: ScanResult(uniqueNetworks: [], allBSSIDs: []))
                    return
                }
                let currentSSID = iface.ssid()
                let currentBSSID = iface.bssid()
                let currentCh = iface.wlanChannel()?.channelNumber

                if let found = try? iface.scanForNetworks(withName: nil), !found.isEmpty {
                    let result = Self.buildScanResult(
                        from: found,
                        currentSSID: currentSSID,
                        currentBSSID: currentBSSID,
                        currentChannel: currentCh
                    )
                    continuation.resume(returning: result)
                    return
                }

                // Active scan failed (e.g. airportd busy mid-association) — fall back to macOS cached scan if available.
                if let cached = iface.cachedScanResults(), !cached.isEmpty {
                    let result = Self.buildScanResult(
                        from: cached,
                        currentSSID: currentSSID,
                        currentBSSID: currentBSSID,
                        currentChannel: currentCh
                    )
                    continuation.resume(returning: result)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    public func scanDetailed() async -> ScanResult {
        await scanDetailedFresh() ?? ScanResult(uniqueNetworks: [], allBSSIDs: [])
    }

    private static func buildScanResult(
        from networks: Set<CWNetwork>,
        currentSSID: String?,
        currentBSSID: String?,
        currentChannel: Int?
    ) -> ScanResult {
        var allBSSIDs: [NearbyNetwork] = []
        var bestBySSID: [String: NearbyNetwork] = [:]

        for net in networks {
            let ch = net.wlanChannel
            let chNum = ch?.channelNumber ?? 0
            let name = (net.ssid?.isEmpty == false) ? net.ssid! : "Hidden AP (Ch \(chNum))"
            let isCur: Bool = {
                if let cb = currentBSSID, let nb = net.bssid { return cb.lowercased() == nb.lowercased() }
                if let cs = currentSSID, let ns = net.ssid { return cs == ns && (currentChannel == nil || chNum == currentChannel) }
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
        return ScanResult(uniqueNetworks: sortedUnique, allBSSIDs: sortedAll)
    }

    public func scanNetworks() async -> [NearbyNetwork] {
        await scanDetailed().uniqueNetworks
    }

    /// Re-associates to the strongest BSSID (preferring 5/6 GHz) of the current SSID to fix sticky-client roaming.
    public func roamToBestAP(ssid: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let iface = self.wifiClient.interface() else {
                    continuation.resume(throwing: WiFiJoinError.noInterface)
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
                        throw WiFiJoinError.notInRange(ssid: ssid)
                    }
                    try iface.associate(to: target, password: nil)
                    continuation.resume()
                } catch let joinErr as WiFiJoinError {
                    continuation.resume(throwing: joinErr)
                } catch {
                    continuation.resume(throwing: Self.classifyJoinError(
                        error,
                        ssid: ssid,
                        hadPassword: false,
                        isKnown: true,
                        isSandboxed: NativeNetworkTelemetry.isSandboxed
                    ))
                }
            }
        }
    }

    /// Joins a Wi-Fi network.
    /// In direct builds (`!APP_STORE`), uses macOS's Apple-signed `networksetup -setairportnetwork` first
    /// so saved Keychain networks join in 1 click without re-entering the password (and newly entered passwords
    /// are saved to Keychain automatically). In Mac App Store sandbox builds, uses pure CoreWLAN with clean
    /// plain-English error classification.
    public func connect(ssid: String, password: String?, isKnown: Bool = false) async throws {
        let cleanPassword = (password?.isEmpty == true) ? nil : password
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let iface = self.wifiClient.interface() else {
                    continuation.resume(throwing: WiFiJoinError.noInterface)
                    return
                }

                // Short-circuit if already associated to this exact SSID — avoids redundant CoreWLAN `tmpErr`.
                if let current = iface.ssid(), current == ssid, iface.rssiValue() < 0 {
                    continuation.resume()
                    return
                }

                let ifaceName = iface.interfaceName ?? "en0"
                #if !APP_STORE
                if !NativeNetworkTelemetry.isSandboxed {
                    var args = ["-setairportnetwork", ifaceName, ssid]
                    if let pw = cleanPassword {
                        args.append(pw)
                    }
                    let (output, exitCode) = Self.runNetworkSetup(arguments: args, timeoutSeconds: 14.0)

                    // Check live interface first — macOS sometimes joins cleanly even with noisy stderr.
                    if let current = iface.ssid(), current == ssid, iface.rssiValue() < 0 {
                        continuation.resume()
                        return
                    }

                    if let parsedErr = Self.parseNetworkSetupJoinFailure(
                        output: output,
                        exitCode: exitCode,
                        ssid: ssid,
                        hadPassword: cleanPassword != nil,
                        isKnown: isKnown
                    ) {
                        // If user supplied a password and `networksetup` failed only due to permission/busy,
                        // try direct CoreWLAN association before failing.
                        if cleanPassword != nil, case .permissionDenied = parsedErr {
                            // Fall through to CoreWLAN below
                        } else if cleanPassword != nil, case .busyOrTemporary = parsedErr {
                            // Fall through to CoreWLAN below
                        } else {
                            continuation.resume(throwing: parsedErr)
                            return
                        }
                    } else if exitCode == 0 {
                        continuation.resume()
                        return
                    }
                }
                #endif

                do {
                    var networks = (try? iface.scanForNetworks(withSSID: ssid.data(using: .utf8))) ?? []
                    if networks.isEmpty, let cached = iface.cachedScanResults() {
                        networks = Set(cached.filter { $0.ssid == ssid })
                    }
                    guard let target = networks.sorted(by: { $0.rssiValue > $1.rssiValue }).first else {
                        throw WiFiJoinError.notInRange(ssid: ssid)
                    }
                    try iface.associate(to: target, password: cleanPassword)
                    continuation.resume()
                } catch let joinErr as WiFiJoinError {
                    continuation.resume(throwing: joinErr)
                } catch {
                    #if APP_STORE
                    let sandboxed = true
                    #else
                    let sandboxed = NativeNetworkTelemetry.isSandboxed
                    #endif
                    continuation.resume(throwing: Self.classifyJoinError(
                        error,
                        ssid: ssid,
                        hadPassword: cleanPassword != nil,
                        isKnown: isKnown,
                        isSandboxed: sandboxed
                    ))
                }
            }
        }
    }

    #if !APP_STORE
    private static func runNetworkSetup(arguments: [String], timeoutSeconds: Double) -> (output: String, exitCode: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = arguments

        let combinedPipe = Pipe()
        proc.standardOutput = combinedPipe
        proc.standardError = combinedPipe
        proc.standardInput = FileHandle.nullDevice

        let lock = NSLock()
        var finished = false
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler {
            lock.withLock {
                guard !finished && proc.isRunning else { return }
                proc.terminate()
            }
        }
        timer.resume()

        do {
            try proc.run()
            let data = combinedPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            timer.cancel()
            lock.withLock { finished = true }
            try? combinedPipe.fileHandleForReading.close()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (text, proc.terminationStatus)
        } catch {
            timer.cancel()
            lock.withLock { finished = true }
            try? combinedPipe.fileHandleForReading.close()
            return ("", -1)
        }
    }
    #endif

    /// Parses stdout/stderr and exit code from `networksetup -setairportnetwork`.
    /// Note: `networksetup` often returns exit code `0` even when it prints `Could not find network` or `Failed to join network`.
    public static func parseNetworkSetupJoinFailure(
        output: String,
        exitCode: Int32,
        ssid: String,
        hadPassword: Bool,
        isKnown: Bool
    ) -> WiFiJoinError? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if trimmed.isEmpty && exitCode == 0 {
            return nil
        }
        if lower.contains("could not find network") || lower.contains("not found") {
            return .notInRange(ssid: ssid)
        }
        if lower.contains("timeout") || lower.contains("-3905") || lower.contains("timed out") {
            return .timedOut(ssid: ssid)
        }
        if lower.contains("not authorized") || lower.contains("not permitted") || lower.contains("-3930") || lower.contains("requires admin") {
            return .permissionDenied(ssid: ssid)
        }
        if lower.contains("failed to join") || lower.contains("invalid") || lower.contains("incorrect") || lower.contains("passphrase") || lower.contains("-3924") || lower.contains("-3908") || lower.contains("-3900") || lower.contains("tmperr") {
            if hadPassword {
                return .authenticationFailed(ssid: ssid)
            }
            return .passwordRequired(ssid: ssid, isKnown: isKnown, isSandboxed: false)
        }
        if exitCode != 0 || lower.contains("error") {
            if exitCode == 15 || exitCode == 9 { // SIGTERM / SIGKILL from timeout
                return .timedOut(ssid: ssid)
            }
            if !hadPassword {
                return .passwordRequired(ssid: ssid, isKnown: isKnown, isSandboxed: false)
            }
            return .busyOrTemporary(ssid: ssid)
        }
        return nil
    }

    /// Translates raw CoreWLAN / OSStatus NSErrors (including cryptic `tmpErr` / `-3900`) into clean, actionable messages.
    public static func classifyJoinError(
        _ error: Error,
        ssid: String,
        hadPassword: Bool,
        isKnown: Bool,
        isSandboxed: Bool
    ) -> WiFiJoinError {
        if let joinErr = error as? WiFiJoinError {
            return joinErr
        }
        let ns = error as NSError
        let code = ns.code
        let desc = ns.localizedDescription.lowercased()

        if desc.contains("not in range") || desc.contains("could not find") {
            return .notInRange(ssid: ssid)
        }
        if code == -3905 || code == -3925 || desc.contains("timeout") || desc.contains("timed out") {
            return .timedOut(ssid: ssid)
        }
        if code == -3930 || desc.contains("not permitted") || desc.contains("not authorized") {
            return .permissionDenied(ssid: ssid)
        }
        // -3900 (kCWInvalidParameterErr), -3908 (kCWAssociationDeniedErr), -3924 (kCWInvalidPMKErr), or CoreWLAN `tmpErr`
        if code == -3900 || code == -3908 || code == -3924 || code == 1 || desc.contains("tmperr") || desc.contains("passphrase") || desc.contains("authentication") {
            if hadPassword {
                return .authenticationFailed(ssid: ssid)
            }
            return .passwordRequired(ssid: ssid, isKnown: isKnown, isSandboxed: isSandboxed)
        }
        if code == -3931 || code == -3929 || code == -3906 || code == -3902 {
            return .busyOrTemporary(ssid: ssid)
        }
        if !hadPassword {
            return .passwordRequired(ssid: ssid, isKnown: isKnown, isSandboxed: isSandboxed)
        }
        return .busyOrTemporary(ssid: ssid)
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
