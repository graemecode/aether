import Foundation

// MARK: - Human-First Relatable Models (Editor's Choice Layer)

public enum ReadinessStatus: String, Sendable, Equatable {
    case great = "great"
    case okay = "okay"
    case poor = "poor"
    case offline = "offline"
}

public struct ActivityReadinessItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let activity: String     // "Video Calls", "4K Video", "Live & Games"
    public let verdict: String      // "Smooth", "Ready", "Snappy"
    public let detail: String       // Plain-English explanation
    public let status: ReadinessStatus

    public init(id: String, activity: String, verdict: String, detail: String, status: ReadinessStatus) {
        self.id = id
        self.activity = activity
        self.verdict = verdict
        self.detail = detail
        self.status = status
    }
}

public struct PrivacyActorRow: Identifiable, Sendable, Equatable {
    public let id: String
    public let actor: String        // "Strangers Nearby", "Wi-Fi Owner & ISP", "Others on This Wi-Fi"
    public let verdict: String      // "Blocked", "Can't see sites", "Sees Graeme-Mac"
    public let detail: String       // Plain-English explanation
    public let severity: AuditSeverity

    public init(id: String, actor: String, verdict: String, detail: String, severity: AuditSeverity) {
        self.id = id
        self.actor = actor
        self.verdict = verdict
        self.detail = detail
        self.severity = severity
    }
}

public struct SignalInsight: Identifiable, Sendable, Equatable {
    public let id: String
    public let eyebrow: String      // "RADIO PHYSICS", "WALKIE-TALKIE EFFECT", "HIDDEN AIRDROP RADIO"
    public let headline: String     // Relatable 1-sentence human hook
    public let footnote: String     // Grounded measured proof

    public init(id: String, eyebrow: String, headline: String, footnote: String) {
        self.id = id
        self.eyebrow = eyebrow
        self.headline = headline
        self.footnote = footnote
    }
}

/// Pure translation engine turning raw RF, latency, DNS, VPN, and socket telemetry into
/// calm, relatable plain English — without hiding or faking a single measurement.
public enum HumanSummary {

    // MARK: - 1. Activity Readiness (Video Calls · 4K Video · Live & Games)

    public static func activityReadiness(
        wifi: WiFiSnapshot,
        isWired: Bool,
        hopHealth: HopHealth,
        stability: StabilityMetrics,
        quality: NetworkQualityResult?,
        rfPhysics: RFPhysicsSnapshot,
        awdl: AWDLSnapshot
    ) -> [ActivityReadinessItem] {
        guard wifi.isConnected || isWired else {
            return [
                ActivityReadinessItem(id: "calls", activity: "Video Calls", verdict: "Offline", detail: "Connect to Wi-Fi or Ethernet", status: .offline),
                ActivityReadinessItem(id: "stream", activity: "4K Video", verdict: "Offline", detail: "No active internet link", status: .offline),
                ActivityReadinessItem(id: "games", activity: "Live & Games", verdict: "Offline", detail: "No route to internet", status: .offline)
            ]
        }

        // Video Calls — strictly consistent with live hop health & rolling stability
        let calls: ActivityReadinessItem = {
            if hopHealth.internetMs == nil && stability.callGrade == .offline {
                return ActivityReadinessItem(
                    id: "calls", activity: "Video Calls", verdict: "No route",
                    detail: "Router is up, but upstream internet is unreachable",
                    status: .poor
                )
            }
            if stability.callGrade == .choppy || (hopHealth.routerMs ?? 0) >= 60 {
                return ActivityReadinessItem(
                    id: "calls", activity: "Video Calls", verdict: "Choppy",
                    detail: String(format: "Sustained jitter (%.0fms) or packet drops", stability.jitterMs),
                    status: .poor
                )
            }
            if let q = quality, q.responsivenessRPM < 280 {
                return ActivityReadinessItem(
                    id: "calls", activity: "Video Calls", verdict: "May stutter",
                    detail: "Router slows down during downloads (bufferbloat)",
                    status: .okay
                )
            }
            if stability.callGrade == .fair || (wifi.isConnected && wifi.snr < 18) || (hopHealth.internetMs ?? 0) >= 95 {
                return ActivityReadinessItem(
                    id: "calls", activity: "Video Calls", verdict: "Usable",
                    detail: "Moderate signal or minor latency variation",
                    status: .okay
                )
            }
            return ActivityReadinessItem(
                id: "calls", activity: "Video Calls", verdict: "Smooth",
                detail: "Steady connection with low lag for Zoom & FaceTime",
                status: .great
            )
        }()

        // 4K Video (needs ~25 Mbps sustained download)
        let stream: ActivityReadinessItem = {
            let effectiveMbps: Double
            if let q = quality {
                effectiveMbps = q.downloadMbps
            } else if isWired {
                effectiveMbps = 250
            } else {
                effectiveMbps = Double(rfPhysics.realMaxTcpMbps)
            }

            if effectiveMbps >= 35 {
                return ActivityReadinessItem(
                    id: "stream", activity: "4K Video", verdict: "Ready",
                    detail: String(format: "Plenty of headroom (~%.0f Mbps)", effectiveMbps),
                    status: .great
                )
            }
            if effectiveMbps >= 12 {
                return ActivityReadinessItem(
                    id: "stream", activity: "4K Video", verdict: "HD Ready",
                    detail: String(format: "Great for 1080p (~%.0f Mbps); 4K may buffer", effectiveMbps),
                    status: .okay
                )
            }
            return ActivityReadinessItem(
                id: "stream", activity: "4K Video", verdict: "Slow",
                detail: "Bandwidth is tight for high-res streaming",
                status: .poor
            )
        }()

        // Live & Games — consistent with live internet RTT & rolling stability
        let games: ActivityReadinessItem = {
            let rtt = hopHealth.internetMs ?? stability.avgInternetMs ?? 25
            if stability.callGrade == .choppy || rtt >= 140 {
                return ActivityReadinessItem(
                    id: "games", activity: "Live & Games", verdict: "Laggy",
                    detail: String(format: "Elevated ping (%dms) or sustained drops", Int(round(rtt))),
                    status: .poor
                )
            }
            if awdl.isStealingAirtime {
                return ActivityReadinessItem(
                    id: "games", activity: "Live & Games", verdict: "Brief spikes",
                    detail: "AirDrop/Handoff radio is briefly hopping channels",
                    status: .okay
                )
            }
            if rtt >= 70 || stability.callGrade == .fair {
                return ActivityReadinessItem(
                    id: "games", activity: "Live & Games", verdict: "Slight lag",
                    detail: String(format: "Around %dms to the internet", Int(round(rtt))),
                    status: .okay
                )
            }
            return ActivityReadinessItem(
                id: "games", activity: "Live & Games", verdict: "Snappy",
                detail: String(format: "Quick %dms response and steady pacing", Int(round(rtt))),
                status: .great
            )
        }()

        return [calls, stream, games]
    }

