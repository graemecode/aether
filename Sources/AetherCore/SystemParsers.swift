import Foundation

/// Pure, zero-IO parsers for macOS network telemetry outputs so every parser is
/// deterministically unit-tested against real macOS 15/26 fixtures.
public enum SystemParsers {

    // MARK: - MAC Address Privacy (IEEE 802 Locally Administered Bit)

    /// Returns true if the MAC address has the IEEE 802 locally-administered bit (0x02) set,
    /// which macOS sets whenever Private Wi-Fi Address (Fixed or Rotating) is active.
    public static func isLocallyAdministeredMAC(_ mac: String?) -> Bool? {
        guard let mac = mac?.trimmingCharacters(in: .whitespacesAndNewlines), !mac.isEmpty else {
            return nil
        }
        let parts = mac.split(separator: ":")
        guard parts.count == 6, let firstByte = UInt8(parts[0], radix: 16) else {
            return nil
        }
        return (firstByte & 0x02) != 0
    }

    /// Normalizes macOS `arp -an` short hex octets (e.g. `2a:cc:9c:44:b:a7` -> `2a:cc:9c:44:0b:a7`).
    public static func normalizeMAC(_ raw: String) -> String {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: ":")
        guard parts.count == 6 else { return raw.lowercased() }
        return parts.map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ":")
    }

    // MARK: - `route -n get default`

    public static func parseDefaultRoute(_ output: String) -> (interface: String?, gateway: String?) {
        var iface: String?
        var gateway: String?
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("gateway:") {
                let val = line.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { gateway = val }
            } else if line.hasPrefix("interface:") {
                let val = line.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { iface = val }
            }
        }
        return (iface, gateway)
    }

    // MARK: - `scutil --dns`

    public static func parseScutilDNS(_ output: String) -> DNSSnapshot {
        // Split into resolver blocks
        let lines = output.components(separatedBy: .newlines)
        var blocks: [[String]] = []
        var current: [String] = []
        var inResolvers = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("resolver #") {
                if !current.isEmpty { blocks.append(current) }
                current = [trimmed]
                inResolvers = true
            } else if trimmed.hasPrefix("DNS configuration (for scoped queries)") {
                break
            } else if inResolvers {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        var allServers: [String] = []
        var tunnelServers: [String] = []
        var tunnelIface: String?

        for block in blocks {
            var isMDNS = false
            var isDomainScoped = false
            var isTunnel = false
            var ifaceName: String?
            var blockServers: [String] = []

            for line in block {
                if line.hasPrefix("options") && line.contains("mdns") {
                    isMDNS = true
                }
                if line.hasPrefix("domain") {
                    isDomainScoped = true
                }
                if line.hasPrefix("if_index") {
                    if let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"), open < close {
                        let name = String(line[line.index(after: open)..<close])
                        ifaceName = name
                        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                            isTunnel = true
                        }
                    }
                }
                if line.hasPrefix("nameserver[") {
                    if let colon = line.firstIndex(of: ":") {
                        let ip = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                        if !ip.isEmpty { blockServers.append(ip) }
                    }
                }
            }

            if isMDNS { continue }
            if isTunnel && !blockServers.isEmpty {
                tunnelIface = tunnelIface ?? ifaceName
                for s in blockServers where !tunnelServers.contains(s) {
                    tunnelServers.append(s)
                }
            }
            if !isDomainScoped || isTunnel {
                for s in blockServers where !allServers.contains(s) {
                    allServers.append(s)
                }
            }
        }

        if allServers.isEmpty && !tunnelServers.isEmpty {
            allServers = tunnelServers
        }

        guard !allServers.isEmpty else {
            return DNSSnapshot(servers: [], providerLabel: "No DNS", posture: .unknown)
        }

        // Classify DNS posture
        if !tunnelServers.isEmpty {
            let label = classifyProvider(tunnelServers) ?? "VPN Tunnel (\(tunnelIface ?? "utun"))"
            return DNSSnapshot(
                servers: allServers,
                providerLabel: label,
                posture: .vpnTunnel,
                hasTunnelResolver: true,
                tunnelInterface: tunnelIface
            )
        }

        if let known = classifyProvider(allServers) {
            return DNSSnapshot(
                servers: allServers,
                providerLabel: known,
                posture: .trustedProvider,
                hasTunnelResolver: false,
                tunnelInterface: nil
            )
        }

        if allServers.allSatisfy({ isPrivateIPv4($0) }) {
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

    public static func classifyProvider(_ servers: [String]) -> String? {
        for ip in servers {
            if ip == "1.1.1.1" || ip == "1.0.0.1" || ip.hasPrefix("2606:4700:") { return "Cloudflare" }
            if ip == "9.9.9.9" || ip == "149.112.112.112" || ip.hasPrefix("2620:fe::") { return "Quad9" }
            if ip == "45.90.28.0" || ip == "45.90.30.0" || ip.hasPrefix("2a07:a8c0:") { return "NextDNS" }
            if ip == "194.242.2.2" || ip == "194.242.2.3" { return "Mullvad DNS" }
            if ip == "94.140.14.14" || ip == "94.140.15.15" { return "AdGuard DNS" }
            if ip == "76.76.2.0" || ip == "76.76.10.0" { return "Control D" }
            if ip == "8.8.8.8" || ip == "8.8.4.4" || ip.hasPrefix("2001:4860:4860:") { return "Google DNS" }
            if ip == "100.100.100.100" { return "Tailscale MagicDNS" }
            if isCGNAT(ip) { return "VPN Tunnel DNS" }
        }
        return nil
    }

    public static func isPrivateIPv4(_ ip: String) -> Bool {
        if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count == 4, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    public static func isCGNAT(_ ip: String) -> Bool {
        guard ip.hasPrefix("100.") else { return false }
        let parts = ip.split(separator: ".")
        guard parts.count == 4, let second = Int(parts[1]) else { return false }
        return (64...127).contains(second)
    }

    // MARK: - `scutil --nc list`

    public static func parseScutilNC(_ output: String) -> [VPNService] {
        // Example:
        // * (Connected)      B9812112-0C88-407C-BECD-EC3970288823 VPN (com.twingate.macos) "Twingate" [VPN:com.twingate.macos]
        var services: [VPNService] = []
        let pattern = #"\(([^)]+)\)\s+([0-9A-Fa-f-]{36})\s+\S+(?:\s+\(([^)]+)\))?\s+"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in output.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            let status = nsLine.substring(with: match.range(at: 1))
            let uuid = nsLine.substring(with: match.range(at: 2))
            let bundle = match.range(at: 3).location != NSNotFound ? nsLine.substring(with: match.range(at: 3)) : nil
            let name = nsLine.substring(with: match.range(at: 4))
            services.append(VPNService(uuid: uuid, name: name, bundleID: bundle, status: status))
        }
        return services
    }

    // MARK: - `scutil --proxy`

    public static func parseScutilProxy(_ output: String) -> ProxySnapshot {
        func flag(_ key: String) -> Bool {
            for line in output.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("\(key) :") || t.hasPrefix("\(key):") {
                    return t.hasSuffix(": 1") || t.hasSuffix(":1")
                }
            }
            return false
        }

        let http = flag("HTTPEnable")
        let https = flag("HTTPSEnable")
        let socks = flag("SOCKSEnable")
        let pac = flag("ProxyAutoConfigEnable")

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

    // MARK: - `arp -an`

    public static func parseArpDevices(
        _ output: String,
        interfaceName: String?,
        gatewayIP: String?,
        localIP: String? = nil,
        localMAC: String? = nil
    ) -> (gatewayMAC: String?, devices: [LANDevice]) {
        var gatewayMAC: String?
        var byIP: [String: LANDevice] = [:]
        let pattern = #"\(([^)]+)\)\s+at\s+([0-9a-fA-F:]+)\s+on\s+(\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (nil, []) }

        for line in output.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            let ip = nsLine.substring(with: match.range(at: 1))
            let rawMAC = nsLine.substring(with: match.range(at: 2))
            let iface = nsLine.substring(with: match.range(at: 3))

            if let target = interfaceName, iface != target { continue }
            let mac = normalizeMAC(rawMAC)
            if mac == "ff:ff:ff:ff:ff:ff" { continue }
            if ip.hasPrefix("224.") || ip.hasPrefix("239.") || ip.hasSuffix(".255") { continue }

            let isGW = (ip == gatewayIP)
            if isGW { gatewayMAC = mac }

            byIP[ip] = LANDevice(
                ip: ip,
                mac: mac,
                vendor: OUIVendorLookup.vendor(for: mac),
                hostname: nil,
                isGateway: isGW,
                isLocalMac: (ip == localIP),
                isPrivateMAC: isLocallyAdministeredMAC(mac) ?? false
            )
        }

        // Include this Mac at top if localIP is known and not already in ARP cache
        if let localIP, !localIP.isEmpty, byIP[localIP] == nil {
            let mac = localMAC.map(normalizeMAC) ?? "—"
            byIP[localIP] = LANDevice(
                ip: localIP,
                mac: mac,
                vendor: "Apple",
                hostname: Host.current().localizedName,
                isGateway: false,
                isLocalMac: true,
                isPrivateMAC: isLocallyAdministeredMAC(mac) ?? false
            )
        }

        let sorted = byIP.values.sorted { a, b in
            if a.isGateway != b.isGateway { return a.isGateway }
            if a.isLocalMac != b.isLocalMac { return a.isLocalMac }
            return a.ip.localizedStandardCompare(b.ip) == .orderedAscending
        }
        return (gatewayMAC, sorted)
    }

    public static func parseArpTable(
        _ output: String,
        interfaceName: String?,
        gatewayIP: String?
    ) -> (gatewayMAC: String?, neighborCount: Int) {
        let parsed = parseArpDevices(output, interfaceName: interfaceName, gatewayIP: gatewayIP)
        return (parsed.gatewayMAC, parsed.devices.count)
    }

    // MARK: - `lsof -nP -iTCP -sTCP:LISTEN`

    private static let macSystemDaemons: Set<String> = [
        "rapportd", "controlce", "controlcenter", "sharingd",
        "airplayxpchelper", "mdnsresponder", "identityservicesd", "apsd"
    ]

    public static func parseListeningPorts(_ output: String) -> (userPorts: [ExposedPort], systemPorts: [ExposedPort]) {
        var seen: Set<String> = []
        var userPorts: [ExposedPort] = []
        var systemPorts: [ExposedPort] = []

        for line in output.components(separatedBy: .newlines).dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let cols = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard cols.count >= 9 else { continue }

            let command = String(cols[0])
            guard let pid = Int(cols[1]) else { continue }

            // Find the token with host:port (usually second-to-last before `(LISTEN)`)
            guard let nameToken = cols.last(where: { $0.contains(":") && !$0.hasPrefix("(") }) else { continue }
            let endpoint = String(nameToken)

            // Only flag wildcard / LAN-reachable bindings (`*:PORT`, `0.0.0.0:PORT`, `[::]:PORT`)
            let isExposed: Bool
            if endpoint.hasPrefix("*:") || endpoint.hasPrefix("0.0.0.0:") || endpoint.hasPrefix("[::]:") {
                isExposed = true
            } else if endpoint.hasPrefix("127.") || endpoint.hasPrefix("[::1]:") || endpoint.hasPrefix("localhost:") {
                isExposed = false
            } else {
                // Bound to a specific non-loopback IP (e.g. 192.168.x.x:3000) -> LAN-exposed
                isExposed = true
            }

            guard isExposed, let colonIdx = endpoint.lastIndex(of: ":"),
                  let port = Int(endpoint[endpoint.index(after: colonIdx)...]) else {
                continue
            }

            let key = "\(pid):\(port)"
            guard seen.insert(key).inserted else { continue }

            let isSys = macSystemDaemons.contains(command.lowercased())
            let entry = ExposedPort(process: command, pid: pid, port: port, isSystemDaemon: isSys)
            if isSys {
                systemPorts.append(entry)
            } else {
                userPorts.append(entry)
            }
        }

        userPorts.sort { $0.port < $1.port }
        systemPorts.sort { $0.port < $1.port }
        return (userPorts, systemPorts)
    }

    // MARK: - `nettop -P -L 1 -J bytes_in,bytes_out -x`

    public struct NettopRow: Sendable, Equatable {
        public let name: String
        public let pid: Int
        public let bytesIn: UInt64
        public let bytesOut: UInt64

        public init(name: String, pid: Int, bytesIn: UInt64, bytesOut: UInt64) {
            self.name = name
            self.pid = pid
            self.bytesIn = bytesIn
            self.bytesOut = bytesOut
        }
    }

    public static func parseNettopSnapshot(_ output: String) -> [String: NettopRow] {
        var result: [String: NettopRow] = [:]
        for line in output.components(separatedBy: .newlines).dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let procField = String(cols[0]).trimmingCharacters(in: .whitespaces)
            guard !procField.isEmpty, let dotIdx = procField.lastIndex(of: ".") else { continue }
            let name = String(procField[..<dotIdx])
            let pidStr = String(procField[procField.index(after: dotIdx)...])
            guard let pid = Int(pidStr),
                  let bin = UInt64(cols[1].trimmingCharacters(in: .whitespaces)),
                  let bout = UInt64(cols[2].trimmingCharacters(in: .whitespaces)) else {
                continue
            }
            result[procField] = NettopRow(name: name, pid: pid, bytesIn: bin, bytesOut: bout)
        }
        return result
    }

    public static func diffNettop(
        previous: [String: NettopRow],
        current: [String: NettopRow],
        elapsedSeconds: Double,
        limit: Int = 5
    ) -> [ProcessBandwidth] {
        guard elapsedSeconds > 0.05 else { return [] }
        var rates: [ProcessBandwidth] = []
        for (key, cur) in current {
            guard let prev = previous[key] else { continue }
            let dIn = cur.bytesIn >= prev.bytesIn ? Double(cur.bytesIn - prev.bytesIn) / elapsedSeconds : 0
            let dOut = cur.bytesOut >= prev.bytesOut ? Double(cur.bytesOut - prev.bytesOut) / elapsedSeconds : 0
            if dIn + dOut >= 256 { // ignore < 256 B/s noise
                rates.append(ProcessBandwidth(name: cur.name, pid: cur.pid, downloadBytesPerSec: dIn, uploadBytesPerSec: dOut))
            }
        }
        rates.sort { $0.totalBytesPerSec > $1.totalBytesPerSec }
        return Array(rates.prefix(limit))
    }

    // MARK: - `networkQuality -c`

    public static func parseNetworkQualityJSON(_ data: Data) -> NetworkQualityResult? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let dlBps = obj["dl_throughput"] as? Double,
              let ulBps = obj["ul_throughput"] as? Double,
              let rpm = obj["responsiveness"] as? Double else {
            return nil
        }
        let baseRtt = (obj["base_rtt"] as? Double) ?? 0
        let endpoint = obj["test_endpoint"] as? String

        // Median loaded H2 RTT gives a clear human number for bufferbloat
        let loadedSamples = (obj["lud_self_h2_req_resp"] as? [Double])
            ?? (obj["lud_foreign_h2_req_resp"] as? [Double])
            ?? []
        let loadedMedian: Double? = {
            guard !loadedSamples.isEmpty else { return nil }
            let sorted = loadedSamples.sorted()
            return sorted[sorted.count / 2]
        }()

        return NetworkQualityResult(
            downloadMbps: dlBps / 1_000_000.0,
            uploadMbps: ulBps / 1_000_000.0,
            responsivenessRPM: Int(round(rpm)),
            baseRttMs: baseRtt,
            loadedRttMs: loadedMedian,
            endpoint: endpoint
        )
    }

    // MARK: - `lsof -nP -iTCP -sTCP:ESTABLISHED` (Live Outbound Connection X-Ray)

    public static func parseEstablishedConnections(_ output: String) -> ConnectionXRay {
        var totalOutbound = 0
        var remoteHosts: Set<String> = []
        var plaintextHTTP = 0
        var continuityLinks = 0
        var perAppCount: [String: Int] = [:]
        var perAppPlaintext: Set<String> = []

        for line in output.components(separatedBy: .newlines).dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let cols = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard cols.count >= 9 else { continue }

            let rawCmd = String(cols[0]).replacingOccurrences(of: "\\x20", with: " ")
            guard let flowToken = cols.first(where: { $0.contains("->") }) else { continue }
            let parts = flowToken.components(separatedBy: "->")
            guard parts.count == 2 else { continue }
            let remote = parts[1]

            // Skip pure loopback
            if remote.hasPrefix("127.") || remote.hasPrefix("[::1]:") { continue }

            // Link-local IPv6 (`fe80:...`) -> Apple Continuity / AWDL / AirDrop peer links
            if remote.hasPrefix("[fe80:") {
                continuityLinks += 1
                continue
            }

            totalOutbound += 1
            if let colonIdx = remote.lastIndex(of: ":") {
                let host = String(remote[..<colonIdx])
                let portStr = String(remote[remote.index(after: colonIdx)...])
                remoteHosts.insert(host)
                if portStr == "80" {
                    plaintextHTTP += 1
                    perAppPlaintext.insert(rawCmd)
                }
            }
            perAppCount[rawCmd, default: 0] += 1
        }

        let top = perAppCount
            .map { OutboundAppSummary(name: $0.key, connectionCount: $0.value, hasPlaintextHTTP: perAppPlaintext.contains($0.key)) }
            .sorted { a, b in
                if a.hasPlaintextHTTP != b.hasPlaintextHTTP { return a.hasPlaintextHTTP }
                return a.connectionCount > b.connectionCount
            }

        return ConnectionXRay(
            totalOutboundSockets: totalOutbound,
            uniqueRemoteHosts: remoteHosts.count,
            plaintextHTTPCount: plaintextHTTP,
            continuityPeerLinks: continuityLinks,
            topApps: Array(top.prefix(6))
        )
    }
}
