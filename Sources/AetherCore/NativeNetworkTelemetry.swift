import Darwin
import Foundation
import SystemConfiguration

/// 100% Native Darwin + SystemConfiguration telemetry engine.
/// Zero subprocesses, sub-millisecond latency, and Mac App Store App Sandbox compatible.
public enum NativeNetworkTelemetry {

    /// True when running inside the Mac App Store App Sandbox.
    public static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Resolves the physical L2 interface for ARP / LAN peer inspection.
    /// Full-tunnel VPNs set `PrimaryInterface` to `utun*`/`ipsec*`/`ppp*`, which are L3 tunnels
    /// with zero ARP entries; always fall back to the active Wi-Fi interface so Evil-Twin and
    /// LAN neighbor detection keep working while a VPN is active.
    public static func physicalInterfaceForARP(
        defaultInterface: String?,
        wifiInterface: String,
        wifiConnected: Bool
    ) -> String? {
        if wifiConnected {
            return wifiInterface
        }
        if let def = defaultInterface {
            let isTunnel = def.hasPrefix("utun") || def.hasPrefix("ipsec") || def.hasPrefix("ppp")
            return isTunnel ? wifiInterface : def
        }
        return wifiInterface
    }

    /// Reads the macOS Network Service display name (e.g. "Wi-Fi" or user-renamed "Home Wi-Fi")
    /// bound to a BSD interface like `en0`, directly via SystemConfiguration (0 subprocesses).
    public static func readNetworkServiceName(forBSDInterface bsdName: String = "en0") -> String? {
        guard let prefs = SCPreferencesCreate(nil, "com.strangechances.Aether" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else {
            return nil
        }
        for svc in services {
            guard SCNetworkServiceGetEnabled(svc),
                  let iface = SCNetworkServiceGetInterface(svc),
                  let dev = SCNetworkInterfaceGetBSDName(iface) as String?,
                  dev == bsdName,
                  let name = SCNetworkServiceGetName(svc) as String?,
                  !name.isEmpty else {
                continue
            }
            return name
        }
        return nil
    }

    // MARK: - Native Kernel ARP Table (`sysctl` PF_ROUTE / RTF_LLINFO — 0 Subprocesses!)

    public static func readArpDevices(
        interfaceName: String?,
        gatewayIP: String?,
        localIP: String? = nil,
        localMAC: String? = nil
    ) -> (gatewayMAC: String?, devices: [LANDevice]) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var needed: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &needed, nil, 0) == 0, needed > 0 else {
            return (nil, [])
        }
        // Add headroom & retry once on ENOMEM so concurrent ARP cache growth never empties the LAN list
        var buf = [UInt8]()
        var actualSize = 0
        for attempt in 0..<2 {
            let allocSize = needed + max(4096, needed / 4) * (attempt + 1)
            buf = [UInt8](repeating: 0, count: allocSize)
            actualSize = allocSize
            if sysctl(&mib, UInt32(mib.count), &buf, &actualSize, nil, 0) == 0 {
                break
            }
            if errno != ENOMEM || attempt == 1 {
                return (nil, [])
            }
            if sysctl(&mib, UInt32(mib.count), nil, &needed, nil, 0) != 0 || needed <= 0 {
                return (nil, [])
            }
        }
        let byteCount = min(actualSize, buf.count)

        func roundup(_ len: Int) -> Int {
            let sz = MemoryLayout<UInt32>.size
            return len > 0 ? ((len + sz - 1) & ~(sz - 1)) : sz
        }

