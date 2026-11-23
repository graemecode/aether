import Foundation

/// Pure RF physics & Wi-Fi networking calculations that translate cryptic dBm / PHY numbers
/// into intuitive physical reality (signal power in nanowatts, linear SNR multiplier,
/// estimated indoor distance, and half-duplex TCP speed ceiling).
public struct RFPhysicsSnapshot: Sendable, Equatable {
    public let centerFreqMHz: Int
    public let signalPowerLabel: String      // e.g. "39.8 nW"
    public let snrMultiplierLabel: String    // e.g. "6,310× noise"
    public let estimatedRangeLabel: String   // e.g. "~1–3 m · Same room"
    public let realMaxTcpMbps: Int           // Honest half-duplex TCP ceiling
    public let bottleneckReason: String      // Why PHY is capped where it is

    public init(
        centerFreqMHz: Int = 0,
        signalPowerLabel: String = "—",
        snrMultiplierLabel: String = "—",
        estimatedRangeLabel: String = "—",
        realMaxTcpMbps: Int = 0,
        bottleneckReason: String = "—"
    ) {
        self.centerFreqMHz = centerFreqMHz
        self.signalPowerLabel = signalPowerLabel
        self.snrMultiplierLabel = snrMultiplierLabel
        self.estimatedRangeLabel = estimatedRangeLabel
        self.realMaxTcpMbps = realMaxTcpMbps
        self.bottleneckReason = bottleneckReason
    }
}

public struct AWDLSnapshot: Sendable, Equatable {
    public let isActive: Bool
    public let totalPackets: UInt64
    public let packetsPerSec: Double

    public init(isActive: Bool = false, totalPackets: UInt64 = 0, packetsPerSec: Double = 0) {
        self.isActive = isActive
        self.totalPackets = totalPackets
        self.packetsPerSec = packetsPerSec
    }

    public var isStealingAirtime: Bool {
        isActive && packetsPerSec >= 3.0
    }
}

public struct OutboundAppSummary: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let connectionCount: Int
    public let hasPlaintextHTTP: Bool

    public init(name: String, connectionCount: Int, hasPlaintextHTTP: Bool) {
        self.name = name
        self.connectionCount = connectionCount
        self.hasPlaintextHTTP = hasPlaintextHTTP
    }
}

public struct ConnectionXRay: Sendable, Equatable {
    public let totalOutboundSockets: Int
    public let uniqueRemoteHosts: Int
    public let plaintextHTTPCount: Int
    public let continuityPeerLinks: Int
    public let topApps: [OutboundAppSummary]

    public init(
        totalOutboundSockets: Int = 0,
        uniqueRemoteHosts: Int = 0,
        plaintextHTTPCount: Int = 0,
        continuityPeerLinks: Int = 0,
        topApps: [OutboundAppSummary] = []
    ) {
        self.totalOutboundSockets = totalOutboundSockets
        self.uniqueRemoteHosts = uniqueRemoteHosts
        self.plaintextHTTPCount = plaintextHTTPCount
        self.continuityPeerLinks = continuityPeerLinks
        self.topApps = topApps
    }
}

public enum RFPhysics {

    /// IEEE 802.11 center frequency in MHz.
    public static func centerFrequencyMHz(band: WiFiBand, channel: Int) -> Int {
        guard channel > 0 else { return 0 }
        switch band {
        case .band24:
            if channel == 14 { return 2484 }
            return 2407 + channel * 5
        case .band5:
            return 5000 + channel * 5
        case .band6:
            return 5950 + channel * 5
        case .unknown:
            return 0
        }
    }

