#if DEBUG
import AetherCore
import AppKit
import SwiftUI

/// Renders high-resolution 1600x1000 documentation & website showcase plates directly from
/// Aether's live SwiftUI views using privacy-safe fixture telemetry. Compiled only in DEBUG.
@MainActor
enum DocSnapshotRenderer {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let flagIdx = args.firstIndex(of: "--render-appstore"),
           args.indices.contains(flagIdx + 1) {
            let outDir = URL(fileURLWithPath: args[flagIdx + 1], isDirectory: true)
            renderAppStorePlates(to: outDir)
            return true
        }
        guard let flagIdx = args.firstIndex(of: "--render-docs"),
              args.indices.contains(flagIdx + 1) else {
            return false
        }
        let outDir = URL(fileURLWithPath: args[flagIdx + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let state = AppState.shared
        state.isPopoverOpen = false // Static deterministic frame for crisp capture
        state.isStudioOpen = false
        state.hasLocationAccess = true
        state.hasDismissedOnboarding = true
        state.isProMode = false
        state.menuBarMode = .alwaysSpeed

        // Plate 1: Hero Menu Bar — SPEED tab + FLUX harmonic silk ribbons
        applyHomeStudioFixture(state)
        state.stageMode = .flux
        state.activeTab = .speed
        let speedShot = renderPopover(state: state)
        savePlate(
            card: speedShot,
            menuBar: renderMenuBarIcon(state: state),
            to: outDir.appendingPathComponent("hero-menubar.jpg")
        )

        // Plate 2: PRIVACY tab + ROUTE curved circuit (in-flight public Wi-Fi + VPN shield)
        applyPublicWiFiFixture(state)
        state.stageMode = .route
        state.activeTab = .shield
        let privacyShot = renderPopover(state: state)
        savePlate(
            card: privacyShot,
            menuBar: renderMenuBarIcon(state: state),
            to: outDir.appendingPathComponent("vis-privacy.jpg")
        )

        // Plate 3: WI-FI tab + SPECTRUM Gaussian RF channel overlap
        applySpectrumFixture(state)
        state.stageMode = .spectrum
        state.activeTab = .networks
        let spectrumShot = renderPopover(state: state)
        savePlate(
            card: spectrumShot,
            menuBar: renderMenuBarIcon(state: state),
            to: outDir.appendingPathComponent("vis-spectrum.jpg")
        )

        // Plate 4: Aether Studio Workstation (full 1000x660 dashboard)
        applyHomeStudioFixture(state)
        state.isScanningNetworks = false
        let studioShot = renderStudio(state: state)
        saveStudioPlate(studio: studioShot, to: outDir.appendingPathComponent("vis-studio.jpg"))

        // Plate 5: Disconnected-First Wi-Fi Picker
        applyDisconnectedFixture(state)
        state.isScanningNetworks = false
        let discShot = renderPopover(state: state)
        savePlate(
            card: discShot,
            menuBar: renderMenuBarIcon(state: state),
            to: outDir.appendingPathComponent("vis-disconnected.jpg")
        )

        print("Rendered 5 Aether plates to \(outDir.path)")
        return true
    }

    // MARK: - Privacy-Safe Realistic Fixtures

    private static func applyHomeStudioFixture(_ s: AppState) {
        let wifi = WiFiSnapshot(
            interfaceName: "en0",
            powerOn: true,
            isConnected: true,
            ssid: "Studio 5G",
            bssid: "ac:8b:a9:42:18:04",
            rssi: -46,
            noise: -91,
            txRateMbps: 866,
            channel: 149,
            band: .band5,
            channelWidthMHz: 80,
            phyGeneration: "Wi-Fi 6",
            security: .wpa3Personal,
            hardwareMAC: "b6:49:dc:03:25:60",
            isPrivateMAC: true
        )
        let route = RouteInfo(defaultInterface: "en0", gatewayIP: "192.168.1.1", localIP: "192.168.1.42", gatewayMAC: "ac:8b:a9:42:18:01")
        let dns = DNSSnapshot(servers: ["100.95.0.251"], providerLabel: "VPN Tunnel DNS", posture: .vpnTunnel, hasTunnelResolver: true, tunnelInterface: "utun6")
        let vpn = VPNService(uuid: "1", name: "WireGuard", bundleID: "com.wireguard.macos", status: "Connected")
        let exposure = LANExposureSnapshot(neighborCount: 6)

        s.wifi = wifi
        s.route = route
        s.dns = dns
        s.vpns = [vpn]
        s.proxy = ProxySnapshot()
        s.exposure = exposure
        s.captivePortal = .clear
        s.currentTrustZone = .home
        s.localBroadcastName = "Studio-Mac.local"
        s.hasGlobalIPv6 = true
        s.awdl = AWDLSnapshot(isActive: true, totalPackets: 412, packetsPerSec: 0.4)
        s.connectionXRay = ConnectionXRay(
            totalOutboundSockets: 28,
            uniqueRemoteHosts: 14,
            plaintextHTTPCount: 0,
            continuityPeerLinks: 2,
            topApps: [
                OutboundAppSummary(name: "Safari", connectionCount: 11, hasPlaintextHTTP: false),
                OutboundAppSummary(name: "Slack", connectionCount: 6, hasPlaintextHTTP: false),
                OutboundAppSummary(name: "git-remote-https", connectionCount: 4, hasPlaintextHTTP: false)
            ]
        )
        s.hopHealth = HopHealth(routerMs: 1.8, dnsMs: 9.4, internetMs: 16.2, updatedAt: Date())

        // Rich multi-hop latency history for Studio timeline
        let now = Date()
        let latPattern: [(Double, Double, Double?)] = [
            (1.9, 10.2, 16.4), (1.7, 9.8, 15.9), (2.1, 11.4, 17.8), (1.8, 9.5, 16.0),
            (2.4, 12.1, 21.3), (1.9, 9.2, 15.6), (1.6, 8.9, 15.2), (2.0, 10.5, 16.8),
            (3.1, 14.8, 28.4), (1.8, 9.4, 16.1), (1.7, 9.1, 15.7), (2.2, 10.9, 17.4),
            (1.9, 9.6, 16.5), (1.8, 9.3, 15.8), (2.5, 13.0, 22.9), (1.7, 8.8, 15.3),
            (1.9, 9.5, 16.1), (2.0, 10.1, 16.7), (1.8, 9.0, 15.5), (1.8, 9.4, 16.2),
            (2.1, 10.4, 17.1), (1.7, 9.2, 15.9), (1.9, 9.7, 16.3), (1.8, 9.4, 16.2)
        ]
        s.latencyHistory = latPattern.enumerated().map { idx, v in
            LatencySample(
                timestamp: now.addingTimeInterval(Double(idx - latPattern.count) * 5.0),
                routerMs: v.0,
                dnsMs: v.1,
                internetMs: v.2
            )
        }
        s.stability = StabilityCalculator.compute(samples: s.latencyHistory)

        // Lush harmonic throughput ribbon history (active ~42 MB/s down, ~6.8 MB/s up)
        var ring: [ThroughputSample] = []
        for i in 0..<60 {
            let t = Double(i) / 59.0
            let dl = (12_000_000 + 28_000_000 * pow(sin(t * .pi * 2.1 + 0.4), 2) + 8_500_000 * sin(t * 17.0) * 0.5)
            let ul = (2_200_000 + 5_400_000 * pow(cos(t * .pi * 1.8 - 0.3), 2) + 1_800_000 * sin(t * 13.0) * 0.4)
            ring.append(ThroughputSample(downloadBytesPerSec: max(400_000, dl), uploadBytesPerSec: max(200_000, ul)))
        }
        s.throughputHistory = ring
        s.currentThroughput = ThroughputSample(downloadBytesPerSec: 42_600_000, uploadBytesPerSec: 6_840_000)
        s.sessionDownBytes = 4_820_000_000
        s.sessionUpBytes = 890_000_000
        s.sessionPeakBytesPerSec = 58_400_000
        s.activeInterfaces = [
            ActiveInterface(bsdName: "en0", kind: .wifi, displayName: "Wi-Fi", ipAddress: "192.168.1.42", isPrimary: true),
            ActiveInterface(bsdName: "utun4", kind: .vpn, displayName: "VPN · WireGuard", ipAddress: "100.96.0.2")
        ]

        s.topProcesses = [
            ProcessBandwidth(name: "Safari", pid: 1844, downloadBytesPerSec: 28_400_000, uploadBytesPerSec: 3_100_000, appBundlePath: "/Applications/Safari.app", processCount: 4),
            ProcessBandwidth(name: "git", pid: 4102, downloadBytesPerSec: 8_200_000, uploadBytesPerSec: 2_900_000),
            ProcessBandwidth(name: "cloudd", pid: 901, downloadBytesPerSec: 4_600_000, uploadBytesPerSec: 620_000)
        ]

        s.qualityResult = NetworkQualityResult(
            downloadMbps: 618,
            uploadMbps: 412,
            responsivenessRPM: 1240,
            baseRttMs: 14.2,
            loadedRttMs: 26.8,
            endpoint: "speed.cloudflare.com"
        )

        let rawBSSIDs: [NearbyNetwork] = [
            NearbyNetwork(ssid: "Studio 5G", bssid: "ac:8b:a9:42:18:04", rssi: -46, channel: 149, channelWidthMHz: 80, band: .band5, security: .wpa3Personal, isCurrent: true),
            NearbyNetwork(ssid: "Cedar-Mesh", bssid: "b0:fc:36:11:20:09", rssi: -64, channel: 36, channelWidthMHz: 80, band: .band5, security: .wpa3Transition),
            NearbyNetwork(ssid: "Neighbor-5G", bssid: "14:cc:20:aa:bb:12", rssi: -71, channel: 157, channelWidthMHz: 40, band: .band5, security: .wpa2Personal),
            NearbyNetwork(ssid: "Loft-6E", bssid: "fc:ec:da:99:11:02", rssi: -58, channel: 69, channelWidthMHz: 160, band: .band6, security: .wpa3Personal),
            NearbyNetwork(ssid: "CafeGuest", bssid: "00:1e:13:88:22:01", rssi: -76, channel: 1, channelWidthMHz: 20, band: .band24, security: .open),
            NearbyNetwork(ssid: "Apt4B-2.4", bssid: "04:92:26:55:19:03", rssi: -68, channel: 6, channelWidthMHz: 20, band: .band24, security: .wpa2Personal),
            NearbyNetwork(ssid: "Office-IoT", bssid: "50:c7:bf:33:14:07", rssi: -74, channel: 11, channelWidthMHz: 20, band: .band24, security: .wpa2Personal)
        ]
        s.rawScanBSSIDs = rawBSSIDs
        s.nearbyNetworks = rawBSSIDs
        s.knownSSIDs = ["Studio 5G", "Cedar-Mesh", "Unitedwifi.com", "iPhone Hotspot"]
        s.channelAnalysis = ChannelAnalyzer.analyze(current: wifi, rawBSSIDs: rawBSSIDs)
        s.rfPhysics = RFPhysics.compute(wifi: wifi, overlappingAPs: s.channelAnalysis.overlappingCount)

        s.lanDevices = [
            LANDevice(ip: "192.168.1.1", mac: "ac:8b:a9:42:18:01", vendor: "Ubiquiti", hostname: "udm-pro.local", isGateway: true),
            LANDevice(ip: "192.168.1.42", mac: "b6:49:dc:03:25:60", vendor: "Apple", hostname: "Studio-Mac.local", isLocalMac: true, isPrivateMAC: true),
            LANDevice(ip: "192.168.1.18", mac: "00:11:32:9a:41:20", vendor: "Synology", hostname: "nas-studio.local"),
            LANDevice(ip: "192.168.1.24", mac: "f0:18:98:1c:02:88", vendor: "Apple", hostname: "iPad-Pro.local"),
            LANDevice(ip: "192.168.1.31", mac: "00:0e:58:61:b4:10", vendor: "Sonos", hostname: "Living-Room.local"),
            LANDevice(ip: "192.168.1.55", mac: "dc:a6:32:77:09:fe", vendor: "Raspberry Pi", hostname: "pihole.local"),
            LANDevice(ip: "192.168.1.63", mac: "2e:44:81:9c:12:04", vendor: "Private / Randomized", hostname: nil, isPrivateMAC: true)
        ]

        s.events = [
            NetworkEvent(timestamp: now.addingTimeInterval(-120), kind: .vpnChange, title: "WireGuard connected", detail: "Encrypted tunnel shielding network traffic", severity: .ok),
            NetworkEvent(timestamp: now.addingTimeInterval(-410), kind: .bandChange, title: "Upgraded to 5 GHz", detail: "2.4G → 5G (Ch 149 · 80 MHz)", severity: .ok),
            NetworkEvent(timestamp: now.addingTimeInterval(-890), kind: .roam, title: "Roamed to new AP", detail: "5G Ch 149 (-46 dBm)", severity: .info),
            NetworkEvent(timestamp: now.addingTimeInterval(-1420), kind: .latencySpike, title: "Latency spike (168 ms)", detail: "Router 2.1ms · DNS 14ms", severity: .caution)
        ]

        s.trustAudit = TrustAnalyzer.evaluate(
            wifi: wifi, route: route, dns: dns, vpns: [vpn],
            proxy: s.proxy, exposure: exposure, zone: .home,
            pinnedFingerprint: nil, localBroadcastName: s.localBroadcastName,
            connectionXRay: s.connectionXRay
        )
    }

    private static func applyPublicWiFiFixture(_ s: AppState) {
        applyHomeStudioFixture(s)
        let wifi = WiFiSnapshot(
            interfaceName: "en0",
            powerOn: true,
            isConnected: true,
            ssid: "Unitedwifi.com",
            bssid: "00:1e:13:94:22:10",
            rssi: -52,
            noise: -90,
            txRateMbps: 240,
            channel: 44,
            band: .band5,
            channelWidthMHz: 40,
            phyGeneration: "Wi-Fi 6",
            security: .open,
            hardwareMAC: "b6:49:dc:03:25:60",
            isPrivateMAC: true
        )
        let vpn = VPNService(uuid: "1", name: "Twingate", bundleID: "com.twingate.macos", status: "Connected")
        let exposure = LANExposureSnapshot(neighborCount: 33)
        s.wifi = wifi
        s.vpns = [vpn]
        s.exposure = exposure
        s.currentTrustZone = .untrusted
        s.hopHealth = HopHealth(routerMs: 4.2, dnsMs: 28.0, internetMs: 44.0, updatedAt: Date())
        s.rfPhysics = RFPhysics.compute(wifi: wifi, overlappingAPs: 2)
        s.trustAudit = TrustAnalyzer.evaluate(
            wifi: wifi, route: s.route, dns: s.dns, vpns: [vpn],
            proxy: ProxySnapshot(), exposure: exposure, zone: .untrusted,
            pinnedFingerprint: nil, localBroadcastName: "Studio-Mac.local",
            connectionXRay: s.connectionXRay
        )
    }

    private static func applySpectrumFixture(_ s: AppState) {
        applyHomeStudioFixture(s)
        let wifi = WiFiSnapshot(
            interfaceName: "en0",
            powerOn: true,
            isConnected: true,
            ssid: "Studio-Mesh",
            bssid: "ac:8b:a9:42:18:02",
            rssi: -61,
            noise: -90,
            txRateMbps: 144,
            channel: 6,
            band: .band24,
            channelWidthMHz: 20,
            phyGeneration: "Wi-Fi 5",
            security: .wpa3Personal,
            hardwareMAC: "b6:49:dc:03:25:60",
            isPrivateMAC: true
        )
        let raw: [NearbyNetwork] = [
            NearbyNetwork(ssid: "Studio-Mesh", bssid: "ac:8b:a9:42:18:02", rssi: -61, channel: 6, channelWidthMHz: 20, band: .band24, security: .wpa3Personal, isCurrent: true),
            NearbyNetwork(ssid: "Studio-Mesh", bssid: "ac:8b:a9:42:18:05", rssi: -54, channel: 149, channelWidthMHz: 80, band: .band5, security: .wpa3Personal),
            NearbyNetwork(ssid: "Neighbor-North", bssid: "14:cc:20:aa:bb:10", rssi: -66, channel: 6, channelWidthMHz: 20, band: .band24, security: .wpa2Personal),
            NearbyNetwork(ssid: "Apt3A-WiFi", bssid: "04:92:26:55:19:01", rssi: -70, channel: 5, channelWidthMHz: 20, band: .band24, security: .wpa2Personal),
            NearbyNetwork(ssid: "CafeGuest", bssid: "00:1e:13:88:22:01", rssi: -69, channel: 8, channelWidthMHz: 20, band: .band24, security: .open),
            NearbyNetwork(ssid: "Loft-5G", bssid: "fc:ec:da:99:11:02", rssi: -58, channel: 36, channelWidthMHz: 80, band: .band5, security: .wpa3Personal),
            NearbyNetwork(ssid: "Lobby-Free", bssid: "50:c7:bf:33:14:07", rssi: -74, channel: 1, channelWidthMHz: 20, band: .band24, security: .open)
        ]
        s.wifi = wifi
        s.rawScanBSSIDs = raw
        s.nearbyNetworks = [raw[0], raw[5], raw[2], raw[4], raw[3], raw[6]]
        s.channelAnalysis = ChannelAnalyzer.analyze(current: wifi, rawBSSIDs: raw)
        s.rfPhysics = RFPhysics.compute(wifi: wifi, overlappingAPs: s.channelAnalysis.overlappingCount)
        s.trustAudit = TrustAnalyzer.evaluate(
            wifi: wifi, route: s.route, dns: s.dns, vpns: s.vpns,
            proxy: ProxySnapshot(), exposure: s.exposure, zone: .home,
            pinnedFingerprint: nil, localBroadcastName: s.localBroadcastName,
            connectionXRay: s.connectionXRay
        )
    }

    private static func applyDisconnectedFixture(_ s: AppState) {
        s.wifi = WiFiSnapshot(interfaceName: "en0", powerOn: true, isConnected: false)
        s.route = RouteInfo()
        s.vpns = []
        s.trustAudit = TrustAudit(level: .offline, score: 0, headline: "Not connected")
        s.currentThroughput = ThroughputSample(downloadBytesPerSec: 0, uploadBytesPerSec: 0)
        s.activeTab = .networks
        s.knownSSIDs = ["Studio 5G", "Cedar-Mesh", "iPhone Hotspot"]
        s.nearbyNetworks = [
            NearbyNetwork(ssid: "Unitedwifi.com", bssid: "00:1e:13:94:22:10", rssi: -50, channel: 44, channelWidthMHz: 40, band: .band5, security: .open),
            NearbyNetwork(ssid: "Studio 5G", bssid: "ac:8b:a9:42:18:04", rssi: -54, channel: 149, channelWidthMHz: 80, band: .band5, security: .wpa3Personal),
            NearbyNetwork(ssid: "Loft-6E", bssid: "fc:ec:da:99:11:02", rssi: -60, channel: 69, channelWidthMHz: 160, band: .band6, security: .wpa3Personal),
            NearbyNetwork(ssid: "iPhone Hotspot", bssid: "f0:18:98:1c:02:88", rssi: -62, channel: 149, channelWidthMHz: 40, band: .band5, security: .wpa3Personal),
            NearbyNetwork(ssid: "Lounge-Guest", bssid: "00:1e:13:88:22:01", rssi: -68, channel: 36, channelWidthMHz: 40, band: .band5, security: .open),
            NearbyNetwork(ssid: "Airport-Free", bssid: "50:c7:bf:33:14:07", rssi: -74, channel: 6, channelWidthMHz: 20, band: .band24, security: .open),
            NearbyNetwork(ssid: "Cedar-Mesh", bssid: "b0:fc:36:11:20:09", rssi: -78, channel: 11, channelWidthMHz: 20, band: .band24, security: .wpa2Personal)
        ]
        s.rawScanBSSIDs = s.nearbyNetworks
    }

    // MARK: - Offscreen Retina Rendering

    private static func renderPopover(state: AppState, scale: CGFloat = 2.0) -> NSImage {
        let view = PopoverView(state: state, onOpenStudio: {}, onQuit: {})
        return renderSwiftUIView(view, fixedWidth: 396, fixedHeight: nil, scale: scale)
    }

    private static func renderStudio(state: AppState, scale: CGFloat = 2.0) -> NSImage {
        let view = AetherStudioView(state: state)
        return renderSwiftUIView(view, fixedWidth: 1000, fixedHeight: 660, scale: scale)
    }

    private static func renderMenuBarIcon(state: AppState, scale: CGFloat = 2.0) -> NSImage {
        let mode: MenuBarDisplayMode = state.isDisconnected ? .iconOnly : .autoSpeed
        let v = MenuBarIconView(frame: NSRect(x: 0, y: 0, width: MenuBarIconView.width(for: mode), height: 22))
        v.appearance = NSAppearance(named: .darkAqua)
        v.update(
            wifi: state.wifi,
            audit: state.trustAudit,
            throughput: state.currentThroughput,
            mode: mode,
            isWired: state.isWired
        )
        let w = v.preferredWidth
        v.frame = NSRect(x: 0, y: 0, width: w, height: 22)
        return snapshotNSView(v, scale: scale)
    }

    private static func renderSwiftUIView<V: View>(_ view: V, fixedWidth: CGFloat, fixedHeight: CGFloat?, scale: CGFloat = 2.0) -> NSImage {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        let h: CGFloat
        if let fixedHeight {
            h = fixedHeight
        } else {
            host.frame = NSRect(x: 0, y: 0, width: fixedWidth, height: 900)
            host.layoutSubtreeIfNeeded()
            h = ceil(host.fittingSize.height)
        }
        host.frame = NSRect(x: 0, y: 0, width: fixedWidth, height: h)
        let win = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: fixedWidth, height: h),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        AppState.shared.isScanningNetworks = false
        host.layoutSubtreeIfNeeded()
        let img = snapshotNSView(host, scale: scale)
        win.orderOut(nil)
        return img
    }