        var gatewayMAC: String?
        var byIP: [String: LANDevice] = [:]

        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<rt_msghdr>.size <= byteCount {
                let rtm = base.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let msgLen = Int(rtm.rtm_msglen)
                guard msgLen >= MemoryLayout<rt_msghdr>.size, offset + msgLen <= byteCount else { break }

                var saOffset = offset + MemoryLayout<rt_msghdr>.size
                if saOffset + MemoryLayout<sockaddr_in>.size <= offset + msgLen {
                    let sin = base.loadUnaligned(fromByteOffset: saOffset, as: sockaddr_in.self)
                    var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var addr = sin.sin_addr
                    inet_ntop(AF_INET, &addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                    let ip = ipBuf.withUnsafeBufferPointer { b in b.baseAddress.map { String(cString: $0) } ?? "" }

                    saOffset += roundup(Int(sin.sin_len))
                    if saOffset + MemoryLayout<sockaddr_dl>.size <= offset + msgLen {
                        let sdl = base.loadUnaligned(fromByteOffset: saOffset, as: sockaddr_dl.self)
                        if Int32(sdl.sdl_family) == AF_LINK && sdl.sdl_alen == 6 {
                            let nlen = Int(sdl.sdl_nlen)
                            let sdlLen = Int(sdl.sdl_len)
                            let dataOff = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) ?? 8
                            if nlen >= 0 && dataOff + nlen + 6 <= sdlLen && saOffset + dataOff + nlen + 6 <= offset + msgLen {
                                var macBytes: [String] = []
                                macBytes.reserveCapacity(6)
                                for i in 0..<6 {
                                    let b = base.load(fromByteOffset: saOffset + dataOff + nlen + i, as: UInt8.self)
                                    macBytes.append(String(format: "%02x", b))
                                }
                                let mac = macBytes.joined(separator: ":")

                                var ifNameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                                let iface = if_indextoname(UInt32(sdl.sdl_index), &ifNameBuf).map { String(cString: $0) } ?? ""

                                let matchesIface = (interfaceName == nil) || (iface == interfaceName)
                                let isBroadcast = (mac == "ff:ff:ff:ff:ff:ff") || ip.hasPrefix("224.") || ip.hasPrefix("239.") || ip.hasSuffix(".255")

                                if matchesIface && !isBroadcast && !ip.isEmpty {
                                    let isGW = (ip == gatewayIP)
                                    if isGW { gatewayMAC = mac }
                                    byIP[ip] = LANDevice(
                                        ip: ip,
                                        mac: mac,
                                        vendor: OUIVendorLookup.vendor(for: mac),
                                        hostname: nil,
                                        isGateway: isGW,
                                        isLocalMac: (ip == localIP),
                                        isPrivateMAC: SystemParsers.isLocallyAdministeredMAC(mac) ?? false
                                    )
                                }
                            }
                        }
                    }
                }
                offset += msgLen
            }
        }

        if let localIP, !localIP.isEmpty, byIP[localIP] == nil {
            let mac = localMAC.map(SystemParsers.normalizeMAC) ?? "—"
            byIP[localIP] = LANDevice(
                ip: localIP,
                mac: mac,
                vendor: "Apple",
                hostname: Host.current().localizedName,
                isGateway: false,
                isLocalMac: true,
                isPrivateMAC: SystemParsers.isLocallyAdministeredMAC(mac) ?? false
            )
        }

        let sorted = byIP.values.sorted { a, b in
            if a.isGateway != b.isGateway { return a.isGateway }
            if a.isLocalMac != b.isLocalMac { return a.isLocalMac }
            return a.ip.localizedStandardCompare(b.ip) == .orderedAscending
        }
        return (gatewayMAC, sorted)
    }

    // MARK: - Pure-Swift Sandbox-Safe Speed & Responsiveness Test (`URLSession`)

    /// Sandbox-compatible throughput & loaded-RTT responsiveness test (used inside Mac App Store Sandbox
    /// where `/usr/bin/networkQuality` subprocesses are unavailable).
    public static func runNativeQualityTest() async -> NetworkQualityResult? {
        guard let probeURL = URL(string: "https://speed.cloudflare.com/__down?bytes=0"),
              let dlURL = URL(string: "https://speed.cloudflare.com/__down?bytes=8000000"),
              let ulURL = URL(string: "https://speed.cloudflare.com/__up") else {
            return nil
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6.0
        cfg.timeoutIntervalForResource = 10.0
        cfg.urlCache = nil
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        // 1. Measure Idle RTT (3 quick probes)
        var idleRtts: [Double] = []
        for _ in 0..<3 {
            let t0 = CFAbsoluteTimeGetCurrent()
            if let _ = try? await session.data(from: probeURL) {
                idleRtts.append((CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
            }
        }
        guard !idleRtts.isEmpty else { return nil }
        let baseRtt = idleRtts.sorted()[idleRtts.count / 2]

        // 2. Download throughput + concurrent loaded RTT probes
        let dlStart = CFAbsoluteTimeGetCurrent()
        let (dlBytes, loadedRtts) = await withTaskGroup(of: (Int, Double?).self) { group -> (Int, [Double]) in
            for _ in 0..<3 {
                group.addTask {
                    guard let (data, _) = try? await session.data(from: dlURL) else { return (0, nil) }
                    return (data.count, nil)
                }
            }
            for delayMs in [150, 450, 850] {
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(delayMs))
                    let t0 = CFAbsoluteTimeGetCurrent()
                    guard let _ = try? await session.data(from: probeURL) else { return (0, nil) }
                    return (0, (CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
                }
            }
            var total = 0
            var rtts: [Double] = []
            for await (bytes, rtt) in group {
                total += bytes
                if let rtt { rtts.append(rtt) }
            }
            return (total, rtts)
        }
        let dlElapsed = max(0.1, CFAbsoluteTimeGetCurrent() - dlStart)
        let dlMbps = (Double(dlBytes) * 8.0) / (dlElapsed * 1_000_000.0)

        // 3. Upload throughput (2 MB payload)
        let payload = Data(repeating: 0x5A, count: 2_000_000)
        var ulReq = URLRequest(url: ulURL)
        ulReq.httpMethod = "POST"
        let ulStart = CFAbsoluteTimeGetCurrent()
        let ulOk = (try? await session.upload(for: ulReq, from: payload)) != nil
        let ulElapsed = max(0.1, CFAbsoluteTimeGetCurrent() - ulStart)
        let ulMbps = ulOk ? (Double(payload.count) * 8.0) / (ulElapsed * 1_000_000.0) : 0

        let loadedMedian: Double? = loadedRtts.isEmpty ? nil : loadedRtts.sorted()[loadedRtts.count / 2]
        let effectiveRtt = max(10.0, loadedMedian ?? baseRtt)
        let rpm = Int(round(60_000.0 / effectiveRtt))

        return NetworkQualityResult(
            downloadMbps: dlMbps,
            uploadMbps: ulMbps,
            responsivenessRPM: rpm,
            baseRttMs: baseRtt,
            loadedRttMs: loadedMedian,
            endpoint: "speed.cloudflare.com"
        )
    }

    // MARK: - Default Route (`State:/Network/Global/IPv4` with IPv6-only NAT64 fallback)

    public static func readDefaultRoute(localIP: String?) -> RouteInfo {
        guard let store = SCDynamicStoreCreate(nil, "com.strangechances.Aether" as CFString, nil, nil) else {
            return RouteInfo(localIP: localIP)
        }
        if let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            let iface = dict["PrimaryInterface"] as? String
            let router = dict["Router"] as? String
            if iface != nil || router != nil {
                return RouteInfo(defaultInterface: iface, gatewayIP: router, localIP: localIP, gatewayMAC: nil)
            }
        }
        // Apple Guideline 2.5.5: Support IPv6-only NAT64 networks when IPv4 global state is absent
        if let dict6 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any] {
            let iface = dict6["PrimaryInterface"] as? String
            let router = dict6["Router"] as? String
            return RouteInfo(defaultInterface: iface, gatewayIP: router, localIP: localIP, gatewayMAC: nil)
        }
        return RouteInfo(localIP: localIP)
    }

    // MARK: - DNS Configuration (`State:/Network/Global/DNS` + Service DNS)

    public static func readDNS() -> DNSSnapshot {
        guard let store = SCDynamicStoreCreate(nil, "com.strangechances.Aether" as CFString, nil, nil) else {
            return DNSSnapshot()
        }

        var allServers: [String] = []
        var tunnelServers: [String] = []
        var tunnelIface: String?

        // Check scoped service DNS entries to detect active VPN tunnel resolvers (utun/ipsec/ppp)
        if let serviceKeys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/DNS" as CFString) as? [String] {
            for key in serviceKeys {
                guard let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                      let servers = dict["ServerAddresses"] as? [String], !servers.isEmpty else {
                    continue
                }
                let iface = dict["InterfaceName"] as? String
                let isTunnel = iface.map { $0.hasPrefix("utun") || $0.hasPrefix("ipsec") || $0.hasPrefix("ppp") } ?? false
                if isTunnel {
                    tunnelIface = tunnelIface ?? iface
                    for s in servers where !tunnelServers.contains(s) { tunnelServers.append(s) }
                }
                for s in servers where !allServers.contains(s) { allServers.append(s) }
            }
        }

        // Also inspect Global DNS (takes precedence if set)
        if let globalDict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let servers = globalDict["ServerAddresses"] as? [String] {
            for s in servers where !allServers.contains(s) {
                allServers.insert(s, at: 0)
            }
        }

        return classifyDNS(allServers: allServers, tunnelServers: tunnelServers, tunnelIface: tunnelIface)
    }

    public static func classifyDNS(allServers: [String], tunnelServers: [String], tunnelIface: String?) -> DNSSnapshot {
        guard !allServers.isEmpty else {
            return DNSSnapshot(servers: [], providerLabel: "No DNS", posture: .unknown)
        }
        if !tunnelServers.isEmpty {
            let label = SystemParsers.classifyProvider(tunnelServers) ?? "VPN Tunnel (\(tunnelIface ?? "utun"))"
            return DNSSnapshot(
                servers: allServers,
                providerLabel: label,
                posture: .vpnTunnel,
                hasTunnelResolver: true,
                tunnelInterface: tunnelIface
            )
        }
        if let known = SystemParsers.classifyProvider(allServers) {
            return DNSSnapshot(
                servers: allServers,
                providerLabel: known,
                posture: .trustedProvider,
                hasTunnelResolver: false,
                tunnelInterface: nil
            )
        }
        if allServers.allSatisfy({ SystemParsers.isPrivateIPv4($0) }) {
            return DNSSnapshot(
                servers: allServers,
                providerLabel: "Router / ISP (\(allServers.first ?? ""))",
                posture: .localRouter,
                hasTunnelResolver: false,
                tunnelInterface: nil
            )
        }
        return DNSSnapshot(
            servers: allServers,
            providerLabel: "Custom (\(allServers.first ?? ""))",
            posture: .custom,
            hasTunnelResolver: false,
            tunnelInterface: nil
        )
    }

    // MARK: - System Proxies (`State:/Network/Global/Proxies`)

    public static func readProxy() -> ProxySnapshot {
        guard let store = SCDynamicStoreCreate(nil, "com.strangechances.Aether" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/Proxies" as CFString) as? [String: Any] else {
            return ProxySnapshot()
        }
        return parseProxyDictionary(dict)
    }

    public static func parseProxyDictionary(_ dict: [String: Any]) -> ProxySnapshot {
        let http = (dict["HTTPEnable"] as? Int) == 1
        let https = (dict["HTTPSEnable"] as? Int) == 1
        let socks = (dict["SOCKSEnable"] as? Int) == 1
        let pac = (dict["ProxyAutoConfigEnable"] as? Int) == 1

        var active: [String] = []
        if http { active.append("HTTP") }
        if https { active.append("HTTPS") }
        if socks { active.append("SOCKS") }
        if pac { active.append("PAC") }

        return ProxySnapshot(
            httpEnabled: http,
            httpsEnabled: https,
            socksEnabled: socks,
            pacEnabled: pac,
            summary: active.isEmpty ? "Direct" : active.joined(separator: " · ") + " Proxy"
        )
    }

    // MARK: - VPN Services (`SCPreferences` + `SCNetworkConnection`)

    public static func readVPNServices() -> [VPNService] {
        guard let prefs = SCPreferencesCreate(nil, "com.strangechances.Aether" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else {
            return []
        }

        var result: [VPNService] = []
        for svc in services {
            guard SCNetworkServiceGetEnabled(svc),
                  let iface = SCNetworkServiceGetInterface(svc),
                  let type = SCNetworkInterfaceGetInterfaceType(iface) as String?,
                  (type.contains("VPN") || type.contains("PPP") || type.contains("IPSec")),
                  let sid = SCNetworkServiceGetServiceID(svc) as String? else {
                continue
            }
            let name = (SCNetworkServiceGetName(svc) as String?) ?? "VPN"
            let conn = SCNetworkConnectionCreateWithServiceID(nil, sid as CFString, nil, nil)
            let statusStr: String = {
                guard let conn else { return "Disconnected" }
                switch SCNetworkConnectionGetStatus(conn) {
                case .connected:     return "Connected"
                case .connecting:    return "Connecting"
                case .disconnecting: return "Disconnecting"
                default:             return "Disconnected"
                }
            }()
            result.append(VPNService(uuid: sid, name: name, bundleID: type, status: statusStr))
        }
        return result
    }

    #if !APP_STORE
    public static func setVPNConnected(_ service: VPNService, connect: Bool) -> Bool {
        guard let conn = SCNetworkConnectionCreateWithServiceID(nil, service.uuid as CFString, nil, nil) else {
            return false
        }
        return connect
            ? SCNetworkConnectionStart(conn, nil, true)
            : SCNetworkConnectionStop(conn, true)
    }
    #endif

    // MARK: - Local mDNS Broadcast Name

    public static func readLocalHostName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "com.strangechances.Aether" as CFString, nil, nil),
              let name = SCDynamicStoreCopyLocalHostName(store) as String?,
              !name.isEmpty else {
            return nil
        }
        return "\(name).local"
    }

    // MARK: - Unprivileged Native ICMP Ping (`SOCK_DGRAM` + `IPPROTO_ICMP`, 0 Subprocesses!)

    public static func internetChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var idx = 0
        while idx + 1 < bytes.count {
            sum += (UInt32(bytes[idx]) << 8) | UInt32(bytes[idx + 1])
            idx += 2
        }
        if idx < bytes.count {
            sum += UInt32(bytes[idx]) << 8
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }

    /// Validates that a received `SOCK_DGRAM` `IPPROTO_ICMP` datagram contains an actual
    /// ICMP Echo Reply (Type 0, Code 0) matching the expected sequence number, rejecting
    /// ICMP Destination Unreachable (Type 3) or Time Exceeded (Type 11) error packets.
    public static func isValidICMPEchoReply(_ bytes: [UInt8], count: Int, expectedSequence: UInt16 = 1) -> Bool {
        guard count >= 28, bytes.count >= count else { return false }
        let version = bytes[0] >> 4
        let ihl = Int(bytes[0] & 0x0F) * 4
        guard version == 4, ihl >= 20, count >= ihl + 8 else { return false }
        let icmpType = bytes[ihl]
        let icmpCode = bytes[ihl + 1]
        let seq = (UInt16(bytes[ihl + 6]) << 8) | UInt16(bytes[ihl + 7])
        return icmpType == 0 && icmpCode == 0 && seq == expectedSequence
    }

    /// Resolves a hostname (e.g. `"one.one.one.one"`) to an IPv4 address string via `getaddrinfo`.
    /// Avoids hardcoded IPv4 literals (Apple Guideline 2.5.5 IPv6-only NAT64 compliance).
    public static func resolveIPv4Address(hostname: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(first) }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return host.withUnsafeBufferPointer { buf in
            buf.baseAddress.map { String(cString: $0) }
        }
    }

    public static func icmpPingMs(ipv4Host: String, timeoutMs: Int = 800) -> Double? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ipv4Host, &addr.sin_addr) == 1 else { return nil }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var tv = timeval(tv_sec: timeoutMs / 1000, tv_usec: __darwin_suseconds_t((timeoutMs % 1000) * 1000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let ident = UInt16.random(in: 1...65000)
        let seq: UInt16 = 1
        var pkt: [UInt8] = [
            8, 0,                           // Echo Request (Type 8, Code 0)
            0, 0,                           // Checksum placeholder
            UInt8(ident >> 8), UInt8(ident & 0xFF),
            UInt8(seq >> 8), UInt8(seq & 0xFF)
        ]
        let cksum = internetChecksum(pkt)
        pkt[2] = UInt8(cksum >> 8)
        pkt[3] = UInt8(cksum & 0xFF)

        let start = CFAbsoluteTimeGetCurrent()
        let sent = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(fd, pkt, pkt.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == pkt.count else { return nil }

        var buf = [UInt8](repeating: 0, count: 128)
        let received = recv(fd, &buf, buf.count, 0)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        guard received > 0, isValidICMPEchoReply(buf, count: received, expectedSequence: seq) else { return nil }
        return elapsedMs
    }
}
