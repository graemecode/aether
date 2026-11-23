import AetherCore
import AppKit
import Combine
import CoreLocation
import Foundation
import Network
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Live Telemetry State

    @Published var wifi = WiFiSnapshot()
    @Published var route = RouteInfo()
    @Published var dns = DNSSnapshot()
    @Published var vpns: [VPNService] = []
    @Published var proxy = ProxySnapshot()
    @Published var exposure = LANExposureSnapshot()
    @Published var hopHealth = HopHealth()
    @Published var trustAudit = TrustAudit()
    @Published var captivePortal: CaptivePortalState = .clear

    // MARK: - Paid-App-Killer Features (Channel Spectrum, Stability, LAN Devices, Events, QR)

    @Published var channelAnalysis = ChannelAnalysis()
    @Published var latencyHistory: [LatencySample] = []
    @Published var stability = StabilityMetrics()
    @Published var events: [NetworkEvent] = []
    @Published var lanDevices: [LANDevice] = []
    @Published var isApplyingDNS = false
    @Published var isRoaming = false

    @Published var qrSharePayload: String?
    @Published var qrShareSSID: String?
    @Published var isLoadingQR = false

    // MARK: - Network Nerd Secrets (RF Physics, AWDL0 Radio, Connection X-Ray, mDNS, IPv6)

    @Published var rfPhysics = RFPhysicsSnapshot()
    @Published var awdl = AWDLSnapshot()
    @Published var hasGlobalIPv6 = false
    @Published var connectionXRay = ConnectionXRay()
    @Published var localBroadcastName: String?

    // MARK: - Throughput & Speed State

    @Published var currentThroughput = ThroughputSample(downloadBytesPerSec: 0, uploadBytesPerSec: 0)
    @Published var throughputHistory: [ThroughputSample] = []
    @Published var sessionDownBytes: UInt64 = 0
    @Published var sessionUpBytes: UInt64 = 0
    @Published var sessionPeakBytesPerSec: Double = 0
    @Published var activeInterfaces: [ActiveInterface] = []
    @Published var topProcesses: [ProcessBandwidth] = []
    @Published var studioFocusConnections = false

    @Published var qualityResult: NetworkQualityResult?
    @Published var isRunningQualityTest = false

    // MARK: - Networks & Public IP

    @Published var nearbyNetworks: [NearbyNetwork] = []
    @Published var rawScanBSSIDs: [NearbyNetwork] = []
    @Published var knownSSIDs: [String] = []
    @Published var isScanningNetworks = false
    @Published var connectingSSID: String?
    @Published var connectionError: String?

    @Published var publicIP: PublicIPInfo?
    @Published var isFetchingPublicIP = false

    // MARK: - Permissions & UI State

    @Published var hasLocationAccess = false
    @Published var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationServicesEnabled = true
    @Published var isRequestingLocation = false
    @Published var didAttemptLocationPrompt = false
    @Published var showSettingsWhileDisconnected = false
    @Published var activeTab: PanelTab = .speed
    @Published var stageMode: StageMode = .flux {
        didSet { store.stageMode = stageMode }
    }
    @Published var menuBarMode: MenuBarDisplayMode = .autoSpeed {
        didSet {
            store.menuBarMode = menuBarMode
            emitMenuBarTick()
        }
    }
    @Published var isProMode: Bool = false {
        didSet { store.isProMode = isProMode }
    }
    @Published var hasDismissedOnboarding: Bool = false {
        didSet { store.hasDismissedOnboarding = hasDismissedOnboarding }
    }
    @Published var currentTrustZone: TrustZone = .home
    @Published var isPopoverOpen = false {
        didSet { updateInteractivePolling() }
    }
    @Published var isStudioOpen = false {
        didSet { updateInteractivePolling() }
    }
    @Published var isStatusItemBehindNotch = false
    @Published var launchAtLogin = false
    @Published var statusBanner: String?

    var onMenuBarTick: ((WiFiSnapshot, TrustAudit, ThroughputSample, MenuBarDisplayMode, Bool) -> Void)?
    var onRequestPanelResize: (() -> Void)?

    // MARK: - Internals

    private let store = TrustStore()
    private let counters = InterfaceCounters()
    private let wifiController = WiFiController()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.strangechances.aether.pathmonitor", qos: .utility)

    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var interactiveTimer: Timer?
    private var bannerTask: Task<Void, Never>?
    private var qualityTask: Task<Void, Never>?
    private var locationRequestTask: Task<Void, Never>?
    private var lanResolveTask: Task<Void, Never>?
    private var lanResolutionGeneration: UInt64 = 0
    private var lastNetworkIdentifierKey: String?
    private var lastNettopRows: [String: SystemParsers.NettopRow]?
    private var lastNettopDate: Date?
    private var isRefreshingEnvironment = false
    private var pendingRefreshNeeded = false
    private var pendingRefreshIncludeHops = false
    private var interactiveTickCount = 0
    private var fastTickCount = 0
    private var internalThroughputRing: [ThroughputSample] = []
    private var latestWiFiCache = WiFiSnapshot()

    var isSandboxed: Bool {
        #if APP_STORE
        return true
        #else
        return NativeNetworkTelemetry.isSandboxed
        #endif
    }

    static let privacyPolicyURL = URL(string: "https://strangechances.com/aether/privacy")!

    // Event deduplication tracking
    private var prevBSSID: String?
    private var prevBand: WiFiBand = .unknown
    private var prevGatewayMAC: String?
    private var prevActiveVPNName: String?

    private let maxHistoryCount = 60
    private let maxLatencyCount = 120
    private let maxEventCount = 80

    private init() {
        self.menuBarMode = store.menuBarMode
        self.stageMode = store.stageMode
        self.isProMode = store.isProMode
        self.hasDismissedOnboarding = store.hasDismissedOnboarding
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        let seed = (0..<maxHistoryCount).map { _ in
            ThroughputSample(downloadBytesPerSec: 0, uploadBytesPerSec: 0)
        }
        self.internalThroughputRing = seed
        self.throughputHistory = seed
    }

    // MARK: - Lifecycle

    func boot() {
        updateLocationStatus()
        knownSSIDs = wifiController.knownNetworkSSIDs()

        wifiController.onEventChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshImmediate()
            }
        }
        wifiController.onLocationAuthorizationChanged = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let hadAccess = self.hasLocationAccess
                self.locationRequestTask?.cancel()
                self.isRequestingLocation = false
                self.updateLocationStatus()
                if self.hasLocationAccess && !hadAccess {
                    self.didAttemptLocationPrompt = false
                    self.showBanner("Wi-Fi names enabled")
                }
                self.refreshImmediate()
                if self.hasLocationAccess {
                    await self.scanNearbyNetworks()
                }
            }
        }

        // Instant OS-level network path change notifications (Wi-Fi switch, VPN connect, Ethernet plug-in)
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshImmediate()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)

        tickFast()
        Task {
            await refreshEnvironment(includeHops: true)
            await scanNearbyNetworks()
        }

        // 1 Hz ultra-light POSIX counter + CoreWLAN read (<0.1% CPU, 0 subprocesses)
        fastTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickFast()
            }
        }

        // 45 s background idle hygiene check (heavy lsof/nettop only run while popover/Studio is open)
        slowTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshEnvironment(includeHops: self.isAnySurfaceOpen)
            }
        }
    }

    func handleSystemWake() {
        counters.resetBaseline()
        lastNettopRows = nil
        lastNettopDate = nil
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            await self.refreshEnvironment(includeHops: true)
        }
    }

    func shutdown() {
        pathMonitor.cancel()
        fastTimer?.invalidate()
        slowTimer?.invalidate()
        interactiveTimer?.invalidate()
        qualityTask?.cancel()
        bannerTask?.cancel()
        locationRequestTask?.cancel()
        lanResolveTask?.cancel()
    }

    var isAnySurfaceOpen: Bool {
        isPopoverOpen || isStudioOpen
    }

    // MARK: - Polling Loops

    private func tickFast(forceWiFiRead: Bool = false) {
        fastTickCount += 1
        let preferredIface = InterfaceCounters.physicalThroughputInterface(
            defaultInterface: route.defaultInterface,
            wifiInterface: latestWiFiCache.interfaceName,
            wifiConnected: latestWiFiCache.isConnected
        )
        let activeVPNName = vpns.first(where: { $0.isConnected })?.name
        let counterSample = counters.readSample(
            preferredInterface: preferredIface,
            wifiInterface: latestWiFiCache.interfaceName,
            connectedVPNName: activeVPNName
        )

        // Throttle CoreWLAN XPC calls to airportd: every 5s when idle, every 2s when open (instant on force/events)
        let wifiInterval = isAnySurfaceOpen ? 2 : 5
        var snap = latestWiFiCache
        if forceWiFiRead || fastTickCount == 1 || (fastTickCount % wifiInterval == 0) {
            snap = wifiController.currentSnapshot()
        }

        // CoreWLAN returns factory hardware MAC; `getifaddrs` AF_LINK returns the actual over-the-air MAC!
        if let liveMAC = counterSample.activeWiFiMAC {
            let factoryMAC = snap.hardwareMAC?.lowercased()
            let differsFromFactory = (factoryMAC != nil && factoryMAC != liveMAC.lowercased())
            let localBit = SystemParsers.isLocallyAdministeredMAC(liveMAC) ?? false
            snap.hardwareMAC = liveMAC
            snap.isPrivateMAC = differsFromFactory || localBit
        }

        detectRadioEvents(newWifi: snap)
        latestWiFiCache = snap

        internalThroughputRing.append(counterSample.sample)
        if internalThroughputRing.count > maxHistoryCount {
            internalThroughputRing.removeFirst(internalThroughputRing.count - maxHistoryCount)
        }

        // Only mutate @Published SwiftUI properties when a UI surface is open (or on initial boot/force)
        // so closed-popover idle CPU stays near 0.0%!
        if isAnySurfaceOpen || forceWiFiRead || fastTickCount == 1 {
            if self.wifi != snap { self.wifi = snap }
            self.awdl = counterSample.awdl
            self.hasGlobalIPv6 = counterSample.hasGlobalIPv6
            self.rfPhysics = RFPhysics.compute(wifi: snap, overlappingAPs: channelAnalysis.overlappingCount)
            self.currentThroughput = counterSample.sample
            self.sessionDownBytes = counterSample.sessionDownBytes
            self.sessionUpBytes = counterSample.sessionUpBytes
            self.sessionPeakBytesPerSec = counterSample.sessionPeakBytesPerSec
            if self.activeInterfaces != counterSample.activeInterfaces {
                self.activeInterfaces = counterSample.activeInterfaces
            }
            self.throughputHistory = internalThroughputRing
            if let ip = counterSample.localIP, self.route.localIP != ip {
                self.route.localIP = ip
            }
        }

        onMenuBarTick?(snap, trustAudit, counterSample.sample, menuBarMode, !snap.isConnected && route.defaultInterface != nil)
    }

    func refreshImmediate() {
        tickFast(forceWiFiRead: true)
        Task { await refreshEnvironment(includeHops: true) }
    }

    private func updateInteractivePolling() {
        if !isPopoverOpen {
            // Clear sensitive Wi-Fi QR payload whenever popover closes
            qrSharePayload = nil
            qrShareSSID = nil
            showSettingsWhileDisconnected = false
        }

        if isAnySurfaceOpen {
            updateLocationStatus()
            knownSSIDs = wifiController.knownNetworkSSIDs()
            // Sync latest ring buffer & Wi-Fi snapshot immediately on open
            self.throughputHistory = internalThroughputRing
            tickFast(forceWiFiRead: true)
            if interactiveTimer == nil {
                lastNettopRows = nil
                lastNettopDate = nil
                interactiveTickCount = 0

                let disconnectedOnOpen = isDisconnected
                Task {
                    await refreshEnvironment(includeHops: true)
                    await sampleProcessBandwidth()
                    // Quick second baseline delta so live per-app speeds appear in ~1s on open
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    if self.isAnySurfaceOpen {
                        await sampleProcessBandwidth()
                    }
                    if disconnectedOnOpen || rawScanBSSIDs.isEmpty {
                        await scanNearbyNetworks()
                    }
                }

                interactiveTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.isAnySurfaceOpen else { return }
                        self.interactiveTickCount += 1
                        await self.sampleProcessBandwidth()
                        if self.interactiveTickCount % 2 == 0 {
                            await self.sampleHopsOnly()
                        }
                    }
                }
            } else if isDisconnected {
                Task { await scanNearbyNetworks() }
            }
        } else {
            interactiveTimer?.invalidate()
            interactiveTimer = nil
            lastNettopRows = nil
            lastNettopDate = nil
        }
    }

    func refreshEnvironment(includeHops: Bool) async {
        if isRefreshingEnvironment {
            pendingRefreshNeeded = true
            pendingRefreshIncludeHops = pendingRefreshIncludeHops || includeHops
            return
        }
        isRefreshingEnvironment = true
        defer {
            isRefreshingEnvironment = false
            if pendingRefreshNeeded {
                let reHops = pendingRefreshIncludeHops
                pendingRefreshNeeded = false
                pendingRefreshIncludeHops = false
                Task { @MainActor [weak self] in
                    await self?.refreshEnvironment(includeHops: reHops)
                }
            }
        }

        let currentLocalIP = route.localIP
        async let routeTask = NetworkProbes.fetchRouteInfo(localIP: currentLocalIP)
        async let dnsTask = NetworkProbes.fetchDNS()
        async let vpnTask = NetworkProbes.fetchVPNServices()
        async let proxyTask = NetworkProbes.fetchProxy()
        // Only run lsof established-socket X-Ray while UI is open or on initial boot to preserve idle battery
        let shouldRunXRay = isAnySurfaceOpen || connectionXRay.totalOutboundSockets == 0
        async let xrayTask: ConnectionXRay? = shouldRunXRay ? NetworkProbes.fetchConnectionXRay() : nil
        async let mdnsTask: String? = localBroadcastName == nil ? NetworkProbes.fetchLocalHostName() : localBroadcastName

        var newRoute = await routeTask
        let newDNS = await dnsTask
        let newVPNs = await vpnTask
        let newProxy = await proxyTask
        if let newXRay = await xrayTask {
            self.connectionXRay = newXRay
        }
        let newMDNS = await mdnsTask
        self.localBroadcastName = newMDNS
        let activeXRay = self.connectionXRay

        // Always read ARP/LAN on the physical L2 interface (never a `utun` VPN tunnel) so
        // Evil-Twin gateway monitoring and public-Wi-Fi neighbor counts keep working under full-tunnel VPNs.
        let arpIface = NativeNetworkTelemetry.physicalInterfaceForARP(
            defaultInterface: newRoute.defaultInterface,
            wifiInterface: wifi.interfaceName,
            wifiConnected: wifi.isConnected
        )
        let (gwMAC, newExposure, rawDevices) = await NetworkProbes.fetchArpAndExposure(
            interfaceName: arpIface,
            gatewayIP: newRoute.gatewayIP,
            localIP: newRoute.localIP,
            localMAC: wifi.hardwareMAC
        )
        newRoute.gatewayMAC = gwMAC

        // Detect gateway MAC / VPN change events
        if let prevGW = prevGatewayMAC, let curGW = gwMAC, prevGW != curGW {
            recordEvent(
                kind: .gatewayChange,
                title: "Gateway MAC changed",
                detail: "\(prevGW) → \(curGW)",
                severity: .alert
            )
        }
        if let gwMAC { prevGatewayMAC = gwMAC }

        let newActiveVPN = newVPNs.first(where: { $0.isConnected })?.name
        if prevActiveVPNName != nil || newActiveVPN != nil {
            if let prev = prevActiveVPNName, prev != newActiveVPN {
                recordEvent(
                    kind: .vpnChange,
                    title: newActiveVPN == nil ? "\(prev) disconnected" : "Switched VPN to \(newActiveVPN!)",
                    detail: newActiveVPN == nil ? "Traffic now exiting direct ISP route" : "Encrypted tunnel active",
                    severity: newActiveVPN == nil ? .caution : .ok
                )
            } else if prevActiveVPNName == nil, let cur = newActiveVPN {
                recordEvent(
                    kind: .vpnChange,
                    title: "\(cur) connected",
                    detail: "Encrypted tunnel shielding network traffic",
                    severity: .ok
                )
            }
        }
        prevActiveVPNName = newActiveVPN

        self.route = newRoute
        self.dns = newDNS
        self.vpns = newVPNs
        self.proxy = newProxy
        self.exposure = newExposure

        // Merge preserved hostnames so UI never flickers while resolving new LAN peers
        let existingNames = Dictionary(uniqueKeysWithValues: lanDevices.compactMap { dev in
            dev.hostname.map { (dev.ip, $0) }
        })
        let mergedDevices = rawDevices.map { dev -> LANDevice in
            var copy = dev
            if copy.hostname == nil, let cached = existingNames[dev.ip] {
                copy.hostname = cached
            }
            return copy
        }
        self.lanDevices = mergedDevices

        // Resolve any missing hostnames in background with generation guard so switching
        // networks mid-lookup can never overwrite the new network's LAN device list.
        if mergedDevices.contains(where: { !$0.isLocalMac && $0.hostname == nil }) {
            lanResolutionGeneration &+= 1
            let gen = lanResolutionGeneration
            lanResolveTask?.cancel()
            lanResolveTask = Task { @MainActor [weak self] in
                let resolved = await NetworkProbes.resolveDeviceHostnames(mergedDevices)
                guard !Task.isCancelled, let self, self.lanResolutionGeneration == gen else { return }
                let resolvedByIP = Dictionary(uniqueKeysWithValues: resolved.compactMap { dev in
                    dev.hostname.map { (dev.ip, $0) }
                })
                self.lanDevices = self.lanDevices.map { dev in
                    var copy = dev
                    if copy.hostname == nil, let name = resolvedByIP[dev.ip] {
                        copy.hostname = name
                    }
                    return copy
                }
            }
        }

        // Update Channel Analysis & RF Physics with latest snapshot
        self.channelAnalysis = ChannelAnalyzer.analyze(current: wifi, rawBSSIDs: rawScanBSSIDs)
        self.rfPhysics = RFPhysics.compute(wifi: wifi, overlappingAPs: channelAnalysis.overlappingCount)

        // Clear stale per-network caches when switching networks or going offline
        let netKey = networkIdentifierKey
        if let prevKey = lastNetworkIdentifierKey, prevKey != netKey {
            publicIP = nil
            qualityResult = nil
            qrSharePayload = nil
            qrShareSSID = nil
        }
        lastNetworkIdentifierKey = netKey
        if isDisconnected {
            hopHealth = HopHealth()
            captivePortal = .clear
        }

        // Resolve TrustZone (explicit override or smart default: open/crowded Wi-Fi -> Public) & AP/Gateway fingerprint
        let zone = store.resolvedTrustZone(for: netKey, wifi: wifi, exposure: newExposure)
        self.currentTrustZone = zone

        var pinned: NetworkFingerprint?
        if let ssid = wifi.ssid, !ssid.isEmpty {
            pinned = store.fingerprint(for: ssid)
            if pinned == nil && newRoute.gatewayMAC != nil {
                pinned = store.observeNetwork(
                    ssid: ssid,
                    bssid: wifi.bssid,
                    gatewayMAC: newRoute.gatewayMAC,
                    securityRank: wifi.security.strengthRank
                )
            }
        }

        let audit = TrustAnalyzer.evaluate(
            wifi: wifi,
            route: newRoute,
            dns: newDNS,
            vpns: newVPNs,
            proxy: newProxy,
            exposure: newExposure,
            zone: zone,
            pinnedFingerprint: pinned,
            localBroadcastName: newMDNS,
            connectionXRay: activeXRay
        )
        self.trustAudit = audit

        // Keep lastSeen, knownBSSIDs, and upgraded security rank fresh without overwriting anomalous gatewayMAC
        if let ssid = wifi.ssid, !ssid.isEmpty, pinned != nil, !audit.hasGatewayAnomaly, !audit.hasSecurityDowngrade {
            _ = store.observeNetwork(
                ssid: ssid,
                bssid: wifi.bssid,
                gatewayMAC: newRoute.gatewayMAC,
                securityRank: wifi.security == .unknown ? 0 : wifi.security.strengthRank
            )
        }

        emitMenuBarTick()

        if includeHops {
            await sampleHopsOnly()
        }
    }

    private func sampleHopsOnly() async {
        let hops = await NetworkProbes.probeHopHealth(gatewayIP: route.gatewayIP)
        self.hopHealth = hops

        let sample = LatencySample(
            timestamp: Date(),
            routerMs: hops.routerMs,
            dnsMs: hops.dnsMs,
            internetMs: hops.internetMs
        )
        latencyHistory.append(sample)
        if latencyHistory.count > maxLatencyCount {
            latencyHistory.removeFirst(latencyHistory.count - maxLatencyCount)
        }
        self.stability = StabilityCalculator.compute(samples: latencyHistory)

        // Log notable latency spikes or drops
        if hops.internetMs == nil && hops.routerMs != nil {
            recordEvent(
                kind: .packetDrop,
                title: "Upstream drop",
                detail: "Router reachable (\(ByteRateFormatter.ms(hops.routerMs))), internet timed out",
                severity: .alert
            )
            // Check if a captive portal is blocking upstream HTTP
            let portal = await NetworkProbes.checkCaptivePortal()
            if portal != captivePortal {
                captivePortal = portal
                if case .detected(let url) = portal {
                    recordEvent(kind: .captivePortal, title: "Captive portal detected", detail: url, severity: .caution)
                }
            }
        } else {
            if captivePortal.isDetected {
                captivePortal = .clear
            }
            if let web = hops.internetMs, web >= 160 {
                recordEvent(
                    kind: .latencySpike,
                    title: "Latency spike (\(Int(round(web))) ms)",
                    detail: "Router \(ByteRateFormatter.ms(hops.routerMs)) · DNS \(ByteRateFormatter.ms(hops.dnsMs))",
                    severity: .caution
                )
            }
        }
    }

    private func detectRadioEvents(newWifi: WiFiSnapshot) {
        if let prev = prevBSSID, let cur = newWifi.bssid, prev != cur {
            recordEvent(
                kind: .roam,
                title: "Roamed to new AP",
                detail: "\(newWifi.band.shortBadge) Ch \(newWifi.channel) (\(newWifi.rssi) dBm)",
                severity: .info
            )
        }
        if prevBand != .unknown && newWifi.band != .unknown && prevBand != newWifi.band {
            let downgraded = (prevBand == .band5 || prevBand == .band6) && newWifi.band == .band24
            recordEvent(
                kind: .bandChange,
                title: downgraded ? "Dropped to 2.4 GHz" : "Upgraded to \(newWifi.band.rawValue)",
                detail: "\(prevBand.shortBadge) → \(newWifi.band.shortBadge) (Ch \(newWifi.channel))",
                severity: downgraded ? .caution : .ok
            )
        }
        if let b = newWifi.bssid { prevBSSID = b }
        if newWifi.band != .unknown { prevBand = newWifi.band }
    }

    private func recordEvent(kind: NetworkEventKind, title: String, detail: String, severity: AuditSeverity) {
        // Avoid duplicating identical consecutive events within 20 seconds
        if let last = events.first, last.kind == kind && last.title == title,
           Date().timeIntervalSince(last.timestamp) < 20 {
            return
        }
        events.insert(NetworkEvent(kind: kind, title: title, detail: detail, severity: severity), at: 0)
        if events.count > maxEventCount {
            events.removeLast(events.count - maxEventCount)
        }
    }

    private func sampleProcessBandwidth() async {
        let now = Date()
        let rows = await NetworkProbes.sampleNettopSnapshot()
        if let prev = lastNettopRows, let prevDate = lastNettopDate {
            let dt = now.timeIntervalSince(prevDate)
            let top = SystemParsers.diffNettop(previous: prev, current: rows, elapsedSeconds: dt, limit: 6)
            self.topProcesses = top
        }
        lastNettopRows = rows
        lastNettopDate = now
    }

    // MARK: - User Actions

    func selectTab(_ tab: PanelTab) {
        performHaptic()
        activeTab = tab
        if tab == .networks && nearbyNetworks.isEmpty {
            Task { await scanNearbyNetworks() }
        }
        DispatchQueue.main.async { [weak self] in
            self?.onRequestPanelResize?()
        }
    }

    func cycleStageMode() {
        let all = StageMode.allCases
        stageMode = all[(stageMode.rawValue + 1) % all.count]
        performHaptic()
    }

    func toggleWiFiPower() {
        performHaptic()
        let next = !wifi.powerOn
        do {
            try wifiController.setPower(next)
            showBanner(next ? "Wi-Fi turned on" : "Wi-Fi turned off")
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                self.refreshImmediate()
            }
        } catch {
            showBanner("Could not toggle Wi-Fi")
        }
    }

    func scanNearbyNetworks() async {
        guard !isScanningNetworks else { return }
        isScanningNetworks = true
        defer { isScanningNetworks = false }
        self.knownSSIDs = wifiController.knownNetworkSSIDs()
        let res = await wifiController.scanDetailed()
        self.nearbyNetworks = res.uniqueNetworks
        self.rawScanBSSIDs = res.allBSSIDs
        self.channelAnalysis = ChannelAnalyzer.analyze(current: wifi, rawBSSIDs: res.allBSSIDs)
    }

    func roamToBetterAP() {
        guard let ssid = wifi.ssid, !ssid.isEmpty, !isRoaming else { return }
        performHaptic()
        isRoaming = true
        showBanner("Roaming to faster AP…")
        Task {
            do {
                try await wifiController.roamToBestAP(ssid: ssid)
                self.isRoaming = false
                self.showBanner("Switched AP on \(ssid)")
                try? await Task.sleep(for: .milliseconds(600))
                await self.refreshEnvironment(includeHops: true)
                await self.scanNearbyNetworks()
            } catch {
                self.isRoaming = false
                self.showBanner("Roam failed — \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func connectToNetwork(ssid: String, password: String?) async -> Bool {
        connectingSSID = ssid
        connectionError = nil
        performHaptic()
        do {
            try await wifiController.connect(ssid: ssid, password: password)
            showBanner("Connected to \(ssid)")
            connectingSSID = nil
            showSettingsWhileDisconnected = false
            try? await Task.sleep(for: .milliseconds(600))
            await refreshEnvironment(includeHops: true)
            await scanNearbyNetworks()
            return true
        } catch {
            connectingSSID = nil
            connectionError = error.localizedDescription
            showBanner("Could not join \(ssid)")
            return false
        }
    }

    func toggleVPN(_ service: VPNService) {
        performHaptic()
        let targetConnect = !service.isConnected
        showBanner(targetConnect ? "Connecting \(service.name)…" : "Disconnecting \(service.name)…")
        Task {
            _ = await NetworkProbes.setVPNConnected(service, connect: targetConnect)
            try? await Task.sleep(for: .milliseconds(900))
            await refreshEnvironment(includeHops: true)
        }
    }

    func applyDNSPreset(_ preset: DNSPreset) {
        guard !isApplyingDNS else { return }
        performHaptic()
        isApplyingDNS = true
        showBanner("Switching DNS to \(preset.label)…")
        Task {
            let ok = await NetworkProbes.applyDNSPreset(preset)
            self.isApplyingDNS = false
            if ok {
                self.showBanner("DNS set to \(preset.label)")
                try? await Task.sleep(for: .milliseconds(450))
                await self.refreshEnvironment(includeHops: true)
            } else {
                self.showBanner("DNS update cancelled or failed")
            }
        }
    }

    func checkCaptivePortalManually() {
        performHaptic()
        Task {
            let res = await NetworkProbes.checkCaptivePortal()
            self.captivePortal = res
            switch res {
            case .clear:
                self.showBanner("No captive portal detected")
            case .detected:
                self.showBanner("Captive portal login required")
            }
        }
    }

    func openCaptivePortal() {
        let target: String
        if case .detected(let urlStr) = captivePortal {
            target = NetworkProbes.sanitizeCaptivePortalURL(urlStr)
        } else {
            target = "http://captive.apple.com"
        }
        if let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        }
    }

    func generateShareQR() {
        guard let ssid = wifi.ssid, !ssid.isEmpty else {
            showBanner("Allow Location access to read SSID first")
            return
        }
        if qrSharePayload != nil {
            qrSharePayload = nil
            qrShareSSID = nil
            return
        }
        performHaptic()
        isLoadingQR = true
        Task {
            let password: String?
            if wifi.security == .open {
                password = nil
            } else {
                password = await NetworkProbes.fetchKeychainWiFiPassword(ssid: ssid)
            }
            self.isLoadingQR = false
            if wifi.security != .open && password == nil {
                self.showBanner("Keychain auth cancelled or password unavailable")
                return
            }
            self.qrShareSSID = ssid
            self.qrSharePayload = WiFiQRPayload.make(ssid: ssid, password: password, security: wifi.security)
            self.onRequestPanelResize?()
        }
    }

    func runQualityTest() {
        guard !isRunningQualityTest else { return }
        performHaptic()
        isRunningQualityTest = true
        qualityTask?.cancel()
        qualityTask = Task {
            let result = await NetworkProbes.runNetworkQuality(maxSeconds: 8)
            guard !Task.isCancelled else { return }
            self.isRunningQualityTest = false
            if let result {
                self.qualityResult = result
                self.showBanner(String(format: "%.0f↓ / %.0f↑ Mbps · %d RPM", result.downloadMbps, result.uploadMbps, result.responsivenessRPM))
            } else {
                self.showBanner("Responsiveness test unavailable")
            }
        }
    }

    func revealPublicIP() {
        guard !isFetchingPublicIP else { return }
        performHaptic()
        isFetchingPublicIP = true
        Task {
            let info = await NetworkProbes.fetchPublicIP()
            self.isFetchingPublicIP = false
            if let info {
                self.publicIP = info
            } else {
                self.showBanner("Could not reach ipinfo.io")
            }
        }
    }

    func flushDNS() {
        performHaptic()
        Task {
            let ok = await NetworkProbes.flushDNSCache()
            self.showBanner(ok ? "DNS cache flushed" : "DNS flush unavailable in sandbox")
            await self.sampleHopsOnly()
        }
    }

    func setTrustZone(_ zone: TrustZone) {
        performHaptic()
        store.setTrustZone(zone, for: networkIdentifierKey)
        currentTrustZone = zone
        let pinned = wifi.ssid.flatMap { store.fingerprint(for: $0) }
        trustAudit = TrustAnalyzer.evaluate(
            wifi: wifi,
            route: route,
            dns: dns,
            vpns: vpns,
            proxy: proxy,
            exposure: exposure,
            zone: zone,
            pinnedFingerprint: pinned,
            localBroadcastName: localBroadcastName,
            connectionXRay: connectionXRay
        )
        emitMenuBarTick()
    }

    func trustCurrentFingerprint() {
        guard let ssid = wifi.ssid, !ssid.isEmpty else { return }
        performHaptic()
        store.trustCurrentFingerprint(
            ssid: ssid,
            bssid: wifi.bssid,
            gatewayMAC: route.gatewayMAC,
            securityRank: wifi.security.strengthRank
        )
        showBanner("Pinned current gateway for \(ssid)")
        Task { await refreshEnvironment(includeHops: false) }
    }

    func requestLocationAccess() {
        performHaptic()
        updateLocationStatus()
        if hasLocationAccess {
            Task { await scanNearbyNetworks() }
            return
        }
        if !locationServicesEnabled || locationAuthStatus == .denied || locationAuthStatus == .restricted || didAttemptLocationPrompt {
            openLocationSettings()
            showBanner("Enable Aether in Location Services")
            return
        }

        isRequestingLocation = true
        didAttemptLocationPrompt = true
        NSApp.activate(ignoringOtherApps: true)
        wifiController.requestLocationAccess()
        showBanner("Click Allow on the macOS Location prompt")

        locationRequestTask?.cancel()
        locationRequestTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            self.isRequestingLocation = false
            self.updateLocationStatus()
        }
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func openControlCenterSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func openPrivacyPolicy() {
        NSWorkspace.shared.open(Self.privacyPolicyURL)
    }

    func toggleLaunchAtLogin() {
        performHaptic()
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
                launchAtLogin = false
            } else {
                try SMAppService.mainApp.register()
                launchAtLogin = true
            }
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            showBanner("Launch at Login requires /Applications install")
        }
    }

    func copyToClipboard(_ value: String, label: String) {
        performHaptic()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        showBanner("Copied \(label)")
    }

    func copyDiagnosticsReport() {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        var lines: [String] = [
            "Aether Network Report — \(ISO8601DateFormatter().string(from: Date()))",
            "Network: \(heroTitle) (\(wifi.band.rawValue), Ch \(wifi.channel), \(wifi.channelWidthMHz) MHz, \(wifi.phyGeneration))",
            "RF: RSSI \(wifi.rssi) dBm | Noise \(wifi.noise) dBm | SNR \(wifi.snr) dB | Tx \(Int(wifi.txRateMbps)) Mbps",
            "Channel: \(channelAnalysis.congestionLabel) — \(channelAnalysis.recommendationSummary)",
            "Stability: \(stability.callGrade.rawValue) — \(stability.verdict)",
            "Route: iface=\(route.defaultInterface ?? "—") local=\(route.localIP ?? "—") gw=\(route.gatewayIP ?? "—") gwMAC=\(route.gatewayMAC ?? "—")",
            "Hops: router=\(ByteRateFormatter.ms(hopHealth.routerMs)) dns=\(ByteRateFormatter.ms(hopHealth.dnsMs)) web=\(ByteRateFormatter.ms(hopHealth.internetMs))",
            "DNS: \(dns.providerLabel) [\(dns.servers.joined(separator: ", "))]",
            "VPN: \(activeVPN?.name ?? "None") | Proxy: \(proxy.summary)",
            "Security: \(trustAudit.level.label) (\(trustAudit.score)/100) — \(trustAudit.headline)",
            "LAN: \(lanDevices.count) devices | \(exposure.exposedUserPorts.count) exposed user ports"
        ]
        if !events.isEmpty {
            lines.append("\nRecent Events:")
            for ev in events.prefix(15) {
                lines.append("  [\(fmt.string(from: ev.timestamp))] \(ev.kind.rawValue): \(ev.title) — \(ev.detail)")
            }
        }
        copyToClipboard(lines.joined(separator: "\n"), label: "diagnostics")
    }

    func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    // MARK: - Computed Presentation Helpers

    func consumeShouldAutoOpenOnLaunch() -> Bool {
        if !store.hasLaunchedBefore {
            store.hasLaunchedBefore = true
            return true
        }
        return false
    }

    func dismissOnboarding() {
        performHaptic()
        hasDismissedOnboarding = true
        onRequestPanelResize?()
    }

    var shouldShowOnboardingStrip: Bool {
        !hasDismissedOnboarding && !hasLocationAccess
    }

    var isUpstreamDown: Bool {
        (wifi.isConnected || isWired) && hopHealth.routerMs != nil && hopHealth.internetMs == nil
    }

    var activeVPN: VPNService? {
        vpns.first(where: { $0.isConnected })
    }

    var isWired: Bool {
        !wifi.isConnected && route.defaultInterface != nil
    }

    var isDisconnected: Bool {
        !wifi.isConnected && !isWired
    }

    var needsManualLocationSettings: Bool {
        !locationServicesEnabled || locationAuthStatus == .denied || locationAuthStatus == .restricted || didAttemptLocationPrompt
    }

    var detectedDNSPreset: DNSPreset? {
        if dns.servers.contains("1.1.1.1") || dns.servers.contains("1.0.0.1") { return .cloudflare }
        if dns.servers.contains("9.9.9.9") { return .quad9 }
        if dns.servers.contains("8.8.8.8") { return .google }
        if dns.posture == .localRouter { return .automatic }
        return nil
    }

    var networkIdentifierKey: String {
        if let ssid = wifi.ssid, !ssid.isEmpty { return "ssid:\(ssid)" }
        if let gw = route.gatewayMAC, !gw.isEmpty { return "gw:\(gw)" }
        if let iface = route.defaultInterface { return "if:\(iface)" }
        return "default"
    }

    var heroTitle: String {
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return ssid
        }
        if wifi.isConnected {
            return isProMode ? "Wi-Fi · \(wifi.interfaceName)" : "Wi-Fi"
        }
        if let iface = route.defaultInterface {
            return isProMode ? "Wired · \(iface)" : "Ethernet"
        }
        return wifi.powerOn ? "Not Connected" : "Wi-Fi Off"
    }

    var trustPillLabel: String {
        if trustAudit.level == .shielded, let vpn = activeVPN {
            let upper = vpn.name.uppercased()
            return upper.count > 12 ? String(upper.prefix(12)) : upper
        }
        return trustAudit.level.label
    }

    var heroSubtitle: String {
        if !isProMode {
            return HumanSummary.humanSubtitle(
                wifi: wifi,
                isWired: isWired,
                rfPhysics: rfPhysics,
                activeVPN: activeVPN
            )
        }
        var parts: [String] = []
        if wifi.isConnected {
            if wifi.band != .unknown { parts.append(wifi.band.rawValue.uppercased()) }
            if wifi.channel > 0 { parts.append("CH \(wifi.channel)") }
            if wifi.txRateMbps > 0 { parts.append("\(Int(round(wifi.txRateMbps))) MBPS") }
            if wifi.security != .unknown { parts.append(wifi.security.rawValue.uppercased()) }
        } else if let iface = route.defaultInterface {
            parts.append("ETHERNET")
            parts.append(iface.uppercased())
        } else {
            parts.append(wifi.powerOn ? "NO ACTIVE ROUTE" : "RADIO POWERED OFF")
        }
        if let vpn = activeVPN {
            parts.append(vpn.name.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    var activityReadiness: [ActivityReadinessItem] {
        HumanSummary.activityReadiness(
            wifi: wifi,
            isWired: isWired,
            hopHealth: hopHealth,
            stability: stability,
            quality: qualityResult,
            rfPhysics: rfPhysics,
            awdl: awdl
        )
    }

    var privacyActors: [PrivacyActorRow] {
        HumanSummary.privacyActors(
            wifi: wifi,
            isWired: isWired,
            dns: dns,
            vpns: vpns,
            proxy: proxy,
            exposure: exposure,
            zone: currentTrustZone,
            localBroadcastName: localBroadcastName,
            audit: trustAudit
        )
    }

    var signalInsights: [SignalInsight] {
        HumanSummary.signalInsights(
            wifi: wifi,
            rfPhysics: rfPhysics,
            channelAnalysis: channelAnalysis,
            awdl: awdl,
            xray: connectionXRay,
            topProcesses: topProcesses
        )
    }

    var studioHeadline: String {
        let sig = HumanSummary.humanSignalLabel(wifi: wifi, isWired: isWired)
        let callVerdict = activityReadiness.first?.verdict ?? "Checking"
        let shield = activeVPN.map { "Protected by \($0.name)" } ?? trustAudit.headline
        return "\(sig) connection · Video calls: \(callVerdict) · \(shield)"
    }

    var peakThroughputBytesPerSec: Double {
        let maxDown = throughputHistory.map(\.downloadBytesPerSec).max() ?? 0
        let maxUp = throughputHistory.map(\.uploadBytesPerSec).max() ?? 0
        return max(maxDown, maxUp)
    }

    private func updateLocationStatus() {
        locationServicesEnabled = wifiController.locationServicesEnabled
        locationAuthStatus = wifiController.locationAuthorizationStatus
        hasLocationAccess = wifiController.hasLocationAccess
    }

    private func emitMenuBarTick() {
        onMenuBarTick?(wifi, trustAudit, currentThroughput, menuBarMode, isWired)
    }

    private func showBanner(_ message: String) {
        bannerTask?.cancel()
        statusBanner = message
        bannerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.statusBanner = nil
        }
    }
}
