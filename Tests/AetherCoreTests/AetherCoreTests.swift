import AetherCore
import CoreGraphics
import Foundation
import XCTest

final class AetherCoreTests: XCTestCase {

    // MARK: - MAC Privacy (IEEE 802 Locally-Administered Bit)

    func testMACPrivacyDetection() {
        // 0x70 = 0111_0000 -> bit 0x02 is 0 -> Fixed hardware MAC
        XCTAssertEqual(SystemParsers.isLocallyAdministeredMAC("70:8c:f2:c3:b3:7a"), false)
        // 0x2a = 0010_1010 -> bit 0x02 is 1 -> Private / randomized MAC
        XCTAssertEqual(SystemParsers.isLocallyAdministeredMAC("2a:cc:9c:44:0b:a7"), true)
        XCTAssertEqual(SystemParsers.isLocallyAdministeredMAC("fe:12:34:56:78:9a"), true)
        XCTAssertNil(SystemParsers.isLocallyAdministeredMAC(nil))
        XCTAssertNil(SystemParsers.isLocallyAdministeredMAC("invalid"))
    }

    func testNormalizeMAC() {
        XCTAssertEqual(SystemParsers.normalizeMAC("2a:cc:9c:44:b:a7"), "2a:cc:9c:44:0b:a7")
        XCTAssertEqual(SystemParsers.normalizeMAC("AA:B:C:D:E:F"), "aa:0b:0c:0d:0e:0f")
    }

    // MARK: - `route -n get default`

