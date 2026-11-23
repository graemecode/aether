import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - On-Device Network Intelligence (Apple FoundationModels on macOS 26+, Deterministic Fallback)

public struct NetworkAdvisorInput: Sendable, Equatable {
    public let wifi: WiFiSnapshot
    public let isWired: Bool
    public let hopHealth: HopHealth
    public let stability: StabilityMetrics
    public let channelAnalysis: ChannelAnalysis
    public let rfPhysics: RFPhysicsSnapshot
    public let awdl: AWDLSnapshot
    public let trustAudit: TrustAudit
    public let trustZone: TrustZone
    public let vpns: [VPNService]
    public let dns: DNSSnapshot
    public let exposure: LANExposureSnapshot
    public let throughput: ThroughputSample
    public let sessionPeakBytesPerSec: Double
    public let topProcesses: [ProcessBandwidth]
    public let qualityResult: NetworkQualityResult?
    public let events: [NetworkEvent]

    public init(
        wifi: WiFiSnapshot,
        isWired: Bool,
        hopHealth: HopHealth,
        stability: StabilityMetrics,
        channelAnalysis: ChannelAnalysis,
        rfPhysics: RFPhysicsSnapshot,
        awdl: AWDLSnapshot,
        trustAudit: TrustAudit,
        trustZone: TrustZone,
        vpns: [VPNService],
        dns: DNSSnapshot,
        exposure: LANExposureSnapshot,
        throughput: ThroughputSample,
        sessionPeakBytesPerSec: Double,
        topProcesses: [ProcessBandwidth],
        qualityResult: NetworkQualityResult?,
        events: [NetworkEvent]
    ) {
        self.wifi = wifi
        self.isWired = isWired
        self.hopHealth = hopHealth
        self.stability = stability
        self.channelAnalysis = channelAnalysis
        self.rfPhysics = rfPhysics
        self.awdl = awdl
        self.trustAudit = trustAudit
        self.trustZone = trustZone
        self.vpns = vpns
        self.dns = dns
        self.exposure = exposure
        self.throughput = throughput
        self.sessionPeakBytesPerSec = sessionPeakBytesPerSec
        self.topProcesses = topProcesses
        self.qualityResult = qualityResult
        self.events = events
    }
}

public struct NetworkDiagnosis: Sendable, Equatable {
    public let summary: String
    public let nextStep: String
    public let usedOnDeviceModel: Bool
    public let generatedAt: Date

