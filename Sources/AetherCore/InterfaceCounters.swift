import Darwin
import Foundation

/// Zero-subprocess POSIX `getifaddrs` counter reader for:
/// - Real-time per-interface byte throughput (`en0` / active route)
/// - Actual over-the-air MAC address on `en0` (detects macOS Private Wi-Fi Address accurately!)
/// - Native global IPv6 presence (non-link-local `fe80::`)
/// - Apple's secret peer-to-peer Wi-Fi radio (`awdl0`) status & live packet rate
public final class InterfaceCounters: @unchecked Sendable {
    public struct Totals: Sendable, Equatable {
        public let bytesIn: UInt64
        public let bytesOut: UInt64
        public let timestamp: Date
    }

    public struct SampleResult: Sendable, Equatable {
        public let sample: ThroughputSample
        public let sessionDownBytes: UInt64
        public let sessionUpBytes: UInt64
        public let sessionPeakBytesPerSec: Double
        public let localIP: String?
        public let activeInterfaces: [ActiveInterface]
        public let activeWiFiMAC: String?
        public let hasGlobalIPv6: Bool
        public let awdl: AWDLSnapshot
    }

    private let lock = NSLock()
    private var previous: Totals?
    private var lastInterface: String?
    private var sessionDown: UInt64 = 0
    private var sessionUp: UInt64 = 0
    private var sessionPeak: Double = 0
    private var prevAwdlPackets: UInt64?
    private var prevAwdlDate: Date?

    public init() {}

    /// Picks the physical wire interface for accurate throughput accounting even under split-tunnel VPNs.
    /// When `defaultInterface` is a virtual L3 tunnel (`utun*`/`ipsec*`/`ppp*`), measuring the underlying
    /// physical interface (`en0` on Wi-Fi) captures both tunneled and direct wire traffic without undercounting.
    public static func physicalThroughputInterface(
        defaultInterface: String?,
        wifiInterface: String,
        wifiConnected: Bool
    ) -> String {
        if let def = defaultInterface, !def.isEmpty {
            let isTunnel = def.hasPrefix("utun") || def.hasPrefix("ipsec") || def.hasPrefix("ppp")
            if !isTunnel {
                return def
            }
        }
        return wifiConnected ? wifiInterface : (defaultInterface ?? wifiInterface)
    }