    func testParseDefaultRoute() {
        let fixture = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.17.248
          interface: en0
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
        """
        let parsed = SystemParsers.parseDefaultRoute(fixture)
        XCTAssertEqual(parsed.interface, "en0")
        XCTAssertEqual(parsed.gateway, "192.168.17.248")
    }

    // MARK: - `scutil --dns`

    func testParseScutilDNSWithVPNTunnel() {
        let fixture = """
        DNS configuration

        resolver #1
          nameserver[0] : 100.95.0.251
          nameserver[1] : 100.95.0.252
          if_index : 24 (utun6)
          flags    : Supplemental, Request A records
          reach    : 0x00000003 (Reachable,Transient Connection)

        resolver #2
          nameserver[0] : 1.0.0.1
          nameserver[1] : 1.1.1.1
          flags    : Request A records

        resolver #3
          domain   : local
          options  : mdns
        """
        let snap = SystemParsers.parseScutilDNS(fixture)
        XCTAssertEqual(snap.posture, .vpnTunnel)
        XCTAssertTrue(snap.hasTunnelResolver)
        XCTAssertEqual(snap.tunnelInterface, "utun6")
        XCTAssertTrue(snap.servers.contains("100.95.0.251"))
        XCTAssertTrue(snap.servers.contains("1.1.1.1"))
    }

    func testParseScutilDNSPlainRouter() {
        let fixture = """
        DNS configuration

        resolver #1
          nameserver[0] : 192.168.1.1
          flags    : Request A records
        """
        let snap = SystemParsers.parseScutilDNS(fixture)
        XCTAssertEqual(snap.posture, .localRouter)
        XCTAssertFalse(snap.hasTunnelResolver)
        XCTAssertEqual(snap.servers, ["192.168.1.1"])
    }

    // MARK: - `scutil --nc list`

    func testParseScutilNC() {
        let fixture = """
        Available network connection services in the current set (*=enabled):
        * (Connected)      B9812112-0C88-407C-BECD-EC3970288823 VPN (com.twingate.macos) "Twingate"                       [VPN:com.twingate.macos]
        * (Disconnected)   11111111-2222-3333-4444-555555555555 VPN (com.wireguard.macos) "Home WG" [VPN:com.wireguard.macos]
        """
        let vpns = SystemParsers.parseScutilNC(fixture)
        XCTAssertEqual(vpns.count, 2)
        XCTAssertEqual(vpns[0].name, "Twingate")
        XCTAssertTrue(vpns[0].isConnected)
        XCTAssertEqual(vpns[1].name, "Home WG")
        XCTAssertFalse(vpns[1].isConnected)
    }

    // MARK: - `scutil --proxy`

    func testParseScutilProxy() {
        let direct = """
        <dictionary> {
          ExceptionsList : <array> {
            0 : *.local
          }
          FTPPassive : 1
        }
        """
        XCTAssertFalse(SystemParsers.parseScutilProxy(direct).isAnyProxyActive)

        let proxied = """
        <dictionary> {
          HTTPEnable : 1
          HTTPSEnable : 1
          ProxyAutoConfigEnable : 0
        }
        """
        let p = SystemParsers.parseScutilProxy(proxied)
        XCTAssertTrue(p.isAnyProxyActive)
        XCTAssertEqual(p.summary, "HTTP · HTTPS Proxy")
    }

    // MARK: - `arp -an`

    func testParseArpTable() {
        let fixture = """
        ? (192.168.17.127) at 16:44:2a:bc:95:aa on en0 ifscope [ethernet]
        ? (192.168.17.140) at 6e:f6:ee:22:a9:6f on en0 ifscope [ethernet]
        ? (192.168.17.248) at 2a:cc:9c:44:b:a7 on en0 ifscope [ethernet]
        ? (192.168.17.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
        ? (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
        """
        let parsed = SystemParsers.parseArpTable(fixture, interfaceName: "en0", gatewayIP: "192.168.17.248")
        XCTAssertEqual(parsed.gatewayMAC, "2a:cc:9c:44:0b:a7")
        XCTAssertEqual(parsed.neighborCount, 3)
    }

    // MARK: - `lsof -nP -iTCP -sTCP:LISTEN`

    func testParseListeningPorts() {
        let fixture = """
        COMMAND     PID      USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        rapportd    677 graemeboy   13u  IPv4 0x4fcece00366aa8c7      0t0  TCP *:49797 (LISTEN)
        ControlCe   831 graemeboy    9u  IPv4 0x74ae2154bccdcf83      0t0  TCP *:7000 (LISTEN)
        ControlCe   831 graemeboy   10u  IPv6 0xe9e71c929fd07f40      0t0  TCP *:7000 (LISTEN)
        Python     2912 graemeboy    3u  IPv4 0x9cede86b716e1e22      0t0  TCP 127.0.0.1:8420 (LISTEN)
        node       4120 graemeboy   11u  IPv4 0x1111111111111111      0t0  TCP *:3000 (LISTEN)
        node       4120 graemeboy   12u  IPv6 0x2222222222222222      0t0  TCP *:3000 (LISTEN)
        """
        let parsed = SystemParsers.parseListeningPorts(fixture)
        // Loopback Python:8420 excluded; dual-stack node:3000 deduplicated
        XCTAssertEqual(parsed.userPorts.count, 1)
        XCTAssertEqual(parsed.userPorts.first?.process, "node")
        XCTAssertEqual(parsed.userPorts.first?.port, 3000)
        // rapportd + deduplicated ControlCe:7000
        XCTAssertEqual(parsed.systemPorts.count, 2)
    }

    // MARK: - `nettop` Diff

    func testDiffNettop() {
        let t0 = SystemParsers.parseNettopSnapshot("""
        ,bytes_in,bytes_out,
        Chrome.100,10000,2000,
        Dropbox.200,5000,50000,
        """)
        let t1 = SystemParsers.parseNettopSnapshot("""
        ,bytes_in,bytes_out,
        Chrome.100,210000,12000,
        Dropbox.200,5000,550000,
        """)
        let top = SystemParsers.diffNettop(previous: t0, current: t1, elapsedSeconds: 2.0, limit: 4)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].name, "Dropbox")
        XCTAssertEqual(top[0].uploadBytesPerSec, 250_000, accuracy: 1.0)
        XCTAssertEqual(top[1].name, "Chrome")
        XCTAssertEqual(top[1].downloadBytesPerSec, 100_000, accuracy: 1.0)
    }

    // MARK: - `networkQuality -c` JSON

    func testParseNetworkQualityJSON() {
        let json = """
        {
          "base_rtt": 16.8,
          "dl_throughput": 17475384,
          "ul_throughput": 70149952,
          "responsiveness": 232.12,
          "lud_self_h2_req_resp": [120, 340, 500],
          "test_endpoint": "twtpe2-edge-fx-003.aaplimg.com"
        }
        """.data(using: .utf8)!

        let res = SystemParsers.parseNetworkQualityJSON(json)
        XCTAssertNotNil(res)
        XCTAssertEqual(res!.downloadMbps, 17.475, accuracy: 0.01)
        XCTAssertEqual(res!.uploadMbps, 70.15, accuracy: 0.01)
        XCTAssertEqual(res!.responsivenessRPM, 232)
        XCTAssertEqual(res!.responsivenessRating, "LOW")
        XCTAssertEqual(res!.loadedRttMs, 340)
    }

    // MARK: - TrustAnalyzer (Evil Twin, ARP Anomaly, Public Wi-Fi vs Shielded)

    func testTrustAnalyzerFlagsGatewayMACChangeAndDowngrade() {
        let wifi = WiFiSnapshot(
            powerOn: true,
            isConnected: true,
            ssid: "StudioNet",
            bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -52,
            noise: -90,
            txRateMbps: 600,
            channel: 149,
            band: .band5,
            channelWidthMHz: 80,
            phyGeneration: "Wi-Fi 6",
            security: .wpa2Personal,
            hardwareMAC: "70:8c:f2:c3:b3:7a",
            isPrivateMAC: false
        )
        let route = RouteInfo(defaultInterface: "en0", gatewayIP: "192.168.1.1", localIP: "192.168.1.50", gatewayMAC: "de:ad:be:ef:00:01")
        let pinned = NetworkFingerprint(
            ssid: "StudioNet",
            knownBSSIDs: ["aa:bb:cc:dd:ee:ff"],
            gatewayMAC: "11:22:33:44:55:66",
            strongestSecurityRank: WiFiSecurityKind.wpa3Personal.strengthRank
        )

        let audit = TrustAnalyzer.evaluate(
            wifi: wifi,
            route: route,
            dns: DNSSnapshot(servers: ["1.1.1.1"], providerLabel: "Cloudflare", posture: .trustedProvider),
            vpns: [],
            proxy: ProxySnapshot(),
            exposure: LANExposureSnapshot(neighborCount: 4),
            zone: .home,
            pinnedFingerprint: pinned
        )

        XCTAssertEqual(audit.level, .alert)
        XCTAssertTrue(audit.hasGatewayAnomaly)
        XCTAssertTrue(audit.hasSecurityDowngrade)
    }

    func testTrustAnalyzerShieldedWithVPN() {
        let wifi = WiFiSnapshot(
            powerOn: true,
            isConnected: true,
            ssid: "CafeWiFi",
            rssi: -58,
            noise: -88,
            txRateMbps: 300,
            channel: 36,
            band: .band5,
            security: .wpa3Personal,
            hardwareMAC: "2a:cc:9c:44:0b:a7",
            isPrivateMAC: true
        )
        let vpn = VPNService(uuid: "1", name: "Twingate", bundleID: "com.twingate.macos", status: "Connected")
        let audit = TrustAnalyzer.evaluate(
            wifi: wifi,
            route: RouteInfo(defaultInterface: "en0", gatewayIP: "10.0.0.1", localIP: "10.0.0.5", gatewayMAC: "aa:bb:cc:dd:ee:01"),
            dns: DNSSnapshot(servers: ["100.95.0.251"], providerLabel: "VPN Tunnel DNS", posture: .vpnTunnel, hasTunnelResolver: true, tunnelInterface: "utun6"),
            vpns: [vpn],
            proxy: ProxySnapshot(),
            exposure: LANExposureSnapshot(neighborCount: 12),
            zone: .untrusted,
            pinnedFingerprint: nil
        )
        XCTAssertEqual(audit.level, .shielded)
        XCTAssertEqual(audit.score, 100)
    }

    // MARK: - MenuBarPositioner Notch Safety

    func testMenuBarPositionerAvoidsNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let auxLeft = CGRect(x: 0, y: 944, width: 650, height: 38)
        let auxRight = CGRect(x: 862, y: 944, width: 650, height: 38)

        // Button behind camera notch
        let occludedBtn = CGRect(x: 740, y: 950, width: 26, height: 22)
        let placement = MenuBarPositioner.computePlacement(
            buttonScreenRect: occludedBtn,
            screenFrame: screen,
            visibleFrame: visible,
            auxLeft: auxLeft,
            auxRight: auxRight,
            panelSize: CGSize(width: 396, height: 500)
        )
        XCTAssertTrue(placement.statusItemOccludedByNotch)
        XCTAssertLessThanOrEqual(placement.origin.y + 500, visible.maxY)
    }

    // MARK: - Formatting

    func testByteRateFormatter() {
        XCTAssertEqual(ByteRateFormatter.compact(512), "512B")
        XCTAssertEqual(ByteRateFormatter.compact(4_500), "4.4K")
        XCTAssertEqual(ByteRateFormatter.compact(4_400_000), "4.2M")
        XCTAssertEqual(ByteRateFormatter.ms(nil), "—")
        XCTAssertEqual(ByteRateFormatter.ms(2.34), "2.3ms")
        XCTAssertEqual(ByteRateFormatter.ms(18.6), "19ms")
    }

    // MARK: - Channel Analyzer & Sticky-AP Roam Detector (WiFi Explorer Pro)

    func testChannelAnalyzerDetectsOverlapAndRecommendsCleanerChannel() {
        let current = WiFiSnapshot(
            powerOn: true,
            isConnected: true,
            ssid: "Studio",
            bssid: "aa:bb:cc:00:00:01",
            rssi: -52,
            noise: -86,
            txRateMbps: 144,
            channel: 10,
            band: .band24,
            channelWidthMHz: 20,
            security: .wpa2Personal
        )
        let peers: [NearbyNetwork] = [
            NearbyNetwork(ssid: "Studio", bssid: "aa:bb:cc:00:00:01", rssi: -52, channel: 10, channelWidthMHz: 20, band: .band24, security: .wpa2Personal, isCurrent: true),
            NearbyNetwork(ssid: "NeighborA", bssid: "11:22:33:00:00:01", rssi: -55, channel: 11, channelWidthMHz: 20, band: .band24, security: .wpa2Personal),
            NearbyNetwork(ssid: "NeighborB", bssid: "11:22:33:00:00:02", rssi: -60, channel: 9, channelWidthMHz: 20, band: .band24, security: .wpa2Personal),
            NearbyNetwork(ssid: "NeighborC", bssid: "11:22:33:00:00:03", rssi: -62, channel: 6, channelWidthMHz: 20, band: .band24, security: .wpa2Personal),
            // Same SSID broadcasting stronger 5 GHz AP -> should trigger sticky-AP roam nudge!
            NearbyNetwork(ssid: "Studio", bssid: "aa:bb:cc:00:00:05", rssi: -58, channel: 149, channelWidthMHz: 80, band: .band5, security: .wpa3Personal)
        ]

        let analysis = ChannelAnalyzer.analyze(current: current, rawBSSIDs: peers)
        XCTAssertEqual(analysis.overlappingCount, 3)
        XCTAssertEqual(analysis.recommendedChannel, 1)
        XCTAssertNotNil(analysis.roamingNudge)
        XCTAssertEqual(analysis.roamingNudge?.targetBand, .band5)
        XCTAssertEqual(analysis.roamingNudge?.targetChannel, 149)
    }

    // MARK: - OUI Vendor Lookup & LAN Device Discovery (LanScan / Fing)

    func testOUIVendorLookup() {
        XCTAssertEqual(OUIVendorLookup.vendor(for: "70:8c:f2:c3:b3:7a"), "Apple")
        XCTAssertEqual(OUIVendorLookup.vendor(for: "78:8a:20:11:22:33"), "Ubiquiti")
        XCTAssertEqual(OUIVendorLookup.vendor(for: "00:11:32:aa:bb:cc"), "Synology")
        XCTAssertEqual(OUIVendorLookup.vendor(for: "2a:cc:9c:44:0b:a7"), "Private / Randomized")
    }

    // MARK: - Stability, Jitter & Packet Loss (PingPlotter / PeakHour)

    func testStabilityCalculatorSolidVsChoppy() {
        let solidSamples = [18.0, 19.2, 18.5, 20.1, 19.0].map {
            LatencySample(routerMs: 2.0, dnsMs: 10.0, internetMs: $0)
        }
        let solid = StabilityCalculator.compute(samples: solidSamples)
        XCTAssertEqual(solid.callGrade, .solid)
        XCTAssertEqual(solid.packetLossPercent, 0.0, accuracy: 0.01)
        XCTAssertLessThan(solid.jitterMs, 2.0)

        let choppySamples = [
            LatencySample(routerMs: 2.0, dnsMs: 12.0, internetMs: 22.0),
            LatencySample(routerMs: 2.0, dnsMs: 12.0, internetMs: nil), // drop
            LatencySample(routerMs: 2.0, dnsMs: 12.0, internetMs: 145.0),
            LatencySample(routerMs: 2.0, dnsMs: 12.0, internetMs: 30.0)
        ]
        let choppy = StabilityCalculator.compute(samples: choppySamples)
        XCTAssertEqual(choppy.callGrade, .choppy)
        XCTAssertEqual(choppy.packetLossPercent, 25.0, accuracy: 0.1)
        XCTAssertGreaterThan(choppy.jitterMs, 40.0)

        // Single cold-start spike followed by steady low latency must NOT falsely trigger choppy
        let coldStartThenSteady = [
            LatencySample(routerMs: 2.0, dnsMs: 12.0, internetMs: 140.0),
            LatencySample(routerMs: 2.0, dnsMs: 10.0, internetMs: 19.0),
            LatencySample(routerMs: 2.0, dnsMs: 10.0, internetMs: 18.0),
            LatencySample(routerMs: 2.0, dnsMs: 10.0, internetMs: 20.0),
            LatencySample(routerMs: 2.0, dnsMs: 10.0, internetMs: 19.0)
        ]
        let steady = StabilityCalculator.compute(samples: coldStartThenSteady)
        XCTAssertEqual(steady.callGrade, .solid)
    }

    // MARK: - Wi-Fi Share QR Payload Escaping

    func testWiFiQRPayloadEscaping() {
        let wpa = WiFiQRPayload.make(ssid: "Cafe;Guest:5G", password: "p@ss\\word,1", security: .wpa2Personal)
        XCTAssertEqual(wpa, #"WIFI:T:WPA;S:Cafe\;Guest\:5G;P:p@ss\\word\,1;;"#)

        let open = WiFiQRPayload.make(ssid: "AirportFree", password: nil, security: .open)
        XCTAssertEqual(open, "WIFI:T:nopass;S:AirportFree;;")
    }

    // MARK: - RF Physics & Live Outbound Connection X-Ray

    func testRFPhysicsCalculations() {
        XCTAssertEqual(RFPhysics.centerFrequencyMHz(band: .band24, channel: 10), 2457)
        XCTAssertEqual(RFPhysics.centerFrequencyMHz(band: .band5, channel: 149), 5745)
        XCTAssertEqual(RFPhysics.formatSignalPower(rssiDbm: -44), "39.8 nW")
        XCTAssertEqual(RFPhysics.formatSNRMultiplier(snrDb: 38), "6.3K× noise")

        let wifi = WiFiSnapshot(
            powerOn: true,
            isConnected: true,
            ssid: "Studio",
            rssi: -44,
            noise: -82,
            txRateMbps: 144,
            channel: 10,
            band: .band24,
            channelWidthMHz: 20
        )
        let phys = RFPhysics.compute(wifi: wifi, overlappingAPs: 2)
        XCTAssertEqual(phys.centerFreqMHz, 2457)
        XCTAssertTrue(phys.realMaxTcpMbps > 60 && phys.realMaxTcpMbps < 90)
        XCTAssertTrue(phys.estimatedRangeLabel.contains("Same room"))
    }

    func testParseEstablishedConnectionsXRay() {
        let fixture = """
        COMMAND     PID      USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        rapportd    677 graemeboy   19u  IPv6 0x1111      0t0  TCP [fe80:e::1]:49797->[fe80:e::2]:61750 (ESTABLISHED)
        OrbStack   4817 graemeboy  140u  IPv4 0x2222      0t0  TCP 127.0.0.1:50766->127.0.0.1:50775 (ESTABLISHED)
        Google    25295 graemeboy   21u  IPv4 0x3333      0t0  TCP 192.168.17.99:56426->184.25.121.46:443 (ESTABLISHED)
        Google    25295 graemeboy   22u  IPv4 0x4444      0t0  TCP 192.168.17.99:56427->93.184.216.34:80 (ESTABLISHED)
        Ando\\x20H 27858 graemeboy   24u  IPv4 0x5555      0t0  TCP 192.168.17.99:58373->172.67.191.41:443 (ESTABLISHED)
        """
        let xray = SystemParsers.parseEstablishedConnections(fixture) { _, cmd in
            ResolvedApp(groupKey: "proc:\(cmd.lowercased())", displayName: cmd, appBundlePath: nil)
        }
        XCTAssertEqual(xray.continuityPeerLinks, 1)
        XCTAssertEqual(xray.totalOutboundSockets, 3)
        XCTAssertEqual(xray.plaintextHTTPCount, 1)
        XCTAssertEqual(xray.topApps.first?.name, "Google")
        XCTAssertEqual(xray.topApps.first?.hasPlaintextHTTP, true)
    }

    // MARK: - Human-First Relatable Summary Engine

    func testHumanSummaryActivityReadinessAndPrivacyActors() {
        let wifi = WiFiSnapshot(
            powerOn: true,
            isConnected: true,
            ssid: "Studio",
            rssi: -44,
            noise: -82,
            txRateMbps: 144,
            channel: 10,
            band: .band24,
            channelWidthMHz: 20,
            security: .wpa2Personal,
            hardwareMAC: "b6:49:dc:03:25:60",
            isPrivateMAC: true
        )
        let phys = RFPhysics.compute(wifi: wifi, overlappingAPs: 2)
        let stability = StabilityMetrics(avgInternetMs: 18, jitterMs: 1.5, packetLossPercent: 0, callGrade: .solid, verdict: "Solid")
        let readiness = HumanSummary.activityReadiness(
            wifi: wifi,
            isWired: false,
            hopHealth: HopHealth(routerMs: 2, dnsMs: 11, internetMs: 18),
            stability: stability,
            quality: nil,
            rfPhysics: phys,
            awdl: AWDLSnapshot()
        )
        XCTAssertEqual(readiness.count, 3)
        XCTAssertEqual(readiness[0].verdict, "Smooth")
        XCTAssertEqual(readiness[1].verdict, "Ready")
        XCTAssertEqual(readiness[2].verdict, "Snappy")

        let vpn = VPNService(uuid: "1", name: "Twingate", bundleID: "com.twingate.macos", status: "Connected")
        let actors = HumanSummary.privacyActors(
            wifi: wifi,
            isWired: false,
            dns: DNSSnapshot(servers: ["100.95.0.251"], providerLabel: "VPN DNS", posture: .vpnTunnel, hasTunnelResolver: true),
            vpns: [vpn],
            proxy: ProxySnapshot(),
            exposure: LANExposureSnapshot(neighborCount: 3),
            zone: .home,
            localBroadcastName: "Graeme-Mac.local",
            audit: TrustAudit(level: .shielded, score: 100, headline: "Shielded")
        )
        XCTAssertEqual(actors.count, 3)
        XCTAssertEqual(actors[0].verdict, "Blocked")
        XCTAssertEqual(actors[1].verdict, "Hidden")
        XCTAssertEqual(actors[2].verdict, "No apps exposed")

        XCTAssertEqual(HumanSummary.friendlyProcessName("cloudd"), "iCloud Drive")
        XCTAssertEqual(HumanSummary.friendlyProcessName("Google"), "Chrome")
    }

    // MARK: - 32-Bit Counter Wrap & Reset Safety

    func testSafe32BitCounterDelta() {
        XCTAssertEqual(InterfaceCounters.safe32BitCounterDelta(previous: 1000, current: 2500), 1500)
        // Rollover across UInt32.max (4_294_967_295)
        let nearMax = UInt64(UInt32.max) - 500
        XCTAssertEqual(InterfaceCounters.safe32BitCounterDelta(previous: nearMax, current: 1000), 1501)
        // Interface reset mid-range returns 0 instead of underflowing
        XCTAssertEqual(InterfaceCounters.safe32BitCounterDelta(previous: 50_000_000, current: 10_000), 0)
    }

    // MARK: - Native SystemConfiguration & ICMP Checksum (Zero-Subprocess / MAS Sandbox)

    func testNativeICMPChecksumAndParsers() {
        // RFC 1071 verification: checksum of packet with checksum embedded must fold to 0
        var pkt: [UInt8] = [8, 0, 0, 0, 0x12, 0x34, 0, 1]
        let cksum = NativeNetworkTelemetry.internetChecksum(pkt)
        pkt[2] = UInt8(cksum >> 8)
        pkt[3] = UInt8(cksum & 0xFF)
        XCTAssertEqual(NativeNetworkTelemetry.internetChecksum(pkt), 0)

        let dns = NativeNetworkTelemetry.classifyDNS(
            allServers: ["100.95.0.251", "192.168.17.248"],
            tunnelServers: ["100.95.0.251"],
            tunnelIface: "utun6"
        )
        XCTAssertEqual(dns.posture, .vpnTunnel)
        XCTAssertTrue(dns.hasTunnelResolver)

        let proxy = NativeNetworkTelemetry.parseProxyDictionary(["HTTPEnable": 1, "SOCKSEnable": 1])
        XCTAssertTrue(proxy.isAnyProxyActive)
        XCTAssertEqual(proxy.summary, "HTTP · SOCKS Proxy")

        // Smoke-verify live kernel sysctl ARP reader runs cleanly without crashing or spawning subprocesses
        let arp = NativeNetworkTelemetry.readArpDevices(interfaceName: "en0", gatewayIP: nil, localIP: "127.0.0.1", localMAC: "00:11:22:33:44:55")
        XCTAssertGreaterThanOrEqual(arp.devices.count, 1)
    }

    func testTrustStorePreferencesPersistence() {
        let suiteName = "aether.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TrustStore(defaults: defaults)
        XCTAssertFalse(store.isProMode)
        XCTAssertFalse(store.hasDismissedOnboarding)
        store.isProMode = true
        store.hasDismissedOnboarding = true
        XCTAssertTrue(store.isProMode)
        XCTAssertTrue(store.hasDismissedOnboarding)
    }

    func testSmartDefaultTrustZoneHeuristic() {
        let suiteName = "aether.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TrustStore(defaults: defaults)
        let openPlaneWiFi = WiFiSnapshot(powerOn: true, isConnected: true, ssid: "Unitedwifi.com", security: .open)
        let crowdedHotelWiFi = WiFiSnapshot(powerOn: true, isConnected: true, ssid: "HotelGuest", security: .wpa2Personal)
        let homeWiFi = WiFiSnapshot(powerOn: true, isConnected: true, ssid: "Studio", security: .wpa3Personal)

        XCTAssertEqual(
            store.resolvedTrustZone(for: "ssid:Unitedwifi.com", wifi: openPlaneWiFi, exposure: LANExposureSnapshot(neighborCount: 33)),
            .untrusted
        )
        XCTAssertEqual(
            store.resolvedTrustZone(for: "ssid:HotelGuest", wifi: crowdedHotelWiFi, exposure: LANExposureSnapshot(neighborCount: 18)),
            .untrusted
        )
        XCTAssertEqual(
            store.resolvedTrustZone(for: "ssid:Studio", wifi: homeWiFi, exposure: LANExposureSnapshot(neighborCount: 4)),
            .home
        )

        // Explicit user override must always take precedence over smart default
        store.setTrustZone(.work, for: "ssid:HotelGuest")
        XCTAssertEqual(
            store.resolvedTrustZone(for: "ssid:HotelGuest", wifi: crowdedHotelWiFi, exposure: LANExposureSnapshot(neighborCount: 18)),
            .work
        )
    }

    // MARK: - Defensive Security Audit Regression Tests

    func testCaptivePortalURLSanitizerBlocksDangerousSchemes() {
        XCTAssertEqual(
            NetworkProbes.sanitizeCaptivePortalURL("https://wifi.united.com/login?next=1"),
            "https://wifi.united.com/login?next=1"
        )
        XCTAssertEqual(
            NetworkProbes.sanitizeCaptivePortalURL("http://portal.hotel.local/auth"),
            "http://portal.hotel.local/auth"
        )
        // Non-HTTP(S) schemes must fall back to safe Apple captive URL
        XCTAssertEqual(NetworkProbes.sanitizeCaptivePortalURL("file:///System/Applications/Calculator.app"), "http://captive.apple.com")
        XCTAssertEqual(NetworkProbes.sanitizeCaptivePortalURL("smb://192.168.1.1/share"), "http://captive.apple.com")
        XCTAssertEqual(NetworkProbes.sanitizeCaptivePortalURL("ssh://evil.example"), "http://captive.apple.com")
        XCTAssertEqual(NetworkProbes.sanitizeCaptivePortalURL("javascript:alert(1)"), "http://captive.apple.com")
        XCTAssertEqual(NetworkProbes.sanitizeCaptivePortalURL("https:///no-host"), "http://captive.apple.com")
        XCTAssertEqual(NetworkProbes.sanitizeCaptivePortalURL(nil), "http://captive.apple.com")
    }

    func testPrivilegedDNSScriptUsesArgvAndRejectsInvalidInputs() {
        let safeArgs = NetworkProbes.buildPrivilegedDNSScriptArguments(service: "Wi-Fi", servers: ["1.1.1.1", "1.0.0.1"])
        XCTAssertNotNil(safeArgs)
        XCTAssertEqual(safeArgs?.first, "-e")
        XCTAssertTrue(safeArgs?[1].contains("quoted form of") == true)
        XCTAssertFalse(safeArgs?[1].contains("Wi-Fi") == true)
        XCTAssertEqual(safeArgs?.dropFirst(2).map { $0 }, ["--", "Wi-Fi", "1.1.1.1", "1.0.0.1"])

        // Reject control characters and non-IP server tokens
        XCTAssertNil(NetworkProbes.buildPrivilegedDNSScriptArguments(service: "Wi-Fi\nwhoami", servers: ["1.1.1.1"]))
        XCTAssertNil(NetworkProbes.buildPrivilegedDNSScriptArguments(service: "Wi-Fi", servers: ["1.1.1.1; id"]))
        XCTAssertNotNil(NetworkProbes.buildPrivilegedDNSScriptArguments(service: "Wi-Fi", servers: ["Empty"]))
    }

    func testUnknownWiFiSecurityNotTreatedAsWeak() {
        XCTAssertFalse(WiFiSecurityKind.unknown.isWeak)
        XCTAssertFalse(WiFiSecurityKind.wpa2Personal.isWeak)
        XCTAssertFalse(WiFiSecurityKind.wpa3Personal.isWeak)
        XCTAssertTrue(WiFiSecurityKind.open.isWeak)
        XCTAssertTrue(WiFiSecurityKind.wep.isWeak)
        XCTAssertTrue(WiFiSecurityKind.wpaPersonal.isWeak)
    }

    func testICMPEchoReplyValidationRejectsErrorPackets() {
        // Real 28-byte macOS SOCK_DGRAM ICMP Echo Reply (20-byte IPv4 header + Type 0 Code 0 Seq 1)
        let validEchoReply: [UInt8] = [
            0x45, 0x00, 0x00, 0x1c, 0x32, 0x53, 0x00, 0x00,
            0x40, 0x01, 0x00, 0x00, 0x7f, 0x00, 0x00, 0x01,
            0x7f, 0x00, 0x00, 0x01,
            0x00, 0x00, 0xed, 0xca, 0x12, 0x34, 0x00, 0x01
        ]
        XCTAssertTrue(NativeNetworkTelemetry.isValidICMPEchoReply(validEchoReply, count: validEchoReply.count, expectedSequence: 1))

        // ICMP Destination Unreachable (Type 3, Code 1) must be rejected
        var destUnreach = validEchoReply
        destUnreach[20] = 3
        destUnreach[21] = 1
        XCTAssertFalse(NativeNetworkTelemetry.isValidICMPEchoReply(destUnreach, count: destUnreach.count, expectedSequence: 1))

        // Wrong sequence number must be rejected
        XCTAssertFalse(NativeNetworkTelemetry.isValidICMPEchoReply(validEchoReply, count: validEchoReply.count, expectedSequence: 2))

        // Truncated packet must be rejected
        XCTAssertFalse(NativeNetworkTelemetry.isValidICMPEchoReply(Array(validEchoReply.prefix(12)), count: 12, expectedSequence: 1))
    }

    func testPhysicalInterfaceForARPIgnoresVPNTunnels() {
        // Full-tunnel VPN sets PrimaryInterface to utun*; ARP must still read physical Wi-Fi en0
        XCTAssertEqual(
            NativeNetworkTelemetry.physicalInterfaceForARP(defaultInterface: "utun4", wifiInterface: "en0", wifiConnected: true),
            "en0"
        )
        XCTAssertEqual(
            NativeNetworkTelemetry.physicalInterfaceForARP(defaultInterface: "utun6", wifiInterface: "en0", wifiConnected: false),
            "en0"
        )
        XCTAssertEqual(
            NativeNetworkTelemetry.physicalInterfaceForARP(defaultInterface: "en7", wifiInterface: "en0", wifiConnected: false),
            "en7"
        )
        // Smoke-check native SCPreferences Wi-Fi service name lookup
        let svc = NativeNetworkTelemetry.readNetworkServiceName(forBSDInterface: "en0")
        XCTAssertNotNil(svc)
    }

    // MARK: - Parent-App Attribution, Active Interfaces, Split-Tunnel Accounting & Outbound Connections

    func testOutermostAppBundlePathResolvesNestedHelpers() {
        let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/130/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        XCTAssertEqual(
            AppAttribution.outermostAppBundlePath(forExecutablePath: chromeHelper),
            "/Applications/Google Chrome.app"
        )
        let electronHelper = "/Applications/Ando.app/Contents/Frameworks/Ando Helper (GPU).app/Contents/MacOS/Ando Helper (GPU)"
        XCTAssertEqual(
            AppAttribution.outermostAppBundlePath(forExecutablePath: electronHelper),
            "/Applications/Ando.app"
        )
        XCTAssertNil(AppAttribution.outermostAppBundlePath(forExecutablePath: "/usr/libexec/cloudd"))
        XCTAssertNil(AppAttribution.outermostAppBundlePath(forExecutablePath: ""))
    }

    func testDiffNettopGroupsHelperProcessesByParentApp() {
        let prev: [String: SystemParsers.NettopRow] = [
            "Google Chrome Helper.101": .init(name: "Google Chrome Helper", pid: 101, bytesIn: 10_000, bytesOut: 1_000),
            "Google Chrome Helper.102": .init(name: "Google Chrome Helper", pid: 102, bytesIn: 20_000, bytesOut: 2_000),
            "cloudd.200": .init(name: "cloudd", pid: 200, bytesIn: 5_000, bytesOut: 5_000)
        ]
        let cur: [String: SystemParsers.NettopRow] = [
            "Google Chrome Helper.101": .init(name: "Google Chrome Helper", pid: 101, bytesIn: 110_000, bytesOut: 11_000),
            "Google Chrome Helper.102": .init(name: "Google Chrome Helper", pid: 102, bytesIn: 220_000, bytesOut: 22_000),
            "cloudd.200": .init(name: "cloudd", pid: 200, bytesIn: 25_000, bytesOut: 15_000)
        ]
        let grouped = SystemParsers.diffNettop(previous: prev, current: cur, elapsedSeconds: 2.0, limit: 5) { pid, name in
            if pid == 101 || pid == 102 {
                return ResolvedApp(groupKey: "app:/applications/google chrome.app", displayName: "Google Chrome", appBundlePath: "/Applications/Google Chrome.app")
            }
            return ResolvedApp(groupKey: "bin:\(name.lowercased())", displayName: name, appBundlePath: nil)
        }

        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].name, "Google Chrome")
        XCTAssertEqual(grouped[0].appBundlePath, "/Applications/Google Chrome.app")
        XCTAssertEqual(grouped[0].processCount, 2)
        XCTAssertEqual(grouped[0].pid, 102) // highest contributor PID
        XCTAssertEqual(grouped[0].downloadBytesPerSec, 150_000, accuracy: 1.0)
        XCTAssertEqual(grouped[0].uploadBytesPerSec, 15_000, accuracy: 1.0)

        XCTAssertEqual(grouped[1].name, "cloudd")
        XCTAssertNil(grouped[1].appBundlePath)
        XCTAssertEqual(grouped[1].processCount, 1)
    }

    func testPhysicalThroughputInterfaceAndActiveInterfaces() {
        // Under split/full-tunnel VPN (`utun4`) while on Wi-Fi, measure physical `en0`
        XCTAssertEqual(
            InterfaceCounters.physicalThroughputInterface(defaultInterface: "utun4", wifiInterface: "en0", wifiConnected: true),
            "en0"
        )
        // On wired Ethernet (`en7`), measure `en7`
        XCTAssertEqual(
            InterfaceCounters.physicalThroughputInterface(defaultInterface: "en7", wifiInterface: "en0", wifiConnected: true),
            "en7"
        )

        let list = InterfaceCounters.buildActiveInterfaces(
            ipv4Map: [
                "utun4": "100.96.0.2",
                "en0": "172.19.249.21",
                "bridge100": "192.168.64.1",
                "awdl0": "169.254.1.2"
            ],
            wifiInterface: "en0",
            primaryInterface: "en0",
            connectedVPNName: "Twingate"
        )
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].kind, .wifi)
        XCTAssertEqual(list[0].displayName, "Wi-Fi")
        XCTAssertEqual(list[0].ipAddress, "172.19.249.21")
        XCTAssertEqual(list[1].kind, .vpn)
        XCTAssertEqual(list[1].displayName, "VPN · Twingate")
        XCTAssertEqual(list[1].ipAddress, "100.96.0.2")
    }

    func testParseEstablishedConnectionsProducesGroupedOutboundRows() {
        let sample = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Chrome\\x20H 501 graeme   42u  IPv4 0x123      0t0  TCP 172.19.249.21:51001->140.82.114.4:443 (ESTABLISHED)
        Chrome\\x20H 502 graeme   43u  IPv4 0x124      0t0  TCP 172.19.249.21:51002->140.82.114.4:443 (ESTABLISHED)
        curl        610 graeme    5u  IPv4 0x125      0t0  TCP 172.19.249.21:51003->93.184.216.34:80 (ESTABLISHED)
        """
        let xray = SystemParsers.parseEstablishedConnections(sample) { pid, cmd in
            if pid == 501 || pid == 502 {
                return ResolvedApp(groupKey: "app:/applications/google chrome.app", displayName: "Google Chrome", appBundlePath: "/Applications/Google Chrome.app")
            }
            return ResolvedApp(groupKey: "bin:\(cmd.lowercased())", displayName: cmd, appBundlePath: nil)
        }
        XCTAssertEqual(xray.totalOutboundSockets, 3)
        XCTAssertEqual(xray.plaintextHTTPCount, 1)
        XCTAssertEqual(xray.connections.count, 2)
        // Plaintext HTTP sorts first
        XCTAssertEqual(xray.connections[0].appName, "curl")
        XCTAssertEqual(xray.connections[0].serviceLabel, "HTTP")
        XCTAssertTrue(xray.connections[0].isPlaintextHTTP)
        // Duplicate sockets to same host collapse cleanly
        XCTAssertEqual(xray.connections[1].appName, "Google Chrome")
        XCTAssertEqual(xray.connections[1].serviceLabel, "HTTPS")
        XCTAssertEqual(xray.connections[1].socketCount, 2)
        XCTAssertEqual(xray.connections[1].remoteHost, "140.82.114.4")
        XCTAssertEqual(xray.connections[1].remotePort, 443)
    }

    func testMenuBarByteRateFormatter() {
        XCTAssertEqual(ByteRateFormatter.menuBar(0), "0 B/s")
        XCTAssertEqual(ByteRateFormatter.menuBar(512), "512 B/s")
        XCTAssertEqual(ByteRateFormatter.menuBar(45 * 1_024), "45.0 KB/s")
        XCTAssertEqual(ByteRateFormatter.menuBar(544 * 1_024), "544 KB/s")
        XCTAssertEqual(ByteRateFormatter.menuBar(21.9 * 1_024 * 1_024), "21.9 MB/s")
    }

    func testParseNettopDeltaUsesSecondChunkAndGroupsByParentApp() {
        let sample = """
        ,bytes_in,bytes_out,
        Antigravity Hel.100,99999999,88888888,
        cloudd.200,5555555,1111111,
        ,bytes_in,bytes_out,
        Antigravity Hel.100,120000,40000,
        language_server.101,80000,10000,
        cloudd.200,11264,0,
        """
        let grouped = SystemParsers.parseNettopDelta(sample, elapsedSeconds: 1.0, limit: 5) { pid, name in
            if pid == 100 || pid == 101 {
                return ResolvedApp(groupKey: "app:/applications/antigravity.app", displayName: "Antigravity", appBundlePath: "/Applications/Antigravity.app")
            }
            return ResolvedApp(groupKey: "bin:\(name.lowercased())", displayName: name, appBundlePath: nil)
        }
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].name, "Antigravity")
        XCTAssertEqual(grouped[0].processCount, 2)
        XCTAssertEqual(grouped[0].downloadBytesPerSec, 200_000, accuracy: 1.0)
        XCTAssertEqual(grouped[0].uploadBytesPerSec, 50_000, accuracy: 1.0)
        XCTAssertEqual(grouped[1].name, "cloudd")
        XCTAssertEqual(grouped[1].downloadBytesPerSec, 11_264, accuracy: 1.0)
    }