    /// Converts received dBm (`P_mW = 10^(dBm/10)`) into intuitive SI units (µW / nW / pW).
    public static func formatSignalPower(rssiDbm: Int) -> String {
        guard rssiDbm < 0 else { return "—" }
        let mW = pow(10.0, Double(rssiDbm) / 10.0)
        let uW = mW * 1_000.0
        if uW >= 1.0 {
            return String(format: "%.1f µW", uW)
        }
        let nW = mW * 1_000_000.0
        if nW >= 1.0 {
            return nW >= 100 ? String(format: "%.0f nW", nW) : String(format: "%.1f nW", nW)
        }
        let pW = mW * 1_000_000_000.0
        return pW >= 100 ? String(format: "%.0f pW", pW) : String(format: "%.1f pW", pW)
    }

    /// Converts logarithmic SNR (dB) into exact linear power ratio (`10^(SNR/10)`).
    public static func formatSNRMultiplier(snrDb: Int) -> String {
        guard snrDb > 0 else { return "—" }
        let ratio = pow(10.0, Double(snrDb) / 10.0)
        if ratio >= 1_000_000 {
            return String(format: "%.1fM× noise", ratio / 1_000_000.0)
        }
        if ratio >= 1_000 {
            return String(format: "%.1fK× noise", ratio / 1_000.0)
        }
        return "\(Int(round(ratio)))× noise"
    }

    /// Indoor log-distance path loss approximation (`RSSI = P0 - 10 * n * log10(d)`).
    /// Returns an honest range band rather than false single-centimeter precision.
    public static func estimateIndoorRange(rssiDbm: Int, freqMHz: Int) -> String {
        guard rssiDbm < 0, freqMHz > 0 else { return "—" }
        // Empirical MacBook received RSSI at 1m from typical router (~-30 dBm on 2.4 GHz, ~-36 dBm on 5/6 GHz)
        let refAt1m: Double = freqMHz < 3000 ? -30.0 : -36.0
        let pathLossExp: Double = 2.8 // typical indoor office/home walls
        let d = pow(10.0, (refAt1m - Double(rssiDbm)) / (10.0 * pathLossExp))

        if d < 3.5 { return "~1–3 m · Same room" }
        if d < 8.5 { return "~3–8 m · Nearby" }
        if d < 16.0 { return "~8–16 m · Through walls" }
        return ">16 m · Far / Heavy walls"
    }

    /// Half-duplex Wi-Fi TCP ceiling: CSMA/CA contention + framing overhead caps real TCP
    /// around ~58% of advertised PHY Tx rate, discounted further by overlapping APs.
    public static func compute(wifi: WiFiSnapshot, overlappingAPs: Int) -> RFPhysicsSnapshot {
        guard wifi.isConnected else { return RFPhysicsSnapshot() }

        let freq = centerFrequencyMHz(band: wifi.band, channel: wifi.channel)
        let power = formatSignalPower(rssiDbm: wifi.rssi)
        let snrMult = formatSNRMultiplier(snrDb: wifi.snr)
        let range = estimateIndoorRange(rssiDbm: wifi.rssi, freqMHz: freq)

        let contentionFactor = max(0.55, 1.0 - Double(min(overlappingAPs, 8)) * 0.05)
        let realTcp = Int(round(wifi.txRateMbps * 0.58 * contentionFactor))

        let bottleneck: String
        if wifi.band == .band24 && wifi.channelWidthMHz <= 20 {
            bottleneck = "2.4 GHz · 20 MHz width caps airlink"
        } else if wifi.snr < 20 {
            bottleneck = "Low SNR (\(wifi.snr) dB) throttling modulation"
        } else if overlappingAPs >= 4 {
            bottleneck = "\(overlappingAPs) competing APs sharing airtime"
        } else if wifi.channelWidthMHz >= 80 {
            bottleneck = "Wide \(wifi.channelWidthMHz) MHz \(wifi.band.shortBadge) channel"
        } else {
            bottleneck = "Half-duplex Wi-Fi framing overhead (~58%)"
        }

        return RFPhysicsSnapshot(
            centerFreqMHz: freq,
            signalPowerLabel: power,
            snrMultiplierLabel: snrMult,
            estimatedRangeLabel: range,
            realMaxTcpMbps: realTcp,
            bottleneckReason: bottleneck
        )
    }
}
