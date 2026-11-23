import Foundation

// MARK: - Trust & Security Enums

public enum TrustLevel: String, Sendable, Equatable, Codable {
    case shielded   // Encrypted link + VPN / encrypted DNS, no anomalies
    case trusted    // Strong link, clean route, expected fingerprint
    case caution    // Plaintext DNS, fixed MAC on public Wi-Fi, exposed ports, or weak link
    case alert      // Open Wi-Fi, ARP/gateway anomaly, security downgrade, or captive/proxy intercept
    case offline    // No active link

    public var label: String {
        switch self {
        case .shielded: return "SHIELDED"
        case .trusted:  return "TRUSTED"
        case .caution:  return "CAUTION"
        case .alert:    return "ALERT"
        case .offline:  return "OFFLINE"
        }
    }
}

public enum TrustZone: String, CaseIterable, Identifiable, Sendable, Codable {
    case home = "home"
    case work = "work"
    case untrusted = "untrusted"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .home:      return "HOME"
        case .work:      return "WORK"
        case .untrusted: return "PUBLIC"
        }
    }

    public var subtitle: String {
        switch self {
        case .home:      return "Relaxed local port & MAC checks"
        case .work:      return "Standard corporate / studio posture"
        case .untrusted: return "Strict public Wi-Fi shield checks"
        }
    }
}

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case iconOnly = "iconOnly"
    case autoSpeed = "autoSpeed"
    case alwaysSpeed = "alwaysSpeed"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .iconOnly:    return "ICON"
        case .autoSpeed:   return "AUTO"
        case .alwaysSpeed: return "SPEED"
        }
    }
}

public enum StageMode: Int, CaseIterable, Identifiable, Sendable {
    case flux = 0
    case spectrum = 1
    case route = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .flux:     return "Flux"
        case .spectrum: return "Spectrum"
        case .route:    return "Route"
        }
    }
}

public enum PanelTab: Int, CaseIterable, Identifiable, Sendable {
    case speed = 0
    case shield = 1
    case networks = 2
    case tools = 3

    public var id: Int { rawValue }

    public var shortLabel: String {
        switch self {
        case .speed:    return "SPEED"
        case .shield:   return "PRIVACY"
        case .networks: return "WI-FI"
        case .tools:    return "MORE"
        }
    }

    public var help: String {
        switch self {
        case .speed:    return "Activity readiness, live speed, insights & top apps"
        case .shield:   return "Who can see your traffic, private lookups & LAN devices"
        case .networks: return "Switch Wi-Fi networks, share QR code & VPN tunnels"
        case .tools:    return "Simple/Pro view, menu bar style, IPs & quick fixes"
        }
    }
}

// MARK: - Wi-Fi & RF Models

public enum WiFiBand: String, Sendable, Equatable, Codable {
    case band24 = "2.4 GHz"
    case band5 = "5 GHz"
    case band6 = "6 GHz"
    case unknown = "—"

    public var shortBadge: String {
        switch self {
        case .band24:  return "2.4G"
        case .band5:   return "5G"
        case .band6:   return "6G"
        case .unknown: return "—"
        }
    }
}

public enum WiFiSecurityKind: String, Sendable, Equatable, Codable {
    case open = "Open"
    case wep = "WEP"
    case wpaPersonal = "WPA"
    case wpa2Personal = "WPA2"
    case wpa2Enterprise = "WPA2-Ent"
    case wpa3Personal = "WPA3"
    case wpa3Enterprise = "WPA3-Ent"
    case wpa3Transition = "WPA2/3"
    case unknown = "Unknown"

    public var strengthRank: Int {
        switch self {
        case .open:           return 0
        case .wep:            return 1
        case .wpaPersonal:    return 2
        case .wpa2Personal:   return 3
        case .wpa2Enterprise: return 4
        case .wpa3Transition: return 4
        case .wpa3Personal:   return 5
        case .wpa3Enterprise: return 6
        case .unknown:        return 2
        }
    }

    public var isWeak: Bool {
        self == .open || self == .wep || self == .wpaPersonal
    }
}

