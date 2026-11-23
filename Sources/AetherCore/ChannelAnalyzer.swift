import Foundation

// MARK: - RF Channel Congestion & Roaming Models

public struct ChannelLobe: Identifiable, Sendable, Equatable {
    public var id: String { "\(ssid)|\(bssid ?? "")|\(channel)" }
    public let ssid: String
    public let bssid: String?
    public let channel: Int
    public let widthMHz: Int
    public let rssi: Int
    public let band: WiFiBand
    public let isCurrent: Bool

    public init(
        ssid: String,
        bssid: String?,
        channel: Int,
        widthMHz: Int,
        rssi: Int,
        band: WiFiBand,
        isCurrent: Bool
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.channel = channel
        self.widthMHz = widthMHz
        self.rssi = rssi
        self.band = band
        self.isCurrent = isCurrent
    }
}

public struct RoamingRecommendation: Sendable, Equatable {
    public let ssid: String
    public let targetBand: WiFiBand
    public let targetChannel: Int
    public let targetRSSI: Int
    public let reason: String

    public init(ssid: String, targetBand: WiFiBand, targetChannel: Int, targetRSSI: Int, reason: String) {
        self.ssid = ssid
        self.targetBand = targetBand
        self.targetChannel = targetChannel
        self.targetRSSI = targetRSSI
        self.reason = reason
    }
}

public struct ChannelAnalysis: Sendable, Equatable {
    public let lobes24GHz: [ChannelLobe]
    public let lobes5GHz: [ChannelLobe]
    public let lobes6GHz: [ChannelLobe]
    public let overlappingCount: Int
    public let congestionLabel: String
    public let recommendedChannel: Int?
    public let recommendationSummary: String
    public let roamingNudge: RoamingRecommendation?

    public init(
        lobes24GHz: [ChannelLobe] = [],
        lobes5GHz: [ChannelLobe] = [],
        lobes6GHz: [ChannelLobe] = [],
        overlappingCount: Int = 0,
        congestionLabel: String = "—",
        recommendedChannel: Int? = nil,
        recommendationSummary: String = "Scan nearby networks to analyze channel overlap",
        roamingNudge: RoamingRecommendation? = nil
    ) {
        self.lobes24GHz = lobes24GHz
        self.lobes5GHz = lobes5GHz
        self.lobes6GHz = lobes6GHz
        self.overlappingCount = overlappingCount
        self.congestionLabel = congestionLabel
        self.recommendedChannel = recommendedChannel
        self.recommendationSummary = recommendationSummary
        self.roamingNudge = roamingNudge
    }

    public func lobes(for band: WiFiBand) -> [ChannelLobe] {
        switch band {
        case .band24:  return lobes24GHz
        case .band5:   return lobes5GHz
        case .band6:   return lobes6GHz
        case .unknown: return lobes24GHz
        }
    }
}

/// Pure RF channel congestion, overlap scoring, best-channel recommendation,
/// and sticky-client roaming detector (replaces WiFi Explorer Pro).
public enum ChannelAnalyzer {

    public static let standard24Channels = [1, 6, 11]
    public static let standard5Channels = [36, 40, 44, 48, 149, 153, 157, 161]