    func testSatelliteHighLatencyNeverReportsSmoothOrReady() {
        // Real United airplane Wi-Fi scenario: strong cabin AP (360 Mbps PHY, 39 dB SNR),
        // fast local router (3ms), but 642ms satellite internet RTT.
        let cabinWiFi = WiFiSnapshot(
            powerOn: true,
            isConnected: true,
            ssid: "Unitedwifi.com",
            rssi: -52,
            noise: -91,
            txRateMbps: 360,
            channel: 149,
            band: .band5,
            channelWidthMHz: 80,
            security: .open
        )
        let hops = HopHealth(routerMs: 3.2, dnsMs: 4.0, internetMs: 642.0)
        let stab = StabilityCalculator.compute(samples: [
            LatencySample(routerMs: 3.0, dnsMs: 4.0, internetMs: 640.0),
            LatencySample(routerMs: 3.2, dnsMs: 4.0, internetMs: 644.0)
        ])
        let readiness = HumanSummary.activityReadiness(
            wifi: cabinWiFi,
            isWired: false,
            hopHealth: hops,
            stability: stab,
            quality: nil,
            rfPhysics: RFPhysics.compute(wifi: cabinWiFi, overlappingAPs: 0),
            awdl: AWDLSnapshot()
        )
        XCTAssertEqual(readiness.count, 3)
        XCTAssertEqual(readiness[0].status, ReadinessStatus.poor) // Video Calls -> Laggy
        XCTAssertEqual(readiness[1].status, ReadinessStatus.poor) // 4K Video -> Slow (not fooled by 360 Mbps cabin PHY!)
        XCTAssertEqual(readiness[2].status, ReadinessStatus.poor) // Live & Games -> Laggy
        XCTAssertEqual(HumanSummary.humanHopLabel(ms: hops.internetMs, warn: 70, bad: 150), "Slow")
    }