public struct WiFiSnapshot: Sendable, Equatable {
    public var interfaceName: String
    public var powerOn: Bool
    public var isConnected: Bool
    public var ssid: String?
    public var bssid: String?
    public var rssi: Int
    public var noise: Int
    public var txRateMbps: Double
    public var channel: Int
    public var band: WiFiBand
    public var channelWidthMHz: Int
    public var phyGeneration: String
    public var security: WiFiSecurityKind
    public var hardwareMAC: String?
    public var isPrivateMAC: Bool?

    public init(
        interfaceName: String = "en0",
        powerOn: Bool = false,
        isConnected: Bool = false,
        ssid: String? = nil,
        bssid: String? = nil,
        rssi: Int = 0,
        noise: Int = 0,
        txRateMbps: Double = 0,
        channel: Int = 0,
        band: WiFiBand = .unknown,
        channelWidthMHz: Int = 0,
        phyGeneration: String = "—",
        security: WiFiSecurityKind = .unknown,
        hardwareMAC: String? = nil,
        isPrivateMAC: Bool? = nil
    ) {
        self.interfaceName = interfaceName
        self.powerOn = powerOn
        self.isConnected = isConnected
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.noise = noise
        self.txRateMbps = txRateMbps
        self.channel = channel
        self.band = band
        self.channelWidthMHz = channelWidthMHz
        self.phyGeneration = phyGeneration
        self.security = security
        self.hardwareMAC = hardwareMAC
        self.isPrivateMAC = isPrivateMAC
    }

    public var snr: Int {
        guard isConnected, rssi < 0, noise < 0 else { return 0 }
        return max(0, rssi - noise)
    }

    /// Normalized 0...1 signal quality from RSSI (-90 dBm .. -45 dBm)
    public var signalFraction: Double {
        guard isConnected, rssi < 0 else { return 0 }
        let clamped = Double(min(max(rssi, -90), -45))
        return (clamped + 90.0) / 45.0
    }

    public var signalBars: Int {
        guard isConnected else { return 0 }
        if rssi >= -55 { return 4 }
        if rssi >= -67 { return 3 }
        if rssi >= -77 { return 2 }
        return 1
    }

    public var signalVerdict: String {
        guard isConnected else { return powerOn ? "Disconnected" : "Wi-Fi Off" }
        if snr >= 35 && rssi >= -60 { return "Excellent link" }
        if snr >= 25 && rssi >= -70 { return "Strong link" }
        if snr >= 15 && rssi >= -78 { return "Fair link" }
        return "Weak / noisy signal"
    }
}

public struct NearbyNetwork: Identifiable, Sendable, Equatable {
    public var id: String { "\(ssid)|\(bssid ?? "")|\(channel)" }
    public let ssid: String
    public let bssid: String?
    public let rssi: Int
    public let channel: Int
    public let channelWidthMHz: Int
    public let band: WiFiBand
    public let security: WiFiSecurityKind
    public let isCurrent: Bool

    public init(
        ssid: String,
        bssid: String?,
        rssi: Int,
        channel: Int,
        channelWidthMHz: Int = 20,
        band: WiFiBand,
        security: WiFiSecurityKind,
        isCurrent: Bool = false
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.channel = channel
        self.channelWidthMHz = channelWidthMHz
        self.band = band
        self.security = security
        self.isCurrent = isCurrent
    }

    public var signalBars: Int {
        if rssi >= -55 { return 4 }
        if rssi >= -67 { return 3 }
        if rssi >= -77 { return 2 }
        return 1
    }
}

// MARK: - Throughput & Speed Models

public struct ThroughputSample: Sendable, Equatable {
    public let timestamp: Date
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double

    public init(timestamp: Date = Date(), downloadBytesPerSec: Double, uploadBytesPerSec: Double) {
        self.timestamp = timestamp
        self.downloadBytesPerSec = max(0, downloadBytesPerSec)
        self.uploadBytesPerSec = max(0, uploadBytesPerSec)
    }
}

public struct ProcessBandwidth: Identifiable, Sendable, Equatable {
    public var id: String { appBundlePath ?? "proc:\(name.lowercased())" }
    public let name: String
    public let pid: Int
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    public let appBundlePath: String?
    public let processCount: Int

