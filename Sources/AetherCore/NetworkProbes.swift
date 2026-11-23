import Darwin
import Foundation
import Network

/// Async, timeout-bounded network probes for routing, DNS, VPNs, ARP, listening ports,
/// 3-hop latency, per-process bandwidth (`nettop`), and `networkQuality` responsiveness.
public enum NetworkProbes {

    // MARK: - Subprocess Helper (Direct Build Only — Mac App Store Binary Uses 100% Native Frameworks)

    #if !APP_STORE
    public static func runCommand(
        _ executable: String,
        arguments: [String],
        timeoutSeconds: Double = 3.0
    ) async -> (stdout: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments = arguments

                let outPipe = Pipe()
                proc.standardOutput = outPipe
                // Route stderr to /dev/null so a verbose child can never fill the 64KB stderr pipe and deadlock
                proc.standardError = FileHandle.nullDevice
                proc.standardInput = FileHandle.nullDevice

                final class ProcFlag: @unchecked Sendable {
                    private let lock = NSLock()
                    private var finished = false
                    private var killWorkItem: DispatchWorkItem?
                    func markFinished() {
                        lock.withLock {
                            finished = true
                            killWorkItem?.cancel()
                            killWorkItem = nil
                        }
                    }
                    func terminateIfRunning(_ proc: Process) {
                        lock.withLock {
                            guard !finished && proc.isRunning else { return }
                            proc.terminate()
                            let pid = proc.processIdentifier
                            let work = DispatchWorkItem { [weak self] in
                                guard let self else { return }
                                self.lock.withLock {
                                    if !self.finished && proc.isRunning && pid > 0 {
                                        kill(pid, SIGKILL)
                                    }
                                }
                            }
                            killWorkItem = work
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
                        }
                    }
                }
                let flag = ProcFlag()

                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timer.schedule(deadline: .now() + timeoutSeconds)
                timer.setEventHandler {
                    flag.terminateIfRunning(proc)
                }
                timer.resume()

                do {
                    try proc.run()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    timer.cancel()
                    flag.markFinished()
                    try? outPipe.fileHandleForReading.close()
                    let str = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (str, proc.terminationStatus))
                } catch {
                    timer.cancel()
                    flag.markFinished()
                    try? outPipe.fileHandleForReading.close()
                    continuation.resume(returning: ("", -1))
                }
            }
        }
    }
    #endif

    // MARK: - System Telemetry Snapshots (Native SystemConfiguration — 0 Subprocesses!)

    public static func fetchRouteInfo(localIP: String?) async -> RouteInfo {
        let native = NativeNetworkTelemetry.readDefaultRoute(localIP: localIP)
        #if APP_STORE
        return native
        #else
        if native.defaultInterface != nil || native.gatewayIP != nil {
            return native
        }
        let (out, _) = await runCommand("/sbin/route", arguments: ["-n", "get", "default"], timeoutSeconds: 2.0)
        let parsed = SystemParsers.parseDefaultRoute(out)
        return RouteInfo(
            defaultInterface: parsed.interface,
            gatewayIP: parsed.gateway,
            localIP: localIP,
            gatewayMAC: nil
        )
        #endif
    }

    public static func fetchDNS() async -> DNSSnapshot {
        let native = NativeNetworkTelemetry.readDNS()
        #if APP_STORE
        return native
        #else
        if !native.servers.isEmpty {
            return native
        }
        let (out, _) = await runCommand("/usr/sbin/scutil", arguments: ["--dns"], timeoutSeconds: 2.0)
        return SystemParsers.parseScutilDNS(out)
        #endif
    }

    public static func fetchVPNServices() async -> [VPNService] {
        let native = NativeNetworkTelemetry.readVPNServices()
        #if APP_STORE
        return native
        #else
        if !native.isEmpty {
            return native
        }
        let (out, _) = await runCommand("/usr/sbin/scutil", arguments: ["--nc", "list"], timeoutSeconds: 2.0)
        return SystemParsers.parseScutilNC(out)
        #endif
    }

    public static func fetchProxy() async -> ProxySnapshot {
        NativeNetworkTelemetry.readProxy()
    }

    public static func fetchArpAndExposure(
        interfaceName: String?,
        gatewayIP: String?,
        localIP: String? = nil,
        localMAC: String? = nil
    ) async -> (gatewayMAC: String?, exposure: LANExposureSnapshot, devices: [LANDevice]) {
        // 100% Native Darwin sysctl ARP read (0 subprocesses, MAS sandbox legal!)
        let arpParsed = NativeNetworkTelemetry.readArpDevices(
            interfaceName: interfaceName,
            gatewayIP: gatewayIP,
            localIP: localIP,
            localMAC: localMAC
        )

        var userPorts: [ExposedPort] = []
        var systemPorts: [ExposedPort] = []
        #if !APP_STORE
        if !NativeNetworkTelemetry.isSandboxed {
            let lsof = await runCommand("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"], timeoutSeconds: 2.5)
            let portsParsed = SystemParsers.parseListeningPorts(lsof.stdout)
            userPorts = portsParsed.userPorts
            systemPorts = portsParsed.systemPorts
        }
        #endif

        return (
            arpParsed.gatewayMAC,
            LANExposureSnapshot(
                neighborCount: arpParsed.devices.filter { !$0.isLocalMac }.count,
                exposedUserPorts: userPorts,
                exposedSystemPorts: systemPorts
            ),
            arpParsed.devices
        )
    }

    /// Resolves local mDNS/DNS hostnames concurrently for discovered LAN devices.
    /// Bounded to max 20 devices and max 4 in-flight lookups so crowded public Wi-Fi subnets
    /// never exhaust the global libdispatch worker pool.
    public static func resolveDeviceHostnames(_ devices: [LANDevice]) async -> [LANDevice] {
        let targets = devices.enumerated()
            .filter { !$0.element.isLocalMac && $0.element.hostname == nil }
            .prefix(20)
        guard !targets.isEmpty else { return devices }

        let targetList = Array(targets)
        let maxConcurrent = 4
        var updated = devices

        await withTaskGroup(of: (Int, String?).self) { group in
            var nextIndex = 0
            while nextIndex < min(maxConcurrent, targetList.count) {
                let (idx, dev) = targetList[nextIndex]
                nextIndex += 1
                group.addTask {
                    let name = await reverseLookupIPv4(dev.ip)
                    return (idx, name)
                }
            }
            for await (idx, name) in group {
                if let name, !name.isEmpty {
                    updated[idx].hostname = name
                }
                if nextIndex < targetList.count && !Task.isCancelled {
                    let (nIdx, nDev) = targetList[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let name = await reverseLookupIPv4(nDev.ip)
                        return (nIdx, name)
                    }
                }
            }
        }
        return updated
    }

    private static func reverseLookupIPv4(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else {
                    continuation.resume(returning: nil)
                    return
                }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let res = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                    }
                }
                guard res == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let name = host.withUnsafeBufferPointer { buf in
                    buf.baseAddress.map { String(cString: $0) } ?? ""
                }
                continuation.resume(returning: name.isEmpty || name == ip ? nil : name)
            }
        }
    }

    // MARK: - Captive Portal Detection (Hotel / Airport Login Walls)

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    /// Strict URL sanitizer for untrusted captive-portal redirect `Location` headers.
    /// Rejects non-HTTP(S) schemes (e.g. `file://`, `smb://`, custom app URL schemes) to prevent
    /// LaunchServices scheme abuse via MITM on public Wi-Fi.
    public static func sanitizeCaptivePortalURL(_ raw: String?) -> String {
        let fallback = "http://captive.apple.com"
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let parsed = URL(string: raw),
              let scheme = parsed.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = parsed.host, !host.isEmpty else {
            return fallback
        }
        return parsed.absoluteString
    }

    public static func checkCaptivePortal() async -> CaptivePortalState {
        guard let url = URL(string: "http://captive.apple.com/hotspot-detect.html") else {
            return .clear
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 3.0
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .clear }
            if (300...399).contains(http.statusCode) {
                let safeLocation = sanitizeCaptivePortalURL(http.value(forHTTPHeaderField: "Location"))
                return .detected(loginURL: safeLocation)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 200 && body.contains("Success") {
                return .clear
            }
            return .detected(loginURL: "http://captive.apple.com")
        } catch {
            // Network timeout / offline is handled by HopHealth, not treated as a captive portal
            return .clear
        }
    }

    // MARK: - 1-Click DNS Preset Switcher (Direct Build Only — Excluded from Mac App Store Binary per 2.4.5(v))

    public static func wifiServiceName() async -> String {
        if let nativeService = NativeNetworkTelemetry.readNetworkServiceName(forBSDInterface: "en0") {
            return nativeService
        }
        #if !APP_STORE
        let (out, _) = await runCommand("/usr/sbin/networksetup", arguments: ["-listallhardwareports"], timeoutSeconds: 2.0)
        var lastPort: String?
        for line in out.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Hardware Port:") {
                lastPort = t.dropFirst("Hardware Port:".count).trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("Device: en0"), let port = lastPort {
                return port
            }
        }
        #endif
        return "Wi-Fi"
    }

    #if !APP_STORE
    /// Builds injection-safe `/usr/bin/osascript` argv for privileged DNS updates.
    /// Never interpolates `service` or `servers` into AppleScript source or shell strings:
    /// passes values via `argv` and applies AppleScript's native `quoted form of`.
    public static func buildPrivilegedDNSScriptArguments(service: String, servers: [String]) -> [String]? {
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedService.isEmpty, trimmedService.count <= 128,
              !trimmedService.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !servers.isEmpty else {
            return nil
        }
        for s in servers {
            if s == "Empty" { continue }
            var ipv4 = in_addr()
            var ipv6 = in6_addr()
            let validIP = inet_pton(AF_INET, s, &ipv4) == 1 || inet_pton(AF_INET6, s, &ipv6) == 1
            guard validIP else { return nil }
        }
        let script = """
        on run argv
            set cmd to "/usr/sbin/networksetup -setdnsservers"
            repeat with arg in argv
                set cmd to cmd & " " & quoted form of (arg as text)
            end repeat
            do shell script cmd with administrator privileges
        end run
        """
        return ["-e", script, "--", trimmedService] + servers
    }
    #endif

    public static func applyDNSPreset(_ preset: DNSPreset) async -> Bool {
        #if APP_STORE
        return false
        #else
        let service = await wifiServiceName()
        var args = ["-setdnsservers", service]
        args.append(contentsOf: preset.servers)
        let (_, code) = await runCommand("/usr/sbin/networksetup", arguments: args, timeoutSeconds: 4.0)
        if code == 0 {
            await flushDNSCache()
            return true
        }
        // Fallback: prompt native macOS administrator privileges via injection-safe osascript argv
        guard let osaArgs = buildPrivilegedDNSScriptArguments(service: service, servers: preset.servers) else {
            return false
        }
        let (_, osaCode) = await runCommand("/usr/bin/osascript", arguments: osaArgs, timeoutSeconds: 20.0)
        if osaCode == 0 {
            await flushDNSCache()
            return true
        }
        return false
        #endif
    }

    // MARK: - On-Demand Wi-Fi Password Retrieval (Direct Build Only)

    public static func fetchKeychainWiFiPassword(ssid: String) async -> String? {
        #if APP_STORE
        return nil
        #else
        guard !NativeNetworkTelemetry.isSandboxed,
              !ssid.isEmpty, ssid.utf8.count <= 64, !ssid.contains("\0") else {
            return nil
        }
        let (out, code) = await runCommand(
            "/usr/bin/security",
            arguments: ["find-generic-password", "-D", "AirPort network password", "-a", ssid, "-w"],
            timeoutSeconds: 25.0
        )
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code == 0, !trimmed.isEmpty else { return nil }
        return trimmed
        #endif
    }

    // MARK: - Live Outbound Connection X-Ray & Local mDNS Broadcast Name

    public static func fetchConnectionXRay() async -> ConnectionXRay {
        #if APP_STORE
        return ConnectionXRay()
        #else
        guard !NativeNetworkTelemetry.isSandboxed else { return ConnectionXRay() }
        let (out, _) = await runCommand(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:ESTABLISHED"],
            timeoutSeconds: 2.5
        )
        return SystemParsers.parseEstablishedConnections(out)
        #endif
    }

    public static func fetchLocalHostName() async -> String? {
        if let native = NativeNetworkTelemetry.readLocalHostName() {
            return native
        }
        #if APP_STORE
        return nil
        #else
        let (out, code) = await runCommand("/usr/sbin/scutil", arguments: ["--get", "LocalHostName"], timeoutSeconds: 1.5)
        let name = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code == 0, !name.isEmpty else { return nil }
        return "\(name).local"
        #endif
    }

    // MARK: - 3-Hop Live Health (Router -> DNS -> Internet, Dual-Stack IPv4/IPv6 NAT64 Safe)

    public static func probeHopHealth(gatewayIP: String?) async -> HopHealth {
        async let router = probePingMs(host: gatewayIP)
        async let dns = probeDNSLatencyMs()
        // Use dual-stack hostname instead of IPv4 literal so Apple IPv6-only NAT64 review passes (Guideline 2.5.5)
        async let internet = probeTCPConnectMs(host: "one.one.one.one", port: 443)
        let (r, d, w) = await (router, dns, internet)
        return HopHealth(routerMs: r, dnsMs: d, internetMs: w, updatedAt: Date())
    }

    private static func probePingMs(host: String?) async -> Double? {
        guard let host, !host.isEmpty else { return nil }
        // Fast native unprivileged SOCK_DGRAM ICMP Echo (0 subprocesses, MAS sandbox legal!)
        let nativeMs: Double? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: NativeNetworkTelemetry.icmpPingMs(ipv4Host: host, timeoutMs: 800))
            }
        }
        if let nativeMs { return nativeMs }

        #if APP_STORE
        return nil
        #else
        // Fallback to /sbin/ping if needed
        let (out, code) = await runCommand("/sbin/ping", arguments: ["-c", "1", "-W", "800", host], timeoutSeconds: 1.5)
        guard code == 0 else { return nil }
        guard let range = out.range(of: "time=") else { return nil }
        let tail = out[range.upperBound...]
        let numStr = tail.prefix(while: { $0.isNumber || $0 == "." })
        return Double(numStr)
        #endif
    }

    private static func probeDNSLatencyMs() async -> Double? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let start = CFAbsoluteTimeGetCurrent()
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var res: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo("captive.apple.com", nil, &hints, &res)
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                if let res { freeaddrinfo(res) }
                continuation.resume(returning: status == 0 ? elapsedMs : nil)
            }
        }
    }

    private static func probeTCPConnectMs(host: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.strangechances.aether.tcpprobe", qos: .utility)
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let start = CFAbsoluteTimeGetCurrent()
            final class ProbeGate: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                private let conn: NWConnection
                private let continuation: CheckedContinuation<Double?, Never>

                init(conn: NWConnection, continuation: CheckedContinuation<Double?, Never>) {
                    self.conn = conn
                    self.continuation = continuation
                }

                func finish(_ value: Double?) {
                    let shouldResume = lock.withLock { () -> Bool in
                        guard !resumed else { return false }
                        resumed = true
                        return true
                    }
                    if shouldResume {
                        conn.cancel()
                        continuation.resume(returning: value)
                    }
                }
            }

            let gate = ProbeGate(conn: conn, continuation: continuation)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.finish((CFAbsoluteTimeGetCurrent() - start) * 1000.0)
                case .failed, .cancelled:
                    gate.finish(nil)
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + 2.0) {
                gate.finish(nil)
            }
            conn.start(queue: queue)
        }
    }

    // MARK: - Per-Process Bandwidth (`nettop`, Direct Build Only)

    /// Captures a real 1-second external-interface delta per process in a single ~1.0s call.
    /// `-t external` excludes loopback noise and cuts runtime from ~5.1s down to ~1.0s while still capturing Wi-Fi & VPN traffic.
    public static func sampleNettopDelta(limit: Int = 6) async -> [ProcessBandwidth] {
        #if APP_STORE
        return []
        #else
        guard !NativeNetworkTelemetry.isSandboxed else { return [] }
        let (out, _) = await runCommand(
            "/usr/bin/nettop",
            arguments: ["-P", "-n", "-t", "external", "-L", "2", "-s", "1", "-d", "-J", "bytes_in,bytes_out", "-x"],
            timeoutSeconds: 6.0
        )
        return SystemParsers.parseNettopDelta(out, elapsedSeconds: 1.0, limit: limit)
        #endif
    }

    public static func sampleNettopSnapshot() async -> [String: SystemParsers.NettopRow] {
        #if APP_STORE
        return [:]
        #else
        guard !NativeNetworkTelemetry.isSandboxed else { return [:] }
        let (out, _) = await runCommand(
            "/usr/bin/nettop",
            arguments: ["-P", "-n", "-t", "external", "-L", "1", "-J", "bytes_in,bytes_out", "-x"],
            timeoutSeconds: 6.0
        )
        return SystemParsers.parseNettopSnapshot(out)
        #endif
    }

    // MARK: - Built-in macOS Speed & Bufferbloat Test (`networkQuality -c` or Pure-Swift Sandbox Test)

    public static func runNetworkQuality(maxSeconds: Int = 8) async -> NetworkQualityResult? {
        #if APP_STORE
        return await NativeNetworkTelemetry.runNativeQualityTest()
        #else
        if NativeNetworkTelemetry.isSandboxed {
            return await NativeNetworkTelemetry.runNativeQualityTest()
        }
        let (out, code) = await runCommand(
            "/usr/bin/networkQuality",
            arguments: ["-c", "-M", "\(maxSeconds)"],
            timeoutSeconds: Double(maxSeconds) + 6.0
        )
        if code == 0, let data = out.data(using: .utf8), let parsed = SystemParsers.parseNetworkQualityJSON(data) {
            return parsed
        }
        return await NativeNetworkTelemetry.runNativeQualityTest()
        #endif
    }

    // MARK: - Actions (VPN toggle, DNS flush, On-Demand Public IP)

    public static func setVPNConnected(_ service: VPNService, connect: Bool) async -> Bool {
        if NativeNetworkTelemetry.setVPNConnected(service, connect: connect) {
            return true
        }
        #if APP_STORE
        return false
        #else
        let verb = connect ? "start" : "stop"
        let (_, code) = await runCommand("/usr/sbin/scutil", arguments: ["--nc", verb, service.uuid], timeoutSeconds: 4.0)
        return code == 0
        #endif
    }

    @discardableResult
    public static func flushDNSCache() async -> Bool {
        #if APP_STORE
        return false
        #else
        let (_, code) = await runCommand("/usr/bin/dscacheutil", arguments: ["-flushcache"], timeoutSeconds: 2.0)
        return code == 0
        #endif
    }

    /// Strictly on-demand — never called in the background without explicit user click.
    /// Uses an ephemeral, no-cache URLSession so VPN/network switches never return a stale cached IP.
    public static func fetchPublicIP() async -> PublicIPInfo? {
        guard let url = URL(string: "https://ipinfo.io/json") else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 5.0
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 4.0)
        req.setValue("Aether/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["ip"] as? String else {
            return nil
        }
        return PublicIPInfo(
            ip: ip,
            org: json["org"] as? String,
            city: json["city"] as? String,
            country: json["country"] as? String
        )
    }
}