    public static func analyze(current: WiFiSnapshot, rawBSSIDs: [NearbyNetwork]) -> ChannelAnalysis {
        var lobes: [ChannelLobe] = rawBSSIDs.map {
            ChannelLobe(
                ssid: $0.ssid,
                bssid: $0.bssid,
                channel: $0.channel,
                widthMHz: max(20, $0.channelWidthMHz),
                rssi: $0.rssi,
                band: $0.band,
                isCurrent: $0.isCurrent
            )
        }

        // Ensure current AP is represented even if Location redacted SSID in scan
        if current.isConnected && current.channel > 0 && !lobes.contains(where: { $0.isCurrent }) {
            lobes.insert(
                ChannelLobe(
                    ssid: current.ssid ?? "Current AP",
                    bssid: current.bssid,
                    channel: current.channel,
                    widthMHz: max(20, current.channelWidthMHz),
                    rssi: current.rssi,
                    band: current.band,
                    isCurrent: true
                ),
                at: 0
            )
        }

        let l24 = lobes.filter { $0.band == .band24 }.sorted { $0.rssi > $1.rssi }
        let l5 = lobes.filter { $0.band == .band5 }.sorted { $0.rssi > $1.rssi }
        let l6 = lobes.filter { $0.band == .band6 }.sorted { $0.rssi > $1.rssi }

        guard current.isConnected && current.channel > 0 else {
            return ChannelAnalysis(lobes24GHz: l24, lobes5GHz: l5, lobes6GHz: l6)
        }

        let sameBandPeers = lobes.filter { !$0.isCurrent && $0.band == current.band }
        let overlapping = sameBandPeers.filter { peer in
            channelsOverlap(
                chA: current.channel, widthA: max(20, current.channelWidthMHz),
                chB: peer.channel, widthB: max(20, peer.widthMHz),
                band: current.band
            )
        }

        let overlapCount = overlapping.count
        let congestionLabel: String
        if overlapCount == 0 {
            congestionLabel = "CLEAR"
        } else if overlapCount <= 2 {
            congestionLabel = "LIGHT"
        } else if overlapCount <= 5 {
            congestionLabel = "MODERATE"
        } else {
            congestionLabel = "CROWDED"
        }

        // Score candidate channels in the current band (lower interference cost = better)
        let candidates: [Int]
        switch current.band {
        case .band24:  candidates = standard24Channels
        case .band5:   candidates = standard5Channels
        default:       candidates = []
        }

        var bestChannel: Int?
        var bestScore = Double.greatestFiniteMagnitude
        let currentScore = interferenceCost(channel: current.channel, widthMHz: max(20, current.channelWidthMHz), band: current.band, peers: sameBandPeers)

        for cand in candidates {
            let score = interferenceCost(channel: cand, widthMHz: 20, band: current.band, peers: sameBandPeers)
            if score < bestScore {
                bestScore = score
                bestChannel = cand
            }
        }

        let summary: String
        if let best = bestChannel, best != current.channel, (currentScore - bestScore) > 0.35 || (current.band == .band24 && !standard24Channels.contains(current.channel)) {
            summary = "Ch \(current.channel) has \(overlapCount) overlapping AP\(overlapCount == 1 ? "" : "s") · Ch \(best) is cleaner"
        } else if overlapCount == 0 {
            summary = "Ch \(current.channel) (\(current.band.shortBadge)) is interference-free"
        } else {
            summary = "Ch \(current.channel) (\(current.band.shortBadge)) · \(overlapCount) overlapping AP\(overlapCount == 1 ? "" : "s")"
        }

        // Sticky-client roaming detector: check if same SSID has a better 5/6 GHz AP or >=12 dB stronger BSSID
        let roamingNudge = detectRoamingOpportunity(current: current, allBSSIDs: rawBSSIDs)

        return ChannelAnalysis(
            lobes24GHz: l24,
            lobes5GHz: l5,
            lobes6GHz: l6,
            overlappingCount: overlapCount,
            congestionLabel: congestionLabel,
            recommendedChannel: bestChannel,
            recommendationSummary: summary,
            roamingNudge: roamingNudge
        )
    }

    public static func channelsOverlap(chA: Int, widthA: Int, chB: Int, widthB: Int, band: WiFiBand) -> Bool {
        if band == .band24 {
            // 2.4 GHz channels are 5 MHz apart; a 20 MHz channel spans +/-2 channels (40 MHz spans +/-4)
            let halfA = widthA >= 40 ? 4 : 2
            let halfB = widthB >= 40 ? 4 : 2
            return abs(chA - chB) <= (halfA + halfB)
        } else {
            // 5 / 6 GHz channels: 20 MHz = 4 channel steps
            let halfA = max(2, widthA / 10)
            let halfB = max(2, widthB / 10)
            return abs(chA - chB) < (halfA + halfB)
        }
    }

    private static func interferenceCost(channel: Int, widthMHz: Int, band: WiFiBand, peers: [ChannelLobe]) -> Double {
        var cost = 0.0
        for p in peers {
            if channelsOverlap(chA: channel, widthA: widthMHz, chB: p.channel, widthB: p.widthMHz, band: band) {
                // Stronger nearby APs cause disproportionately more contention (-45 dBm = 1.0, -90 dBm = 0.1)
                let powerWeight = max(0.1, min(1.0, Double(p.rssi + 95) / 50.0))
                let exactBonus = (p.channel == channel) ? 1.25 : 0.85
                cost += powerWeight * exactBonus
            }
        }
        return cost
    }

    private static func detectRoamingOpportunity(current: WiFiSnapshot, allBSSIDs: [NearbyNetwork]) -> RoamingRecommendation? {
        guard current.isConnected, let ssid = current.ssid, !ssid.isEmpty else { return nil }
        let sameSSID = allBSSIDs.filter { !$0.isCurrent && $0.ssid == ssid }
        guard !sameSSID.isEmpty else { return nil }

        // 1. Stuck on 2.4 GHz when a usable 5 GHz or 6 GHz AP of the same SSID is nearby
        if current.band == .band24 {
            let fasterBand = sameSSID
                .filter { ($0.band == .band5 || $0.band == .band6) && $0.rssi >= -72 }
                .sorted { $0.rssi > $1.rssi }
            if let best = fasterBand.first {
                return RoamingRecommendation(
                    ssid: ssid,
                    targetBand: best.band,
                    targetChannel: best.channel,
                    targetRSSI: best.rssi,
                    reason: "Stuck on 2.4 GHz — \(best.band.rawValue) AP available (\(best.rssi) dBm, Ch \(best.channel))"
                )
            }
        }

        // 2. Weak signal on current mesh node while another node of the same SSID is >= 12 dB stronger
        if current.rssi <= -68 {
            if let stronger = sameSSID.sorted(by: { $0.rssi > $1.rssi }).first,
               (stronger.rssi - current.rssi) >= 12 {
                return RoamingRecommendation(
                    ssid: ssid,
                    targetBand: stronger.band,
                    targetChannel: stronger.channel,
                    targetRSSI: stronger.rssi,
                    reason: "Stronger \(stronger.band.shortBadge) AP nearby (\(stronger.rssi) vs \(current.rssi) dBm)"
                )
            }
        }

        return nil
    }
}