    public init(
        name: String,
        pid: Int,
        downloadBytesPerSec: Double,
        uploadBytesPerSec: Double,
        appBundlePath: String? = nil,
        processCount: Int = 1
    ) {
        self.name = name
        self.pid = pid
        self.downloadBytesPerSec = max(0, downloadBytesPerSec)
        self.uploadBytesPerSec = max(0, uploadBytesPerSec)
        self.appBundlePath = appBundlePath
        self.processCount = max(1, processCount)
    }

    public var totalBytesPerSec: Double {
        downloadBytesPerSec + uploadBytesPerSec
    }
}

public enum ActiveInterfaceKind: String, Sendable, Equatable {
    case wifi
    case ethernet
    case vpn
    case other

    public var sortRank: Int {
        switch self {
        case .wifi: return 0
        case .ethernet: return 1
        case .vpn: return 2
        case .other: return 3
        }
    }
}

public struct ActiveInterface: Identifiable, Sendable, Equatable {
    public var id: String { "\(bsdName):\(ipAddress)" }
    public let bsdName: String
    public let kind: ActiveInterfaceKind
    public let displayName: String
    public let ipAddress: String
    public let isPrimary: Bool

    public init(
        bsdName: String,
        kind: ActiveInterfaceKind,
        displayName: String,
        ipAddress: String,
        isPrimary: Bool = false
    ) {
        self.bsdName = bsdName
        self.kind = kind
        self.displayName = displayName
        self.ipAddress = ipAddress
        self.isPrimary = isPrimary
    }
}

public struct HopHealth: Sendable, Equatable {
    public var routerMs: Double?
    public var dnsMs: Double?
    public var internetMs: Double?
    public var updatedAt: Date?

    public init(routerMs: Double? = nil, dnsMs: Double? = nil, internetMs: Double? = nil, updatedAt: Date? = nil) {
        self.routerMs = routerMs
        self.dnsMs = dnsMs
        self.internetMs = internetMs
        self.updatedAt = updatedAt
    }

    public var bottleneckSummary: String {
        if routerMs == nil && internetMs == nil { return "Probing route…" }
        if let r = routerMs, r > 35 { return "Local Wi-Fi / router latency high (\(Int(r)) ms)" }
        if let d = dnsMs, d > 80 { return "DNS lookup sluggish (\(Int(d)) ms)" }
        if let w = internetMs, w > 120 { return "Upstream ISP latency elevated (\(Int(w)) ms)" }
        if internetMs == nil && routerMs != nil { return "Router reachable, no upstream internet" }
        return "Route clean across all hops"
    }
}

public struct NetworkQualityResult: Sendable, Equatable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let responsivenessRPM: Int
    public let baseRttMs: Double
    public let loadedRttMs: Double?
    public let endpoint: String?
    public let measuredAt: Date

    public init(
        downloadMbps: Double,
        uploadMbps: Double,
        responsivenessRPM: Int,
        baseRttMs: Double,
        loadedRttMs: Double?,
        endpoint: String?,
        measuredAt: Date = Date()
    ) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.responsivenessRPM = responsivenessRPM
        self.baseRttMs = baseRttMs
        self.loadedRttMs = loadedRttMs
        self.endpoint = endpoint
        self.measuredAt = measuredAt
    }

    public var responsivenessRating: String {
        if responsivenessRPM >= 800 { return "HIGH" }
        if responsivenessRPM >= 350 { return "MEDIUM" }
        return "LOW"
    }

    public var plainEnglishVerdict: String {
        let bloatRatio: Double = {
            guard let loaded = loadedRttMs, baseRttMs > 0 else { return 1.0 }
            return loaded / baseRttMs
        }()
        if responsivenessRPM >= 800 {
            return "Snappy under load — great for video calls & SSH"
        }
        if bloatRatio >= 4.0 || responsivenessRPM < 280 {
            return "Bufferbloat under load — calls may stutter during transfers"
        }
        return "Solid throughput, moderate latency under heavy load"
    }
}

// MARK: - Route, DNS, VPN, Exposure & Audit Models

public struct RouteInfo: Sendable, Equatable {
    public var defaultInterface: String?
    public var gatewayIP: String?
    public var localIP: String?
    public var gatewayMAC: String?

    public init(defaultInterface: String? = nil, gatewayIP: String? = nil, localIP: String? = nil, gatewayMAC: String? = nil) {
        self.defaultInterface = defaultInterface
        self.gatewayIP = gatewayIP
        self.localIP = localIP
        self.gatewayMAC = gatewayMAC
    }
}