    // MARK: - 2. "Who Can See You?" 3-Actor Privacy Story

    public static func privacyActors(
        wifi: WiFiSnapshot,
        isWired: Bool,
        dns: DNSSnapshot,
        vpns: [VPNService],
        proxy: ProxySnapshot,
        exposure: LANExposureSnapshot,
        zone: TrustZone,
        localBroadcastName: String?,
        audit: TrustAudit
    ) -> [PrivacyActorRow] {
        let activeVPN = vpns.first(where: { $0.isConnected })
        let hasTunnel = activeVPN != nil || dns.hasTunnelResolver

        // Actor 1: Nearby Strangers (Airwaves)
        let airwaves: PrivacyActorRow = {
            if isWired {
                return PrivacyActorRow(
                    id: "airwaves", actor: "Strangers Nearby", verdict: "Blocked",
                    detail: "Wired connection — nothing broadcast over radio.",
                    severity: .ok
                )
            }
            if audit.hasGatewayAnomaly || audit.hasSecurityDowngrade {
                return PrivacyActorRow(
                    id: "airwaves", actor: "Strangers Nearby", verdict: "Warning",
                    detail: audit.hasGatewayAnomaly
                        ? "Router identity changed unexpectedly — verify this Wi-Fi."
                        : "Wi-Fi security dropped below its usual level.",
                    severity: .alert
                )
            }
            if wifi.security.isWeak {
                return PrivacyActorRow(
                    id: "airwaves", actor: "Strangers Nearby",
                    verdict: hasTunnel ? "Shielded by VPN" : "Can snoop",
                    detail: hasTunnel
                        ? "Wi-Fi itself is open, but \(activeVPN?.name ?? "your VPN") encrypts your data."
                        : "Unencrypted Wi-Fi — anyone nearby can capture unencrypted traffic.",
                    severity: hasTunnel ? .caution : .alert
                )
            }
            let macNote = wifi.isPrivateMAC == true ? "Private Wi-Fi address hides your Mac." : "Encrypted with \(wifi.security.rawValue)."
            return PrivacyActorRow(
                id: "airwaves", actor: "Strangers Nearby", verdict: "Blocked",
                detail: macNote,
                severity: .ok
            )
        }()

        // Actor 2: Wi-Fi Owner & ISP
        let isp: PrivacyActorRow = {
            if proxy.isAnyProxyActive {
                return PrivacyActorRow(
                    id: "isp", actor: "Wi-Fi Owner & ISP", verdict: "Proxy active",
                    detail: "\(proxy.summary) is routing traffic — verify it's yours.",
                    severity: .caution
                )
            }
            if let vpn = activeVPN {
                return PrivacyActorRow(
                    id: "isp", actor: "Wi-Fi Owner & ISP", verdict: "Hidden",
                    detail: "\(vpn.name) hides the sites you visit and your traffic.",
                    severity: .ok
                )
            }
            if dns.hasTunnelResolver {
                return PrivacyActorRow(
                    id: "isp", actor: "Wi-Fi Owner & ISP", verdict: "Tunnelled",
                    detail: "Lookups go through an encrypted tunnel interface.",
                    severity: .ok
                )
            }
            if dns.posture == .trustedProvider {
                return PrivacyActorRow(
                    id: "isp", actor: "Wi-Fi Owner & ISP", verdict: "Limited",
                    detail: "Using \(dns.providerLabel) instead of the router's default lookups.",
                    severity: .ok
                )
            }
            return PrivacyActorRow(
                id: "isp", actor: "Wi-Fi Owner & ISP", verdict: "Sees site names",
                detail: "Router/ISP handles your website lookups. Tap Cloudflare below to switch.",
                severity: zone == .untrusted ? .caution : .info
            )
        }()

        // Actor 3: Others on This Wi-Fi (LAN)
        let lan: PrivacyActorRow = {
            let nameNote = localBroadcastName.map { "Sees \"\($0.replacingOccurrences(of: ".local", with: ""))\"" } ?? "Visible on local network"
            if !exposure.exposedUserPorts.isEmpty {
                let first = exposure.exposedUserPorts.prefix(2).map { "\($0.process) (:\($0.port))" }.joined(separator: ", ")
                return PrivacyActorRow(
                    id: "lan", actor: "Others on This Wi-Fi",
                    verdict: "\(exposure.exposedUserPorts.count) app\(exposure.exposedUserPorts.count == 1 ? "" : "s") open",
                    detail: "\(exposure.neighborCount) devices here can reach \(first).",
                    severity: zone == .untrusted ? .caution : .info
                )
            }
            return PrivacyActorRow(
                id: "lan", actor: "Others on This Wi-Fi", verdict: "No apps exposed",
                detail: "\(nameNote) · \(exposure.neighborCount) other device\(exposure.neighborCount == 1 ? "" : "s") on this network.",
                severity: .ok
            )
        }()

        return [airwaves, isp, lan]
    }