    func testLocalNetworkAdvisorGroundedContextAndContradictionGuard() {
        let cabinWiFi = WiFiSnapshot(
            powerOn: true,
            isConnected: true,
            ssid: "Unitedwifi.com",
            rssi: -52,
            noise: -91,
            txRateMbps: 360,
            channel: 149,
            band: .band5,
            channelWidthMHz: 80,
            security: .open
        )
        let input = NetworkAdvisorInput(
            wifi: cabinWiFi,
            isWired: false,
            hopHealth: HopHealth(routerMs: 3.0, dnsMs: 4.0, internetMs: 642.0),
            stability: StabilityMetrics(avgInternetMs: 642.0, jitterMs: 2.2, packetLossPercent: 0, callGrade: .choppy, verdict: "High RTT"),
            channelAnalysis: ChannelAnalysis(),
            rfPhysics: RFPhysics.compute(wifi: cabinWiFi, overlappingAPs: 0),
            awdl: AWDLSnapshot(),
            trustAudit: TrustAudit(level: .caution, score: 78, headline: "Open Wi-Fi shielded by VPN"),
            trustZone: .untrusted,
            vpns: [VPNService(uuid: "1", name: "Twingate", bundleID: "com.twingate.macos", status: "Connected")],
            dns: DNSSnapshot(servers: ["100.95.0.251"], providerLabel: "VPN DNS", posture: .vpnTunnel, hasTunnelResolver: true),
            exposure: LANExposureSnapshot(neighborCount: 33),
            throughput: ThroughputSample(downloadBytesPerSec: 32_000, uploadBytesPerSec: 885_000),
            sessionPeakBytesPerSec: 1_320_000,
            topProcesses: [
                ProcessBandwidth(name: "Antigravity", pid: 100, downloadBytesPerSec: 1_000, uploadBytesPerSec: 119_000)
            ],
            qualityResult: nil,
            events: []
        )

        let ctx = LocalNetworkAdvisor.buildGroundedContext(from: input)
        XCTAssertTrue(ctx.contains("Unitedwifi.com"))
        XCTAssertTrue(ctx.contains("642 ms"))
        XCTAssertTrue(ctx.contains("Antigravity"))
        XCTAssertTrue(ctx.contains("Twingate VPN is already connected"))

        let diag = LocalNetworkAdvisor.deterministicDiagnosis(from: input)
        XCTAssertTrue(diag.summary.contains("642 ms"))
        XCTAssertTrue(diag.summary.contains("Antigravity"))
        XCTAssertTrue(diag.nextStep.contains("Antigravity"))

        // Contradiction guard must block hallucinated "switch to 5 GHz" when already on 5 GHz,
        // and block "turn on a VPN" when Twingate is already connected!
        XCTAssertTrue(LocalNetworkAdvisor.containsContradiction(text: "Try to switch to 5 GHz for faster speed.", input: input))
        XCTAssertTrue(LocalNetworkAdvisor.containsContradiction(text: "You should turn on a VPN on public Wi-Fi.", input: input))
        XCTAssertFalse(LocalNetworkAdvisor.containsContradiction(text: "Pause Antigravity uploads while on satellite Wi-Fi.", input: input))
    }