    private static func snapshotNSView(_ view: NSView, scale: CGFloat) -> NSImage {
        let bounds = view.bounds
        let pw = max(1, Int(ceil(bounds.width * scale)))
        let ph = max(1, Int(ceil(bounds.height * scale)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pw,
            pixelsHigh: ph,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: bounds.size)
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }

    /// Composes a 1600x1000 studio plate with top macOS menu bar hairline + icon + centered panel
    /// matching Satie's `hero-menubar.jpg` visual rhythm.
    private static func savePlate(card: NSImage, menuBar: NSImage, to url: URL) {
        let W: CGFloat = 1600
        let H: CGFloat = 1000
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(W),
            pixelsHigh: Int(H),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.current = nsCtx
        let ctx = nsCtx.cgContext
        ctx.interpolationQuality = .high

        // Deep obsidian studio backdrop (#0c0e12) with subtle radial center glow
        let bgColors = [
            CGColor(red: 0.068, green: 0.080, blue: 0.104, alpha: 1.0),
            CGColor(red: 0.036, green: 0.041, blue: 0.052, alpha: 1.0)
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: W * 0.5, y: H * 0.54),
                startRadius: 0,
                endCenter: CGPoint(x: W * 0.5, y: H * 0.54),
                endRadius: W * 0.62,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Top macOS Menu Bar strip (44px tall at 2x = 22pt) + 1px hairline
        let barH: CGFloat = 46
        ctx.setFillColor(CGColor(red: 0.044, green: 0.050, blue: 0.064, alpha: 0.96))
        ctx.fill(CGRect(x: 0, y: H - barH, width: W, height: barH))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        ctx.fill(CGRect(x: 0, y: H - barH, width: W, height: 1))

        // Draw live MenuBarIconView centered in top menu bar
        let iconScale: CGFloat = 1.65
        let iconW = menuBar.size.width * iconScale
        let iconH = menuBar.size.height * iconScale
        menuBar.draw(in: NSRect(x: (W - iconW) * 0.5, y: H - barH + (barH - iconH) * 0.5, width: iconW, height: iconH))

        // Scale & center the floating popover cleanly below the menu bar
        let availH = H - barH - 86
        let maxCardH = min(availH, 860)
        let cardScale = min(maxCardH / max(1, card.size.height), 1.48)
        let drawW = card.size.width * cardScale
        let drawH = card.size.height * cardScale
        let drawX = (W - drawW) * 0.5
        let drawY = (H - barH - drawH) * 0.52

        // Soft studio drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 52, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.72))
        let shadowRect = CGRect(x: drawX, y: drawY, width: drawW, height: drawH)
        let path = CGPath(roundedRect: shadowRect, cornerWidth: 15 * cardScale, cornerHeight: 15 * cardScale, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 0.03, green: 0.034, blue: 0.042, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        card.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH))

        NSGraphicsContext.restoreGraphicsState()

        if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.90]) {
            try? jpeg.write(to: url)
        }
    }

    private static func saveStudioPlate(studio: NSImage, to url: URL) {
        let W: CGFloat = 1600
        let H: CGFloat = 1000
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(W),
            pixelsHigh: Int(H),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.current = nsCtx
        let ctx = nsCtx.cgContext
        ctx.interpolationQuality = .high

        ctx.setFillColor(CGColor(red: 0.026, green: 0.030, blue: 0.038, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        let pad: CGFloat = 34
        let scale = min((W - pad * 2) / studio.size.width, (H - pad * 2) / studio.size.height)
        let drawW = studio.size.width * scale
        let drawH = studio.size.height * scale
        let rect = CGRect(x: (W - drawW) * 0.5, y: (H - drawH) * 0.5, width: drawW, height: drawH)

        ctx.saveGState()
        let clip = CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.addPath(clip)
        ctx.clip()
        studio.draw(in: rect)
        ctx.restoreGState()

        ctx.addPath(clip)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        NSGraphicsContext.restoreGraphicsState()

        if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.90]) {
            try? jpeg.write(to: url)
        }
    }

    // MARK: - S-Tier Mac App Store Editorial Screenshots (2560×1600 Opaque sRGB PNG)

    private struct AppStoreSpec: Identifiable {
        let id = UUID()
        let value: String
        let label: String
    }

    private static func renderAppStorePlates(to outDir: URL) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let state = AppState.shared
        state.isPopoverOpen = false
        state.isStudioOpen = false
        state.hasLocationAccess = true
        state.hasDismissedOnboarding = true
        state.isProMode = false
        state.menuBarMode = .autoSpeed
        state.aiDiagnosis = nil
        state.isGeneratingBrief = false

        // 01: Hero Showstopper — Instant Verdict + 4-Hop Route (DaisyDisk clarity: why is my Wi-Fi slow?)
        applyOnDeviceBriefFixture(state)
        state.aiDiagnosis = nil
        state.stageMode = .route
        state.activeTab = .speed
        saveAppStorePopoverPlate(
            eyebrow: "INSTANT WI-FI DIAGNOSIS",
            headline: "Know why your\nWi-Fi feels slow.",
            subhead: "Separates strong local Wi-Fi from slow upstream links in one glance — with a live 4-hop route and plain-English verdict.",
            accent: Color(red: 1.0, green: 0.52, blue: 0.44),
            specs: [
                AppStoreSpec(value: "4-Hop", label: "Live route map"),
                AppStoreSpec(value: "True", label: "ICMP latency"),
                AppStoreSpec(value: "0.0%", label: "Idle CPU closed")
            ],
            card: renderPopover(state: state, scale: 3.0),
            menuBar: renderMenuBarIcon(state: state, scale: 3.0),
            to: outDir.appendingPathComponent("01-instant-verdict.png")
        )

        // 02: Live Menu Bar — Speed & Flux (Healthy Home Studio 5G)
        applyHomeStudioFixture(state)
        state.aiDiagnosis = nil
        state.stageMode = .flux
        state.activeTab = .speed
        saveAppStorePopoverPlate(
            eyebrow: "LIVE MENU BAR INSTRUMENT",
            headline: "See your Wi-Fi\nin real time.",
            subhead: "Signal physics, live throughput, and bufferbloat smoothness — in a fixed-width menu bar icon that never shifts.",
            accent: Color(red: 0.48, green: 0.86, blue: 1.0),
            specs: [
                AppStoreSpec(value: "28pt", label: "Fixed menu bar"),
                AppStoreSpec(value: "618M", label: "Speed & RPM test"),
                AppStoreSpec(value: "Native", label: "Swift & AppKit")
            ],
            card: renderPopover(state: state, scale: 3.0),
            menuBar: renderMenuBarIcon(state: state, scale: 3.0),
            to: outDir.appendingPathComponent("02-speed-flux.png")
        )

        // 03: On-Device Apple Intelligence Brief (Expanded Directly Inside the Top Verdict Card)
        applyOnDeviceBriefFixture(state)
        state.stageMode = .route
        state.activeTab = .speed
        saveAppStorePopoverPlate(
            eyebrow: "ON-DEVICE APPLE INTELLIGENCE",
            headline: "Ask your Wi-Fi\nwhat to do next.",
            subhead: "On-demand local diagnosis grounded in real signal, channel overlap, and ICMP latency. Zero cloud calls.",
            accent: Color(red: 0.62, green: 0.82, blue: 1.0),
            specs: [
                AppStoreSpec(value: "100%", label: "On-device model"),
                AppStoreSpec(value: "0 bytes", label: "Sent to cloud"),
                AppStoreSpec(value: "Private", label: "Zero tracking")
            ],
            card: renderPopover(state: state, scale: 3.0),
            menuBar: renderMenuBarIcon(state: state, scale: 3.0),
            to: outDir.appendingPathComponent("03-apple-intelligence.png")
        )

        // 04: Privacy & Route Audit
        applyPublicWiFiFixture(state)
        state.aiDiagnosis = nil
        state.stageMode = .route
        state.activeTab = .shield
        saveAppStorePopoverPlate(
            eyebrow: "PRIVACY & ROUTE AUDIT",
            headline: "Know who can see\nyou on any Wi-Fi.",
            subhead: "Shows your VPN tunnel shield, evil-twin router checks, and every device sharing your local network.",
            accent: Color(red: 0.28, green: 0.90, blue: 0.64),
            specs: [
                AppStoreSpec(value: "VPN", label: "Tunnel shield"),
                AppStoreSpec(value: "ARP", label: "LAN device list"),
                AppStoreSpec(value: "Instant", label: "Evil-twin guard")
            ],
            card: renderPopover(state: state, scale: 3.0),
            menuBar: renderMenuBarIcon(state: state, scale: 3.0),
            to: outDir.appendingPathComponent("04-privacy-route.png")
        )

        // 05: 2.4 / 5 / 6 GHz RF Channel Spectrum & 1-Click 5 GHz Roaming
        applySpectrumFixture(state)
        state.aiDiagnosis = nil
        state.stageMode = .spectrum
        state.activeTab = .networks
        saveAppStorePopoverPlate(
            eyebrow: "RF CHANNEL SPECTRUM",
            headline: "Escape crowded\nairwaves in seconds.",
            subhead: "Live Gaussian overlap across 2.4, 5 & 6 GHz with automatic cleaner-channel guidance and 1-click roaming.",
            accent: Color(red: 1.0, green: 0.76, blue: 0.38),
            specs: [
                AppStoreSpec(value: "2.4·5·6", label: "GHz spectrum"),
                AppStoreSpec(value: "1-Click", label: "Switch to 5 GHz"),
                AppStoreSpec(value: "Live", label: "Overlap math")
            ],
            card: renderPopover(state: state, scale: 3.0),
            menuBar: renderMenuBarIcon(state: state, scale: 3.0),
            to: outDir.appendingPathComponent("05-rf-spectrum.png")
        )

        // 06: Full-Screen Aether Studio Workbench
        applyHomeStudioFixture(state)
        state.aiDiagnosis = nil
        state.isScanningNetworks = false
        saveAppStoreStudioPlate(
            eyebrow: "AETHER STUDIO · ⌘E",
            headline: "Your full RF & latency workbench.",
            subhead: "Channel spectrum, multi-hop jitter timeline, LAN devices, event log & on-device Q&A.",
            studio: renderStudio(state: state, scale: 3.0),
            to: outDir.appendingPathComponent("06-aether-studio.png")
        )

        print("Rendered 6 S-tier 2560x1600 App Store plates to \(outDir.path)")
    }

    private static func applyOnDeviceBriefFixture(_ s: AppState) {
        applyPublicWiFiFixture(s)
        s.hopHealth = HopHealth(routerMs: 3.2, dnsMs: 14.0, internetMs: 642.0, updatedAt: Date())
        s.stability = StabilityMetrics(avgInternetMs: 642.0, jitterMs: 18.4, packetLossPercent: 1.2, callGrade: .choppy, verdict: "High upstream latency (642 ms)")
        s.qualityResult = nil
        s.activeInterfaces = [
            ActiveInterface(bsdName: "en0", kind: .wifi, displayName: "Wi-Fi", ipAddress: "172.19.249.21"),
            ActiveInterface(bsdName: "utun6", kind: .vpn, displayName: "VPN · Twingate", ipAddress: "100.96.0.2")
        ]
        s.currentThroughput = ThroughputSample(downloadBytesPerSec: 410_000, uploadBytesPerSec: 185_000)
        s.sessionDownBytes = 411_800_000
        s.sessionUpBytes = 148_200_000
        s.sessionPeakBytesPerSec = 1_320_000
        s.aiDiagnosis = NetworkDiagnosis(
            summary: "Your cabin Wi-Fi signal is strong (38 dB SNR on 5 GHz), so the 642 ms lag is upstream over the satellite link — not your Mac.",
            nextStep: "Twingate VPN is already encrypting your traffic; skip live video calls until you land and use async messaging instead.",
            usedOnDeviceModel: true
        )
    }

    private static func saveAppStorePopoverPlate(
        eyebrow: String,
        headline: String,
        subhead: String,
        accent: Color,
        specs: [AppStoreSpec],
        card: NSImage,
        menuBar: NSImage,
        to url: URL
    ) {
        let plate = AppStorePopoverPlateView(
            eyebrow: eyebrow,
            headline: headline,
            subhead: subhead,
            accent: accent,
            specs: specs,
            card: card,
            menuBar: menuBar
        )
        let img = renderSwiftUIView(plate, fixedWidth: 1280, fixedHeight: 800, scale: 2.0)
        writeOpaquePNG(img, width: 2560, height: 1600, to: url)
    }

    private static func saveAppStoreStudioPlate(
        eyebrow: String,
        headline: String,
        subhead: String,
        studio: NSImage,
        to url: URL
    ) {
        let plate = AppStoreStudioPlateView(
            eyebrow: eyebrow,
            headline: headline,
            subhead: subhead,
            studio: studio
        )
        let img = renderSwiftUIView(plate, fixedWidth: 1280, fixedHeight: 800, scale: 2.0)
        writeOpaquePNG(img, width: 2560, height: 1600, to: url)
    }

    /// Writes a strict opaque 24-bit sRGB PNG (no alpha channel) so App Store Connect accepts it cleanly.
    private static func writeOpaquePNG(_ image: NSImage, width: Int, height: Int, to url: URL) {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return }

        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(red: 0.028, green: 0.034, blue: 0.046, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsCtx
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private struct AppStorePopoverPlateView: View {
        let eyebrow: String
        let headline: String
        let subhead: String
        let accent: Color
        let specs: [AppStoreSpec]
        let card: NSImage
        let menuBar: NSImage

        var body: some View {
            ZStack {
                // Deep obsidian-sapphire studio backdrop
                LinearGradient(
                    colors: [
                        Color(red: 0.032, green: 0.040, blue: 0.058),
                        Color(red: 0.020, green: 0.024, blue: 0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Atmospheric semantic glow behind the live popover
                RadialGradient(
                    colors: [accent.opacity(0.20), accent.opacity(0.05), Color.clear],
                    center: UnitPoint(x: 0.72, y: 0.52),
                    startRadius: 20,
                    endRadius: 480
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [Color(red: 0.35, green: 0.55, blue: 0.90).opacity(0.10), Color.clear],
                    center: UnitPoint(x: 0.14, y: 0.24),
                    startRadius: 10,
                    endRadius: 380
                )
                .blendMode(.screen)

                // Top macOS menu bar glass strip with Aether's live menu bar icon anchored above the popover
                VStack(spacing: 0) {
                    ZStack {
                        Color(red: 0.042, green: 0.049, blue: 0.066).opacity(0.92)
                        HStack {
                            HStack(spacing: 14) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.75))
                                Text("Aether")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.78))
                                Text("Window")
                                    .font(.system(size: 11.5, weight: .regular))
                                    .foregroundColor(.white.opacity(0.42))
                                Text("Help")
                                    .font(.system(size: 11.5, weight: .regular))
                                    .foregroundColor(.white.opacity(0.42))
                            }
                            .padding(.leading, 22)

                            Spacer()

                            // Live MenuBarIconView anchored directly above the popover center
                            HStack(spacing: 14) {
                                Image(nsImage: menuBar)
                                    .interpolation(.high)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 22)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.11))
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.55))
                                Image(systemName: "switch.2")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.55))
                                Text("Mon 9:41 AM")
                                    .font(.system(size: 11.0, weight: .medium))
                                    .foregroundColor(.white.opacity(0.72))
                            }
                            .padding(.trailing, 130)
                        }
                    }
                    .frame(height: 30)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.75)
                    }

                    Spacer()
                }

                // Split-Editorial Hero Layout
                HStack(spacing: 48) {
                    // Left Editorial Column
                    VStack(alignment: .leading, spacing: 22) {
                        // Eyebrow pill
                        HStack(spacing: 7) {
                            Circle()
                                .fill(accent)
                                .frame(width: 7, height: 7)
                                .shadow(color: accent.opacity(0.8), radius: 5)
                            Text(eyebrow)
                                .font(.system(size: 11.0, weight: .semibold, design: .monospaced))
                                .tracking(1.3)
                                .foregroundColor(.white.opacity(0.86))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 0.9))

                        Text(headline)
                            .font(.system(size: 52, weight: .bold))
                            .tracking(-1.4)
                            .lineSpacing(2)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subhead)
                            .font(.system(size: 18.5, weight: .regular))
                            .lineSpacing(5)
                            .foregroundColor(.white.opacity(0.66))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 490, alignment: .leading)

                        Spacer().frame(height: 8)

                        // Micro-spec strip
                        VStack(alignment: .leading, spacing: 14) {
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 1)
                                .frame(maxWidth: 440)

                            HStack(spacing: 30) {
                                ForEach(specs) { spec in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(spec.value)
                                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.95))
                                        Text(spec.label)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(.white.opacity(0.46))
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 530, alignment: .leading)
                    .padding(.leading, 84)
                    .padding(.top, 24)

                    Spacer(minLength: 10)

                    // Right Live MAS Popover Column
                    let maxH: CGFloat = 716
                    let aspect = card.size.width / max(1, card.size.height)
                    let targetH = min(maxH, card.size.height * 1.12)
                    let targetW = min(475, targetH * aspect)
                    let finalH = targetW / aspect

                    Image(nsImage: card)
                        .interpolation(.high)
                        .resizable()
                        .frame(width: targetW, height: finalH)
                        .shadow(color: Color.black.opacity(0.75), radius: 36, x: 0, y: 20)
                        .padding(.trailing, 84)
                        .padding(.top, 24)
                }
            }
            .frame(width: 1280, height: 800)
        }
    }

    private struct AppStoreStudioPlateView: View {
        let eyebrow: String
        let headline: String
        let subhead: String
        let studio: NSImage

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.032, green: 0.040, blue: 0.058),
                        Color(red: 0.020, green: 0.024, blue: 0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Color(red: 0.30, green: 0.86, blue: 0.68).opacity(0.16), Color.clear],
                    center: UnitPoint(x: 0.5, y: 0.62),
                    startRadius: 40,
                    endRadius: 560
                )
                .blendMode(.screen)

                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6.5) {
                            Circle()
                                .fill(Color(red: 0.30, green: 0.90, blue: 0.66))
                                .frame(width: 6, height: 6)
                            Text(eyebrow)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .tracking(1.3)
                                .foregroundColor(.white.opacity(0.84))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 0.85))

                        Text(headline)
                            .font(.system(size: 36, weight: .bold))
                            .tracking(-1.0)
                            .foregroundColor(.white)

                        Text(subhead)
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.64))
                    }
                    .padding(.top, 24)

                    let studioAspect = studio.size.width / max(1, studio.size.height)
                    let maxStudioH: CGFloat = 626
                    let maxStudioW: CGFloat = 1120
                    let fitH = min(maxStudioH, maxStudioW / studioAspect)
                    let fitW = fitH * studioAspect

                    Image(nsImage: studio)
                        .interpolation(.high)
                        .resizable()
                        .frame(width: fitW, height: fitH)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.08), Color.white.opacity(0.14)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.0
                                )
                        )
                        .shadow(color: Color.black.opacity(0.78), radius: 40, x: 0, y: 22)
                        .padding(.bottom, 20)
                }
            }
            .frame(width: 1280, height: 800)
        }
    }
}
#endif