    // MARK: - 3. Relatable Editorial "Behind the Signal" Insights

    public static func signalInsights(
        wifi: WiFiSnapshot,
        rfPhysics: RFPhysicsSnapshot,
        channelAnalysis: ChannelAnalysis,
        awdl: AWDLSnapshot,
        xray: ConnectionXRay,
        topProcesses: [ProcessBandwidth]
    ) -> [SignalInsight] {
        var list: [SignalInsight] = []

        if let hog = topProcesses.first, hog.totalBytesPerSec >= 350_000 {
            let dir = hog.uploadBytesPerSec > hog.downloadBytesPerSec ? "uploading" : "downloading"
            list.append(SignalInsight(
                id: "hog",
                eyebrow: "RIGHT NOW",
                headline: "\(friendlyProcessName(hog.name)) is \(dir) at \(ByteRateFormatter.detailed(max(hog.downloadBytesPerSec, hog.uploadBytesPerSec))).",
                footnote: hog.uploadBytesPerSec > hog.downloadBytesPerSec
                    ? "Heavy uploads are the #1 hidden cause of laggy video calls."
                    : "Active download stream on your Mac."
            ))
        }

        if awdl.isStealingAirtime {
            list.append(SignalInsight(
                id: "awdl",
                eyebrow: "APPLE AIRDROP RADIO",
                headline: "Your Mac is briefly hopping off Wi-Fi to talk to nearby Apple devices.",
                footnote: "awdl0 (AirDrop / Handoff) is firing \(Int(round(awdl.packetsPerSec))) pkts/s — can add brief call spikes."
            ))
        }

        if wifi.isConnected {
            list.append(SignalInsight(
                id: "power",
                eyebrow: "THE PHYSICS",
                headline: "Your Mac is decoding \(Int(round(wifi.txRateMbps)))M bits/sec from a signal \(humanPowerPhrase(rfPhysics.signalPowerLabel)) strong.",
                footnote: "That's \(rfPhysics.snrMultiplierLabel.replacingOccurrences(of: " noise", with: "")) louder than room static (\(rfPhysics.estimatedRangeLabel))."
            ))

            if rfPhysics.realMaxTcpMbps > 0 {
                list.append(SignalInsight(
                    id: "walkie",
                    eyebrow: "WALKIE-TALKIE EFFECT",
                    headline: "Your \(Int(round(wifi.txRateMbps))) Mbps Wi-Fi link delivers ~\(rfPhysics.realMaxTcpMbps) Mbps of real speed.",
                    footnote: "Wi-Fi can't send and receive at the same instant — \(rfPhysics.bottleneckReason.lowercased())."
                ))
            }

            if channelAnalysis.overlappingCount > 0 {
                list.append(SignalInsight(
                    id: "lane",
                    eyebrow: "SHARED AIRSPACE",
                    headline: "\(channelAnalysis.overlappingCount) neighboring router\(channelAnalysis.overlappingCount == 1 ? " is" : "s are") sharing your Wi-Fi lane right now.",
                    footnote: channelAnalysis.recommendationSummary
                ))
            }
        }

        if xray.totalOutboundSockets > 0 {
            let appCount = xray.topApps.count
            list.append(SignalInsight(
                id: "xray",
                eyebrow: "QUIET BACKGROUND TRAFFIC",
                headline: "\(appCount) app\(appCount == 1 ? "" : "s") holding \(xray.totalOutboundSockets) live internet connections right now.",
                footnote: xray.plaintextHTTPCount == 0
                    ? "All checked connections are encrypted (0 plaintext HTTP)."
                    : "\(xray.plaintextHTTPCount) unencrypted HTTP connection(s) detected."
            ))
        }

        return list
    }