public enum DNSPostureKind: String, Sendable, Equatable {
    case vpnTunnel = "VPN DNS"
    case trustedProvider = "Privacy DNS"
    case localRouter = "Router / ISP DNS"
    case custom = "Custom DNS"
    case unknown = "No DNS"
}

public struct DNSSnapshot: Sendable, Equatable {
    public var servers: [String]
    public var providerLabel: String
    public var posture: DNSPostureKind
    public var hasTunnelResolver: Bool
    public var tunnelInterface: String?

    public init(
        servers: [String] = [],
        providerLabel: String = "—",
        posture: DNSPostureKind = .unknown,
        hasTunnelResolver: Bool = false,
        tunnelInterface: String? = nil
    ) {
        self.servers = servers
        self.providerLabel = providerLabel
        self.posture = posture
        self.hasTunnelResolver = hasTunnelResolver
        self.tunnelInterface = tunnelInterface
    }
}

public struct VPNService: Identifiable, Sendable, Equatable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String
    public let bundleID: String?
    public let status: String
    public var isConnected: Bool { status.lowercased() == "connected" }

    public init(uuid: String, name: String, bundleID: String?, status: String) {
        self.uuid = uuid
        self.name = name
        self.bundleID = bundleID
        self.status = status
    }
}

public struct ProxySnapshot: Sendable, Equatable {
    public var httpEnabled: Bool
    public var httpsEnabled: Bool
    public var socksEnabled: Bool
    public var pacEnabled: Bool
    public var summary: String

    public init(httpEnabled: Bool = false, httpsEnabled: Bool = false, socksEnabled: Bool = false, pacEnabled: Bool = false, summary: String = "Direct") {
        self.httpEnabled = httpEnabled
        self.httpsEnabled = httpsEnabled
        self.socksEnabled = socksEnabled
        self.pacEnabled = pacEnabled
        self.summary = summary
    }

    public var isAnyProxyActive: Bool {
        httpEnabled || httpsEnabled || socksEnabled || pacEnabled
    }
}

public struct ExposedPort: Identifiable, Sendable, Equatable {
    public var id: String { "\(process).\(pid).\(port)" }
    public let process: String
    public let pid: Int
    public let port: Int
    public let isSystemDaemon: Bool

    public init(process: String, pid: Int, port: Int, isSystemDaemon: Bool) {
        self.process = process
        self.pid = pid
        self.port = port
        self.isSystemDaemon = isSystemDaemon
    }
}

public struct LANExposureSnapshot: Sendable, Equatable {
    public var neighborCount: Int
    public var exposedUserPorts: [ExposedPort]
    public var exposedSystemPorts: [ExposedPort]

    public init(neighborCount: Int = 0, exposedUserPorts: [ExposedPort] = [], exposedSystemPorts: [ExposedPort] = []) {
        self.neighborCount = neighborCount
        self.exposedUserPorts = exposedUserPorts
        self.exposedSystemPorts = exposedSystemPorts
    }
}

public struct PublicIPInfo: Sendable, Equatable {
    public let ip: String
    public let org: String?
    public let city: String?
    public let country: String?
    public let fetchedAt: Date

    public init(ip: String, org: String?, city: String?, country: String?, fetchedAt: Date = Date()) {
        self.ip = ip
        self.org = org
        self.city = city
        self.country = country
        self.fetchedAt = fetchedAt
    }

    public var locationSummary: String {
        let parts = [city, country].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? "" : parts.joined(separator: ", ")
    }
}

public struct NetworkFingerprint: Sendable, Equatable, Codable {
    public let ssid: String
    public var knownBSSIDs: [String]
    public var gatewayMAC: String?
    public var strongestSecurityRank: Int
    public var lastSeen: Date

    public init(ssid: String, knownBSSIDs: [String], gatewayMAC: String?, strongestSecurityRank: Int, lastSeen: Date = Date()) {
        self.ssid = ssid
        self.knownBSSIDs = knownBSSIDs
        self.gatewayMAC = gatewayMAC
        self.strongestSecurityRank = strongestSecurityRank
        self.lastSeen = lastSeen
    }
}