    func testWiFiJoinErrorTranslationNeverLeaksTmpErr() {
        let tmpErr = NSError(
            domain: "com.apple.wifi.apple80211API.error",
            code: -3900,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed. tmpErr"]
        )

        let directSaved = WiFiController.classifyJoinError(
            tmpErr,
            ssid: "iPhone (38)",
            hadPassword: false,
            isKnown: true,
            isSandboxed: false
        )
        XCTAssertEqual(directSaved, .passwordRequired(ssid: "iPhone (38)", isKnown: true, isSandboxed: false))
        XCTAssertTrue(directSaved.needsPasswordPrompt)
        XCTAssertFalse((directSaved.errorDescription ?? "").contains("tmpErr"))
        XCTAssertTrue((directSaved.errorDescription ?? "").contains("iPhone (38)"))

        let sandboxSaved = WiFiController.classifyJoinError(
            tmpErr,
            ssid: "iPhone (38)",
            hadPassword: false,
            isKnown: true,
            isSandboxed: true
        )
        XCTAssertEqual(sandboxSaved, .passwordRequired(ssid: "iPhone (38)", isKnown: true, isSandboxed: true))
        XCTAssertTrue((sandboxSaved.errorDescription ?? "").contains("sandbox"))

        let wrongPass = WiFiController.classifyJoinError(
            tmpErr,
            ssid: "iPhone (38)",
            hadPassword: true,
            isKnown: true,
            isSandboxed: false
        )
        XCTAssertEqual(wrongPass, .authenticationFailed(ssid: "iPhone (38)"))
        XCTAssertTrue(wrongPass.needsPasswordPrompt)

        let timeoutErr = NSError(domain: "com.apple.wifi.apple80211API.error", code: -3905, userInfo: nil)
        let timedOut = WiFiController.classifyJoinError(
            timeoutErr,
            ssid: "iPhone (38)",
            hadPassword: false,
            isKnown: true,
            isSandboxed: false
        )
        XCTAssertEqual(timedOut, .timedOut(ssid: "iPhone (38)"))
        XCTAssertFalse(timedOut.needsPasswordPrompt)
    }