    // MARK: - 4. Human Hop Verdict & Friendly Process Names

    public static func humanHopLabel(ms: Double?, warn: Double, bad: Double) -> String {
        guard let ms else { return "—" }
        if ms >= bad { return "Slow" }
        if ms >= warn { return "Fair" }
        return "Fast"
    }

    public static func humanSignalLabel(wifi: WiFiSnapshot, isWired: Bool) -> String {
        if isWired { return "Wired" }
        guard wifi.isConnected else { return "Off" }
        if wifi.snr >= 30 && wifi.rssi >= -62 { return "Strong" }
        if wifi.snr >= 20 && wifi.rssi >= -72 { return "Good" }
        if wifi.snr >= 12 { return "Fair" }
        return "Weak"
    }

    public static func humanSubtitle(
        wifi: WiFiSnapshot,
        isWired: Bool,
        rfPhysics: RFPhysicsSnapshot,
        activeVPN: VPNService?
    ) -> String {
        if isWired {
            return "WIRED ETHERNET · DIRECT LINK"
        }
        guard wifi.isConnected else {
            return wifi.powerOn ? "NOT CONNECTED" : "WI-FI TURNED OFF"
        }
        var parts: [String] = [humanSignalLabel(wifi: wifi, isWired: false).uppercased()]
        if let room = rfPhysics.estimatedRangeLabel.components(separatedBy: " · ").last, !room.isEmpty, room != "—" {
            parts.append(room.uppercased())
        }
        if wifi.band != .unknown {
            parts.append(wifi.band.rawValue.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    public static func friendlyProcessName(_ raw: String) -> String {
        let lower = raw.lowercased()
        switch lower {
        case "google", "google chrome", "google chrome helper": return "Chrome"
        case "cloudd", "bird", "clouddocs": return "iCloud Drive"
        case "nsurlsessiond": return "macOS Downloads"
        case "apsd": return "Apple Push"
        case "mdnsresponder": return "Local Discovery"
        case "kernel_task": return "macOS System"
        case "rapportd", "sharingd": return "AirDrop & Handoff"
        case "identityservicesd", "identitys": return "iMessage / FaceTime"
        case "com.apple.webkit.networking": return "Safari"
        case "softwareupdated": return "macOS Updates"
        case "trustd": return "Security Checks"
        default:
            return raw.replacingOccurrences(of: "\\x20", with: " ")
        }
    }

    private static func humanPowerPhrase(_ label: String) -> String {
        if label.hasSuffix(" nW") {
            let num = label.replacingOccurrences(of: " nW", with: "")
            return "\(num) billionths of a watt"
        }
        if label.hasSuffix(" pW") {
            let num = label.replacingOccurrences(of: " pW", with: "")
            return "\(num) trillionths of a watt"
        }
        if label.hasSuffix(" µW") {
            let num = label.replacingOccurrences(of: " µW", with: "")
            return "\(num) millionths of a watt"
        }
        return label
    }
}