public enum AuditSeverity: Int, Sendable, Equatable, Comparable {
    case ok = 0
    case info = 1
    case caution = 2
    case alert = 3

    public static func < (lhs: AuditSeverity, rhs: AuditSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AuditCheck: Identifiable, Sendable, Equatable {
    public let id: String
    public let category: String
    public let title: String
    public let detail: String
    public let severity: AuditSeverity

    public init(id: String, category: String, title: String, detail: String, severity: AuditSeverity) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public struct TrustAudit: Sendable, Equatable {
    public let level: TrustLevel
    public let score: Int
    public let headline: String
    public let checks: [AuditCheck]
    public let hasGatewayAnomaly: Bool
    public let hasSecurityDowngrade: Bool

    public init(
        level: TrustLevel = .offline,
        score: Int = 0,
        headline: String = "Disconnected",
        checks: [AuditCheck] = [],
        hasGatewayAnomaly: Bool = false,
        hasSecurityDowngrade: Bool = false
    ) {
        self.level = level
        self.score = score
        self.headline = headline
        self.checks = checks
        self.hasGatewayAnomaly = hasGatewayAnomaly
        self.hasSecurityDowngrade = hasSecurityDowngrade
    }
}

// MARK: - Formatting Helpers

public enum ByteRateFormatter {
    /// Compact menu-bar / HUD formatter: e.g. "0K", "48K", "4.2M", "1.1G"
    public static func compact(_ bytesPerSec: Double) -> String {
        let b = max(0, bytesPerSec)
        if b < 1_024 {
            return "\(Int(b))B"
        }
        let kb = b / 1_024.0
        if kb < 999.5 {
            return kb < 10 ? String(format: "%.1fK", kb) : String(format: "%.0fK", kb)
        }
        let mb = kb / 1_024.0
        if mb < 999.5 {
            return mb < 10 ? String(format: "%.1fM", mb) : String(format: "%.0fM", mb)
        }
        let gb = mb / 1_024.0
        return String(format: "%.1fG", gb)
    }

    /// Detailed rate formatter: e.g. "12.4 MB/s" or "340 KB/s"
    public static func detailed(_ bytesPerSec: Double) -> String {
        let b = max(0, bytesPerSec)
        if b < 1_024 {
            return "\(Int(b)) B/s"
        }
        let kb = b / 1_024.0
        if kb < 1_000 {
            return kb < 100 ? String(format: "%.1f KB/s", kb) : String(format: "%.0f KB/s", kb)
        }
        let mb = kb / 1_024.0
        if mb < 1_000 {
            return mb < 10 ? String(format: "%.2f MB/s", mb) : String(format: "%.1f MB/s", mb)
        }
        let gb = mb / 1_024.0
        return String(format: "%.2f GB/s", gb)
    }

    /// Clean menu-bar rate formatter with explicit unit and 3-digit precision: e.g. "0 B/s", "45.0 KB/s", "544 KB/s", "21.9 MB/s"
    public static func menuBar(_ bytesPerSec: Double) -> String {
        let b = max(0, bytesPerSec)
        if b < 1_024 {
            return "\(Int(b)) B/s"
        }
        let kb = b / 1_024.0
        if kb < 999.5 {
            if kb < 10 { return String(format: "%.2f KB/s", kb) }
            if kb < 100 { return String(format: "%.1f KB/s", kb) }
            return String(format: "%.0f KB/s", kb)
        }
        let mb = kb / 1_024.0
        if mb < 999.5 {
            if mb < 10 { return String(format: "%.2f MB/s", mb) }
            if mb < 100 { return String(format: "%.1f MB/s", mb) }
            return String(format: "%.0f MB/s", mb)
        }
        let gb = mb / 1_024.0
        return String(format: "%.1f GB/s", gb)
    }

    public static func totalBytes(_ bytes: UInt64) -> String {
        let d = Double(bytes)
        if d < 1_024 { return "\(bytes) B" }
        let kb = d / 1_024
        if kb < 1_024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1_024
        if mb < 1_024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1_024
        return String(format: "%.2f GB", gb)
    }

    public static func ms(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        if v < 10 { return String(format: "%.1fms", v) }
        return "\(Int(round(v)))ms"
    }
}