    /// Pure classification helper for building the clean `Wi-Fi` / `Ethernet` / `VPN` active interfaces list.
    public static func buildActiveInterfaces(
        ipv4Map: [String: String],
        wifiInterface: String = "en0",
        primaryInterface: String? = nil,
        connectedVPNName: String? = nil
    ) -> [ActiveInterface] {
        var result: [ActiveInterface] = []
        for (name, ip) in ipv4Map {
            if name.hasPrefix("bridge") || name.hasPrefix("ap") || name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("anpi") {
                continue
            }
            let kind: ActiveInterfaceKind
            let display: String
            if name == wifiInterface {
                kind = .wifi
                display = "Wi-Fi"
            } else if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                kind = .vpn
                if let vpnName = connectedVPNName, !vpnName.isEmpty {
                    display = "VPN · \(vpnName)"
                } else {
                    display = "VPN"
                }
            } else if name.hasPrefix("en") {
                kind = .ethernet
                display = "Ethernet"
            } else {
                kind = .other
                display = name
            }
            result.append(ActiveInterface(
                bsdName: name,
                kind: kind,
                displayName: display,
                ipAddress: ip,
                isPrimary: name == primaryInterface
            ))
        }
        result.sort { a, b in
            if a.kind.sortRank != b.kind.sortRank { return a.kind.sortRank < b.kind.sortRank }
            if a.isPrimary != b.isPrimary { return a.isPrimary }
            return a.bsdName < b.bsdName
        }
        return result
    }

    /// Call on Mac sleep/wake so the first post-wake sample starts clean without a phantom spike.
    public func resetBaseline() {
        lock.withLock {
            previous = nil
            prevAwdlPackets = nil
            prevAwdlDate = nil
        }
    }

    public func readSample(
        preferredInterface: String? = nil,
        wifiInterface: String = "en0",
        connectedVPNName: String? = nil
    ) -> SampleResult {
        let now = Date()
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return SampleResult(
                sample: ThroughputSample(timestamp: now, downloadBytesPerSec: 0, uploadBytesPerSec: 0),
                sessionDownBytes: 0,
                sessionUpBytes: 0,
                sessionPeakBytesPerSec: 0,
                localIP: nil,
                activeInterfaces: [],
                activeWiFiMAC: nil,
                hasGlobalIPv6: false,
                awdl: AWDLSnapshot()
            )
        }
        defer { freeifaddrs(first) }

        let target = preferredInterface ?? wifiInterface
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var matchedTarget = false
        var fallbackIn: UInt64 = 0
        var fallbackOut: UInt64 = 0
        var ipv4Map: [String: String] = [:]
        var activeEn0MAC: String?
        var hasGlobalIPv6 = false
        var awdlActive = false
        var awdlPackets: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let ifa = ptr.pointee
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback, let addr = ifa.ifa_addr {
                let family = Int32(addr.pointee.sa_family)
                if family == AF_LINK {
                    if name == "en0" {
                        activeEn0MAC = extractLinkMAC(addr)
                    }
                    if let dataPtr = ifa.ifa_data {
                        let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                        let ib = UInt64(data.ifi_ibytes)
                        let ob = UInt64(data.ifi_obytes)
                        if name == "awdl0" {
                            awdlActive = isRunning
                            awdlPackets = UInt64(data.ifi_ipackets) &+ UInt64(data.ifi_opackets)
                        }
                        if name == target {
                            bytesIn = ib
                            bytesOut = ob
                            matchedTarget = true
                        } else if name.hasPrefix("en") {
                            fallbackIn &+= ib
                            fallbackOut &+= ob
                        }
                    }
                } else if family == AF_INET {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let len = socklen_t(addr.pointee.sa_len)
                    if getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = host.withUnsafeBufferPointer { buf in
                            buf.baseAddress.map { String(cString: $0) } ?? ""
                        }
                        if !ip.isEmpty && !ip.hasPrefix("169.254.") {
                            ipv4Map[name] = ip
                        }
                    }
                } else if family == AF_INET6 && (name == target || name == "en0") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let len = socklen_t(addr.pointee.sa_len)
                    if getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip6 = host.withUnsafeBufferPointer { buf in
                            buf.baseAddress.map { String(cString: $0) } ?? ""
                        }.lowercased()
                        // Global unicast IPv6 starts with 2xxx or 3xxx (not link-local fe80:: or ULA fd/fc)
                        if ip6.hasPrefix("2") || ip6.hasPrefix("3") {
                            hasGlobalIPv6 = true
                        }
                    }
                }
            }
            cursor = ifa.ifa_next
        }

        let currentIn = matchedTarget ? bytesIn : fallbackIn
        let currentOut = matchedTarget ? bytesOut : fallbackOut
        let localIP = ipv4Map[target] ?? ipv4Map[wifiInterface] ?? ipv4Map.values.first
        let activeInterfaces = Self.buildActiveInterfaces(
            ipv4Map: ipv4Map,
            wifiInterface: wifiInterface,
            primaryInterface: target,
            connectedVPNName: connectedVPNName
        )

        return lock.withLock {
            // Compute live awdl0 packet rate
            var awdlPps = 0.0
            if let prevP = prevAwdlPackets, let prevD = prevAwdlDate {
                let dt = now.timeIntervalSince(prevD)
                if dt > 0.05 && awdlPackets >= prevP {
                    awdlPps = Double(awdlPackets - prevP) / dt
                }
            }
            prevAwdlPackets = awdlPackets
            prevAwdlDate = now
            let awdlSnap = AWDLSnapshot(isActive: awdlActive, totalPackets: awdlPackets, packetsPerSec: awdlPps)

            if lastInterface != target {
                previous = Totals(bytesIn: currentIn, bytesOut: currentOut, timestamp: now)
                lastInterface = target
                return SampleResult(
                    sample: ThroughputSample(timestamp: now, downloadBytesPerSec: 0, uploadBytesPerSec: 0),
                    sessionDownBytes: sessionDown,
                    sessionUpBytes: sessionUp,
                    sessionPeakBytesPerSec: sessionPeak,
                    localIP: localIP,
                    activeInterfaces: activeInterfaces,
                    activeWiFiMAC: activeEn0MAC,
                    hasGlobalIPv6: hasGlobalIPv6,
                    awdl: awdlSnap
                )
            }

            defer {
                previous = Totals(bytesIn: currentIn, bytesOut: currentOut, timestamp: now)
            }

            guard let prev = previous else {
                return SampleResult(
                    sample: ThroughputSample(timestamp: now, downloadBytesPerSec: 0, uploadBytesPerSec: 0),
                    sessionDownBytes: sessionDown,
                    sessionUpBytes: sessionUp,
                    sessionPeakBytesPerSec: sessionPeak,
                    localIP: localIP,
                    activeInterfaces: activeInterfaces,
                    activeWiFiMAC: activeEn0MAC,
                    hasGlobalIPv6: hasGlobalIPv6,
                    awdl: awdlSnap
                )
            }

            let dt = now.timeIntervalSince(prev.timestamp)
            // Ignore tiny intervals or long sleep gaps (> 12s) so wake-from-sleep never spikes the graph
            guard dt > 0.05 && dt <= 12.0 else {
                return SampleResult(
                    sample: ThroughputSample(timestamp: now, downloadBytesPerSec: 0, uploadBytesPerSec: 0),
                    sessionDownBytes: sessionDown,
                    sessionUpBytes: sessionUp,
                    sessionPeakBytesPerSec: sessionPeak,
                    localIP: localIP,
                    activeInterfaces: activeInterfaces,
                    activeWiFiMAC: activeEn0MAC,
                    hasGlobalIPv6: hasGlobalIPv6,
                    awdl: awdlSnap
                )
            }

            let dIn = Self.safe32BitCounterDelta(previous: prev.bytesIn, current: currentIn)
            let dOut = Self.safe32BitCounterDelta(previous: prev.bytesOut, current: currentOut)
            sessionDown &+= dIn
            sessionUp &+= dOut
            let downRate = Double(dIn) / dt
            let upRate = Double(dOut) / dt
            sessionPeak = max(sessionPeak, downRate + upRate)

            return SampleResult(
                sample: ThroughputSample(
                    timestamp: now,
                    downloadBytesPerSec: downRate,
                    uploadBytesPerSec: upRate
                ),
                sessionDownBytes: sessionDown,
                sessionUpBytes: sessionUp,
                sessionPeakBytesPerSec: sessionPeak,
                localIP: localIP,
                activeInterfaces: activeInterfaces,
                activeWiFiMAC: activeEn0MAC,
                hasGlobalIPv6: hasGlobalIPv6,
                awdl: awdlSnap
            )
        }
    }

    /// Handles 32-bit `if_data.ifi_ibytes` wrap-around (~4.29 GB) without negative underflow or spikes.
    public static func safe32BitCounterDelta(previous: UInt64, current: UInt64) -> UInt64 {
        if current >= previous {
            return current - previous
        }
        // Only treat as 32-bit rollover if previous was near UInt32.max
        let u32Max = UInt64(UInt32.max)
        if previous <= u32Max && (u32Max - previous) < 512_000_000 && current < 512_000_000 {
            return (u32Max - previous) + current + 1
        }
        return 0
    }

    private func extractLinkMAC(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdlPtr in
            let sdl = sdlPtr.pointee
            let sdlLen = Int(sdl.sdl_len)
            let nlen = Int(sdl.sdl_nlen)
            let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) ?? 8
            guard sdl.sdl_alen == 6, nlen >= 0, dataOffset + nlen + 6 <= sdlLen else { return nil }
            let base = UnsafeRawPointer(sdlPtr)
            var bytes: [String] = []
            bytes.reserveCapacity(6)
            for i in 0..<6 {
                let b = base.load(fromByteOffset: dataOffset + nlen + i, as: UInt8.self)
                bytes.append(String(format: "%02x", b))
            }
            return bytes.joined(separator: ":")
        }
    }
}
