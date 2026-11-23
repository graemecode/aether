import Foundation

// MARK: - Continuous Latency, Jitter, Packet Loss & Event Log (Replaces PingPlotter / PeakHour)

public struct LatencySample: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let routerMs: Double?
    public let dnsMs: Double?
    public let internetMs: Double?

    public init(id: UUID = UUID(), timestamp: Date = Date(), routerMs: Double?, dnsMs: Double?, internetMs: Double?) {
        self.id = id
        self.timestamp = timestamp
        self.routerMs = routerMs
        self.dnsMs = dnsMs
        self.internetMs = internetMs
    }

    public var isDrop: Bool {
        internetMs == nil
    }
}

public enum CallReadinessGrade: String, Sendable, Equatable {
    case solid = "SOLID"
    case fair = "FAIR"
    case choppy = "CHOPPY"
    case offline = "OFFLINE"
}

public struct StabilityMetrics: Sendable, Equatable {
    public let avgInternetMs: Double?
    public let jitterMs: Double
    public let packetLossPercent: Double
    public let callGrade: CallReadinessGrade
    public let verdict: String

    public init(
        avgInternetMs: Double? = nil,
        jitterMs: Double = 0,
        packetLossPercent: Double = 0,
        callGrade: CallReadinessGrade = .offline,
        verdict: String = "Collecting stability samples…"
    ) {
        self.avgInternetMs = avgInternetMs
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
        self.callGrade = callGrade
        self.verdict = verdict
    }
}

public enum NetworkEventKind: String, Sendable, Equatable {
    case roam = "ROAM"
    case bandChange = "BAND"
    case latencySpike = "SPIKE"
    case packetDrop = "DROP"
    case gatewayChange = "GATEWAY"
    case vpnChange = "VPN"
    case captivePortal = "PORTAL"
    case connected = "LINK"
}

public struct NetworkEvent: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let kind: NetworkEventKind
    public let title: String
    public let detail: String
    public let severity: AuditSeverity

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: NetworkEventKind,
        title: String,
        detail: String,
        severity: AuditSeverity
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public enum StabilityCalculator {
    public static func compute(samples: [LatencySample]) -> StabilityMetrics {
        guard !samples.isEmpty else { return StabilityMetrics() }

        // Evaluate over the most recent 20 samples so old startup/wake transients don't poison live status
        let window = Array(samples.suffix(20))
        let total = window.count
        let successes = window.compactMap(\.internetMs)
        let lost = total - successes.count
        let lossPct = (Double(lost) / Double(total)) * 100.0
        let latestDropped = window.last?.isDrop ?? false

        guard !successes.isEmpty else {
            return StabilityMetrics(
                avgInternetMs: nil,
                jitterMs: 0,
                packetLossPercent: 100,
                callGrade: .offline,
                verdict: "No upstream packets reaching the internet"
            )
        }

        // Median latency & median consecutive delta (robust against single cold-start TLS outliers)
        let sortedRtt = successes.sorted()
        let medianRtt = sortedRtt[sortedRtt.count / 2]

        var jitter = 0.0
        if successes.count >= 2 {
            var deltas: [Double] = []
            deltas.reserveCapacity(successes.count - 1)
            for i in 1..<successes.count {
                deltas.append(abs(successes[i] - successes[i - 1]))
            }
            deltas.sort()
            jitter = deltas[deltas.count / 2]
        }

        // Require either >= 4 samples or a live drop before escalating loss to choppy
        let meaningfulLoss = (total >= 4 || latestDropped) ? lossPct : 0.0

        let grade: CallReadinessGrade
        let verdict: String
        if meaningfulLoss >= 8.0 || jitter >= 35.0 || medianRtt >= 180.0 || (latestDropped && lost >= 2) {
            grade = .choppy
            verdict = String(format: "Choppy for calls · %.0fms jitter · %.0f%% loss", jitter, lossPct)
        } else if meaningfulLoss >= 2.0 || jitter >= 14.0 || medianRtt >= 95.0 {
            grade = .fair
            verdict = String(format: "Usable for calls · %.1fms jitter · %.0f%% loss", jitter, lossPct)
        } else {
            grade = .solid
            verdict = String(format: "Rock solid for Zoom & SSH · %.1fms jitter · %.0f%% loss", jitter, lossPct)
        }

        return StabilityMetrics(
            avgInternetMs: medianRtt,
            jitterMs: jitter,
            packetLossPercent: lossPct,
            callGrade: grade,
            verdict: verdict
        )
    }
}

// MARK: - DNS Presets & Captive Portal & Wi-Fi QR Formatting

public enum DNSPreset: String, CaseIterable, Identifiable, Sendable {
    case automatic = "auto"
    case cloudflare = "cloudflare"
    case quad9 = "quad9"
    case google = "google"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic:  return "AUTO"
        case .cloudflare: return "1.1.1.1"
        case .quad9:      return "QUAD9"
        case .google:     return "8.8.8.8"
        }
    }

    public var servers: [String] {
        switch self {
        case .automatic:  return ["Empty"]
        case .cloudflare: return ["1.1.1.1", "1.0.0.1"]
        case .quad9:      return ["9.9.9.9", "149.112.112.112"]
        case .google:     return ["8.8.8.8", "8.8.4.4"]
        }
    }
}

public enum CaptivePortalState: Sendable, Equatable {
    case clear
    case detected(loginURL: String)

    public var isDetected: Bool {
        if case .detected = self { return true }
        return false
    }
}

public enum WiFiQRPayload {
    /// Escapes special characters per the standard `WIFI:T:...;S:...;P:...;;` QR payload format.
    public static func escape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for ch in value {
            if ch == "\\" || ch == ";" || ch == "," || ch == ":" || ch == "\"" {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    public static func make(ssid: String, password: String?, security: WiFiSecurityKind) -> String {
        let authType: String
        switch security {
        case .open: authType = "nopass"
        case .wep:  authType = "WEP"
        default:    authType = "WPA"
        }
        let escSSID = escape(ssid)
        if let password, !password.isEmpty, authType != "nopass" {
            return "WIFI:T:\(authType);S:\(escSSID);P:\(escape(password));;"
        }
        return "WIFI:T:\(authType);S:\(escSSID);;"
    }
}