    func testNetworkSetupJoinFailureParsing() {
        // Clean exit 0 with no output means success
        XCTAssertNil(WiFiController.parseNetworkSetupJoinFailure(
            output: "",
            exitCode: 0,
            ssid: "iPhone (38)",
            hadPassword: false,
            isKnown: true
        ))

        // networksetup often returns exit code 0 while printing "Could not find network"
        let notFound = WiFiController.parseNetworkSetupJoinFailure(
            output: "Could not find network iPhone (38).\n",
            exitCode: 0,
            ssid: "iPhone (38)",
            hadPassword: false,
            isKnown: true
        )
        XCTAssertEqual(notFound, .notInRange(ssid: "iPhone (38)"))
        XCTAssertFalse(notFound?.needsPasswordPrompt ?? true)

        // Failed join without password should prompt for password cleanly
        let needsPw = WiFiController.parseNetworkSetupJoinFailure(
            output: "Failed to join network iPhone (38).\nError: -3900 The operation couldn't be completed.",
            exitCode: 0,
            ssid: "iPhone (38)",
            hadPassword: false,
            isKnown: true
        )
        XCTAssertEqual(needsPw, .passwordRequired(ssid: "iPhone (38)", isKnown: true, isSandboxed: false))
        XCTAssertTrue(needsPw?.needsPasswordPrompt ?? false)

        // Failed join WITH password -> wrong password
        let badPw = WiFiController.parseNetworkSetupJoinFailure(
            output: "Failed to join network Studio 5G.\nError: -3924",
            exitCode: 1,
            ssid: "Studio 5G",
            hadPassword: true,
            isKnown: false
        )
        XCTAssertEqual(badPw, .authenticationFailed(ssid: "Studio 5G"))

        // Timeout (-3905) takes precedence over "Failed to join"
        let timeout = WiFiController.parseNetworkSetupJoinFailure(
            output: "Failed to join network iPhone (38).\nError: -3905 The operation couldn't be completed.",
            exitCode: 0,
            ssid: "iPhone (38)",
            hadPassword: false,
            isKnown: true
        )
        XCTAssertEqual(timeout, .timedOut(ssid: "iPhone (38)"))
    }
}
