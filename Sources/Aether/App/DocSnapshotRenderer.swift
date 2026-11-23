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
        s.trustAudit = TrustAudit(level: .offline, score: 0, headline: "Not connected")
        s.currentThroughput = ThroughputSample(downloadBytesPerSec: 0, uploadBytesPerSec: 0)
        s.showSettingsWhileDisconnected = false
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

    private static func renderPopover(state: AppState) -> NSImage {
        let view = PopoverView(state: state, onOpenStudio: {}, onQuit: {})
        return renderSwiftUIView(view, fixedWidth: 396, fixedHeight: nil)
    }

    private static func renderStudio(state: AppState) -> NSImage {
        let view = AetherStudioView(state: state)
        return renderSwiftUIView(view, fixedWidth: 1000, fixedHeight: 660)
    }

    private static func renderMenuBarIcon(state: AppState) -> NSImage {
        let v = MenuBarIconView(frame: NSRect(x: 0, y: 0, width: MenuBarIconView.iconWithSpeedWidth, height: 22))
        v.appearance = NSAppearance(named: .darkAqua)
        v.update(
            wifi: state.wifi,
            audit: state.trustAudit,
            throughput: state.currentThroughput,
            mode: state.isDisconnected ? .iconOnly : .alwaysSpeed,
            isWired: state.isWired
        )
        let w = v.preferredWidth
        v.frame = NSRect(x: 0, y: 0, width: w, height: 22)
        return snapshotNSView(v, scale: 2.0)
    }

    private static func renderSwiftUIView<V: View>(_ view: V, fixedWidth: CGFloat, fixedHeight: CGFloat?) -> NSImage {
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
        let img = snapshotNSView(host, scale: 2.0)
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
                startRadius: 40,
                endCenter: CGPoint(x: W * 0.5, y: H * 0.54),
                endRadius: W * 0.62,
                options: [.drawsAfterEndLocation]
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
}
#endif