    public init(summary: String, nextStep: String, usedOnDeviceModel: Bool, generatedAt: Date = Date()) {
        self.summary = summary
        self.nextStep = nextStep
        self.usedOnDeviceModel = usedOnDeviceModel
        self.generatedAt = generatedAt
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct GeneratedNetworkDiagnosis {
    @Guide(description: "One sharp, factual, plain-English sentence (max 150 characters) explaining the actual state and bottleneck of this Mac's Wi-Fi.")
    var summary: String

    @Guide(description: "One short practical recommendation (max 90 characters) strictly matching the provided measurements, or a brief all-clear note.")
    var nextStep: String
}
#endif

public enum LocalNetworkAdvisor {

    /// Returns `true` when Apple's on-device FoundationModels LLM is ready on this Mac (macOS 26+, Apple Intelligence enabled).
    public static var isOnDeviceModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    // MARK: - 1. Grounded Natural-English Telemetry Brief (100% English for NLLanguageRecognizer + Zero Hallucination)

    public static func buildGroundedContext(from input: NetworkAdvisorInput) -> String {
        var lines: [String] = []

        if input.isWired {
            lines.append("The Mac is connected over wired Ethernet.")
        } else if input.wifi.isConnected {
            let ssid = input.wifi.ssid ?? "an unnamed Wi-Fi network"
            let band = input.wifi.band.rawValue
            let phy = Int(round(input.wifi.txRateMbps))
            let bandNote = (input.wifi.band == .band5 || input.wifi.band == .band6)
                ? "already on the fast \(band) band"
                : "on the 2.4 GHz band"
            lines.append("The Mac is connected to the Wi-Fi network named \(ssid) on channel \(input.wifi.channel) (\(bandNote)) with a \(HumanSummary.humanSignalLabel(wifi: input.wifi, isWired: false).lowercased()) local signal (\(input.wifi.snr) dB signal-to-noise ratio and a \(phy) Mbps local radio link).")
        } else {
            lines.append("The Mac is currently disconnected from Wi-Fi and Ethernet.")
        }

        // Hops & stability
        var hopParts: [String] = []
        if let r = input.hopHealth.routerMs { hopParts.append("local router ping is \(Int(round(r))) ms") }
        if let d = input.hopHealth.dnsMs { hopParts.append("website lookup is \(Int(round(d))) ms") }
        if let w = input.hopHealth.internetMs {
            let qual: String
            if w >= 400 { qual = "very slow upstream (typical of satellite or heavily congested links)" }
            else if w >= 150 { qual = "slow upstream" }
            else if w >= 70 { qual = "moderate" }
            else { qual = "fast" }
            hopParts.append("internet round-trip latency is \(Int(round(w))) ms (\(qual))")
        } else if input.wifi.isConnected || input.isWired {
            hopParts.append("upstream internet is currently unreachable")
        }
        if !hopParts.isEmpty {
            lines.append("Measured path timing: \(hopParts.joined(separator: ", ")), with \(Int(round(input.stability.packetLossPercent))) percent packet loss and \(String(format: "%.1f", input.stability.jitterMs)) ms jitter.")
        }

        // Live throughput & top active apps
        let downStr = ByteRateFormatter.menuBar(input.throughput.downloadBytesPerSec)
        let upStr = ByteRateFormatter.menuBar(input.throughput.uploadBytesPerSec)
        var trafficLine = "Live network traffic right now is \(downStr) download and \(upStr) upload"
        if input.sessionPeakBytesPerSec >= 1_024 {
            trafficLine += ", with a session peak of \(ByteRateFormatter.menuBar(input.sessionPeakBytesPerSec))"
        }
        trafficLine += "."
        lines.append(trafficLine)

        let activeApps = input.topProcesses.filter { $0.totalBytesPerSec >= 2_048 }.prefix(3)
        if !activeApps.isEmpty {
            let appList = activeApps.map { proc -> String in
                let dir = proc.uploadBytesPerSec > proc.downloadBytesPerSec ? "uploading" : "downloading"
                return "\(proc.name) (\(dir) \(ByteRateFormatter.menuBar(proc.totalBytesPerSec)))"
            }.joined(separator: ", ")
            lines.append("The busiest applications on this Mac right now are \(appList).")
        }

        if let q = input.qualityResult {
            lines.append("A speed test measured \(Int(round(q.downloadMbps))) Mbps download, \(Int(round(q.uploadMbps))) Mbps upload, and \(q.responsivenessRPM) RPM loaded responsiveness (\(q.responsivenessRating.lowercased())).")
        }

        // Channel contention & roaming
        if input.wifi.isConnected {
            if let roam = input.channelAnalysis.roamingNudge {
                lines.append("Sticky client detected: a stronger \(roam.targetBand.rawValue) access point for the same network is available nearby.")
            } else if input.channelAnalysis.overlappingCount >= 3 {
                lines.append("Channel interference: \(input.channelAnalysis.recommendationSummary).")
            } else {
                lines.append("Radio channel interference is low (\(input.channelAnalysis.overlappingCount) overlapping access points).")
            }
            if input.awdl.isStealingAirtime {
                lines.append("Apple AirDrop peer-to-peer radio (awdl0) is actively hopping channels and borrowing Wi-Fi airtime.")
            }
        }

        // Security & Privacy
        let activeVPN = input.vpns.first(where: { $0.isConnected })
        let vpnText = activeVPN != nil
            ? "\(activeVPN!.name) VPN is already connected and encrypting traffic"
            : (input.dns.hasTunnelResolver ? "a VPN tunnel is already active" : "no VPN is currently connected")
        let secText = input.wifi.security == .open ? "an open unencrypted Wi-Fi network" : "\(input.wifi.security.rawValue) encrypted Wi-Fi"
        lines.append("Security posture: this is \(secText) marked as \(input.trustZone.label.lowercased()) with \(input.exposure.neighborCount) other devices on the local network, and \(vpnText).")

        // Recent events (for Studio post-mortem & Q&A)
        if !input.events.isEmpty {
            let recent = input.events.prefix(6).map { "\($0.kind.rawValue): \($0.title) (\($0.detail))" }.joined(separator: "; ")
            lines.append("Recent connection events: \(recent).")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 2. Deterministic Ground-Truth Fallback (Instant, Always Accurate, Zero Hallucination)

    public static func deterministicDiagnosis(from input: NetworkAdvisorInput) -> NetworkDiagnosis {
        guard input.wifi.isConnected || input.isWired else {
            return NetworkDiagnosis(
                summary: input.wifi.powerOn
                    ? "Your Mac is offline right now."
                    : "Wi-Fi radio is turned off.",
                nextStep: input.wifi.powerOn
                    ? "Pick a nearby Wi-Fi network to connect."
                    : "Turn Wi-Fi back on from the top-right button.",
                usedOnDeviceModel: false
            )
        }

        let activeVPN = input.vpns.first(where: { $0.isConnected })
        let hasVPN = activeVPN != nil || input.dns.hasTunnelResolver
        let topApp = input.topProcesses.first(where: { $0.totalBytesPerSec >= 50_000 })

        // Priority 1: Upstream unreachable
        if input.hopHealth.internetMs == nil && input.hopHealth.routerMs != nil {
            return NetworkDiagnosis(
                summary: "Local Wi-Fi and router are reachable (\(Int(round(input.hopHealth.routerMs ?? 0))) ms), but upstream internet isn't responding.",
                nextStep: "Check for a Wi-Fi sign-in portal or wait for upstream recovery.",
                usedOnDeviceModel: false
            )
        }

        // Priority 2: High satellite / congested upstream RTT
        if let rtt = input.hopHealth.internetMs, rtt >= 220 {
            let localPart = input.wifi.isConnected
                ? "Local Wi-Fi is \(HumanSummary.humanSignalLabel(wifi: input.wifi, isWired: false).lowercased())"
                : "Ethernet link is up"
            let uploadClause: String
            let step: String
            if let hog = topApp, hog.uploadBytesPerSec >= 50_000 {
                uploadClause = " while \(hog.name) uploads at \(ByteRateFormatter.menuBar(hog.uploadBytesPerSec))"
                step = "Pause large uploads from \(hog.name) to keep browsing responsive."
            } else {
                uploadClause = ""
                step = "Expect lag on video calls and live apps; fine for async text and browsing."
            }
            return NetworkDiagnosis(
                summary: "\(localPart), but upstream internet is slow at \(Int(round(rtt))) ms\(uploadClause).",
                nextStep: step,
                usedOnDeviceModel: false
            )
        }

        // Priority 3: Sticky client 2.4 -> 5 GHz roaming opportunity
        if let roam = input.channelAnalysis.roamingNudge {
            return NetworkDiagnosis(
                summary: "Connected on crowded 2.4 GHz even though a faster \(roam.targetBand.rawValue) signal for \(roam.ssid) is nearby.",
                nextStep: "Switch to \(roam.targetBand.rawValue) in the Wi-Fi tab to cut jitter and boost speed.",
                usedOnDeviceModel: false
            )
        }

        // Priority 4: Local Wi-Fi / router bottleneck
        if let routerMs = input.hopHealth.routerMs, routerMs >= 35 {
            return NetworkDiagnosis(
                summary: "Local Wi-Fi to your router is sluggish (\(Int(round(routerMs))) ms) with \(input.channelAnalysis.overlappingCount) overlapping networks.",
                nextStep: input.channelAnalysis.recommendedChannel != nil
                    ? "Move closer to the router or switch to cleaner channel \(input.channelAnalysis.recommendedChannel!)."
                    : "Move closer to the access point or pause heavy local transfers.",
                usedOnDeviceModel: false
            )
        }

        // Priority 5: Open public Wi-Fi without VPN
        if input.wifi.security == .open && !hasVPN {
            return NetworkDiagnosis(
                summary: "Fast connection (\(Int(round(input.hopHealth.internetMs ?? 0))) ms), but this open Wi-Fi is unencrypted with \(input.exposure.neighborCount) nearby devices.",
                nextStep: "Connect a VPN before sensitive work or keep traffic strictly HTTPS.",
                usedOnDeviceModel: false
            )
        }

        // Priority 6: Clean healthy connection
        let rttText = input.hopHealth.internetMs.map { "\(Int(round($0))) ms internet ping" } ?? "steady route"
        let shieldText = hasVPN ? " and shielded by \(activeVPN?.name ?? "VPN")" : ""
        let summary: String
        if let hog = topApp {
            let dir = hog.uploadBytesPerSec > hog.downloadBytesPerSec ? "uploading" : "downloading"
            summary = "Healthy link (\(rttText)\(shieldText)); \(hog.name) is actively \(dir) at \(ByteRateFormatter.menuBar(hog.totalBytesPerSec))."
        } else {
            summary = "Strong, steady connection (\(rttText), \(Int(round(input.stability.packetLossPercent)))% loss\(shieldText))."
        }
        return NetworkDiagnosis(
            summary: summary,
            nextStep: "All clear for video calls, 4K streaming, and SSH.",
            usedOnDeviceModel: false
        )
    }

    // MARK: - 3. On-Device LLM Synthesis (Concise Situational Brief)

    public static func generateDiagnosis(from input: NetworkAdvisorInput) async -> NetworkDiagnosis {
        let fallback = deterministicDiagnosis(from: input)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let facts = buildGroundedContext(from: input)
            let instructions = """
            You are Aether, a calm and precise macOS Wi-Fi engineer.
            Explain what is actually happening with this Mac's connection in plain English, grounded strictly in the provided measurements.
            Strict rules:
            - Cite only numbers present in the facts. Never invent metrics.
            - Never suggest switching to 5 GHz or 6 GHz if the Mac is already on 5 GHz or 6 GHz.
            - Never suggest turning on a VPN if a VPN is already connected.
            - Never suggest connecting to a different Wi-Fi network if the bottleneck is satellite/in-flight upstream or if no better network is listed.
            - Connect interacting causes (for example: strong cabin Wi-Fi + slow 640 ms upstream + active upload app).
            - Keep wording crisp, factual, and free of filler or greetings.
            """
            let prompt = """
            Summarize this Mac Wi-Fi connection in plain English based on these live measurements:
            \(facts)

            Deterministic baseline assessment (do not contradict these core facts):
            - \(fallback.summary)
            - \(fallback.nextStep)
            """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedNetworkDiagnosis.self,
                    options: GenerationOptions(temperature: 0.15)
                )
                let sum = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let tip = response.content.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sum.isEmpty && !tip.isEmpty && !containsContradiction(text: "\(sum) \(tip)", input: input) {
                    return NetworkDiagnosis(summary: sum, nextStep: tip, usedOnDeviceModel: true)
                }
            } catch {
                // Gracefully fall back to deterministic ground-truth diagnosis
            }
        }
        #endif

        return fallback
    }

    // MARK: - 4. Studio Event-Log Post-Mortem ("Explain Recent Events")

    public static func explainEvents(from input: NetworkAdvisorInput) async -> (text: String, usedOnDeviceModel: Bool) {
        let fallback = deterministicEventExplanation(from: input)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let facts = buildGroundedContext(from: input)
            let instructions = """
            You are Aether, a terse macOS Wi-Fi engineer.
            Write two short, plain-English sentences explaining what the recent connection events and current telemetry mean together.
            Never invent events or numbers. No bullet points, no markdown, no greetings.
            """
            let prompt = """
            Explain the recent connection history and current stability for this Mac in plain English:
            \(facts)
            """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.2)
                )
                let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && !containsContradiction(text: cleaned, input: input) {
                    return (cleaned, true)
                }
            } catch {
                // Fall back cleanly
            }
        }
        #endif

        return (fallback, false)
    }

    // MARK: - 5. Studio "Ask Aether" Natural-Language Q&A (100% On-Device)

    public static func answer(question: String, input: NetworkAdvisorInput) async -> (text: String, usedOnDeviceModel: Bool) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let d = deterministicDiagnosis(from: input)
            return ("\(d.summary) \(d.nextStep)", false)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let facts = buildGroundedContext(from: input)
            let instructions = """
            You are Aether, an on-device macOS Wi-Fi and networking engineer.
            Answer the user's question directly in 2 to 4 concise sentences of plain English using ONLY the measured telemetry provided.
            Rules:
            - Never invent metrics or claim speeds that weren't measured.
            - Never suggest switching to 5 GHz if already on 5 GHz or 6 GHz.
            - Never suggest turning on a VPN if a VPN is already connected.
            - If the user asks for an ISP or IT support note, write a concise, ready-to-paste factual summary citing exact gateway, SNR, latency, and loss numbers.
            - No markdown formatting, no greetings.
            """
            let prompt = """
            User question: \(trimmed)

            Live Mac network measurements:
            \(facts)
            """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.2)
                )
                let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && !containsContradiction(text: cleaned, input: input) {
                    return (cleaned, true)
                }
            } catch {
                // Fall back to deterministic answer below
            }
        }
        #endif

        return (deterministicAnswer(for: trimmed, input: input), false)
    }

    // MARK: - Safety Verifier (Blocks Classic 3B Hallucinations Before They Ever Reach UI)

    public static func containsContradiction(text: String, input: NetworkAdvisorInput) -> Bool {
        let lower = text.lowercased()
        // Never tell someone already on 5/6 GHz to switch to 5 GHz
        if (input.wifi.band == .band5 || input.wifi.band == .band6) &&
            (lower.contains("switch to 5 ghz") || lower.contains("move to 5 ghz") || lower.contains("change to 5 ghz")) {
            return true
        }
        // Never tell someone whose VPN is already connected to enable/turn on a VPN
        let hasVPN = input.vpns.contains(where: { $0.isConnected }) || input.dns.hasTunnelResolver
        if hasVPN && (lower.contains("turn on a vpn") || lower.contains("enable a vpn") || lower.contains("connect a vpn") || lower.contains("use a vpn")) {
            return true
        }
        return false
    }

    private static func deterministicEventExplanation(from input: NetworkAdvisorInput) -> String {
        if input.events.isEmpty {
            let d = deterministicDiagnosis(from: input)
            return "No roams, band drops, or latency spikes have occurred during this session. \(d.summary)"
        }
        let drops = input.events.filter { $0.kind == .packetDrop }.count
        let spikes = input.events.filter { $0.kind == .latencySpike }.count
        let roams = input.events.filter { $0.kind == .roam || $0.kind == .bandChange }.count
        var parts: [String] = []
        if drops > 0 { parts.append("\(drops) upstream drop\(drops == 1 ? "" : "s")") }
        if spikes > 0 { parts.append("\(spikes) latency spike\(spikes == 1 ? "" : "s")") }
        if roams > 0 { parts.append("\(roams) access point/band change\(roams == 1 ? "" : "s")") }
        let summary = parts.isEmpty ? "\(input.events.count) network state transitions" : parts.joined(separator: ", ")
        let d = deterministicDiagnosis(from: input)
        return "Recorded \(summary) recently. \(d.summary)"
    }

    private static func deterministicAnswer(for question: String, input: NetworkAdvisorInput) -> String {
        let q = question.lowercased()
        if q.contains("isp") || q.contains("support") || q.contains("report") || q.contains("ticket") {
            let ssid = input.wifi.ssid ?? "Wi-Fi"
            let r = input.hopHealth.routerMs.map { "\(Int(round($0))) ms" } ?? "n/a"
            let w = input.hopHealth.internetMs.map { "\(Int(round($0))) ms" } ?? "unreachable"
            return "Network diagnostics on \(ssid) (\(input.wifi.band.rawValue) Ch \(input.wifi.channel), \(input.wifi.snr) dB SNR): local router ping is \(r), upstream internet RTT is \(w), jitter \(String(format: "%.1f", input.stability.jitterMs)) ms, packet loss \(Int(round(input.stability.packetLossPercent)))%."
        }
        let d = deterministicDiagnosis(from: input)
        return "\(d.summary) \(d.nextStep)"
    }
}
