import Foundation

/// Pure security & privacy evaluation engine.
/// Produces plain-English verdicts without scareware — separating genuine threats
/// (open Wi-Fi, ARP/gateway change, encryption downgrade, exposed dev ports on public Wi-Fi,
/// transparent proxies) from normal baseline conditions.
public enum TrustAnalyzer {

    public static func evaluate(
        wifi: WiFiSnapshot,
        route: RouteInfo,
        dns: DNSSnapshot,
        vpns: [VPNService],
        proxy: ProxySnapshot,
        exposure: LANExposureSnapshot,
        zone: TrustZone,
        pinnedFingerprint: NetworkFingerprint?,
        localBroadcastName: String? = nil,
        connectionXRay: ConnectionXRay? = nil
    ) -> TrustAudit {
        let activeVPN = vpns.first(where: { $0.isConnected })
        let hasActiveLink = wifi.isConnected || route.defaultInterface != nil

        guard hasActiveLink else {
            return TrustAudit(
                level: .offline,
                score: 0,
                headline: wifi.powerOn ? "No active network connection" : "Wi-Fi radio turned off",
                checks: []
            )
        }

        var checks: [AuditCheck] = []
        var score = 100
        var hasGatewayAnomaly = false
        var hasSecurityDowngrade = false

        // 1. Link Encryption (Wi-Fi vs Wired)
        if wifi.isConnected {
            switch wifi.security {
            case .wpa3Personal, .wpa3Enterprise:
                checks.append(AuditCheck(
                    id: "link",
                    category: "LINK",
                    title: "\(wifi.security.rawValue) encrypted",
                    detail: "Modern forward-secret Wi-Fi encryption protects local radio traffic.",
                    severity: .ok
                ))
            case .wpa2Enterprise, .wpa3Transition:
                checks.append(AuditCheck(
                    id: "link",
                    category: "LINK",
                    title: "\(wifi.security.rawValue) encrypted",
                    detail: "Strong wireless encryption active on \(wifi.band.rawValue) Ch \(wifi.channel).",
                    severity: .ok
                ))
            case .wpa2Personal:
                let detail = zone == .untrusted
                    ? "Shared WPA2 password on a public network — peers with the password can inspect unencrypted frames."
                    : "WPA2 Personal active. Upgrade router to WPA3 if supported."
                let sev: AuditSeverity = (zone == .untrusted && activeVPN == nil) ? .caution : .ok
                if sev == .caution { score -= 12 }
                checks.append(AuditCheck(
                    id: "link",
                    category: "LINK",
                    title: "WPA2 Personal",
                    detail: detail,
                    severity: sev
                ))
            case .open, .wep, .wpaPersonal:
                score -= (activeVPN != nil ? 20 : 45)
                checks.append(AuditCheck(
                    id: "link",
                    category: "LINK",
                    title: "\(wifi.security.rawValue) — unencrypted Wi-Fi",
                    detail: activeVPN != nil
                        ? "Airlink is weak, but \(activeVPN!.name) tunnel encrypts your traffic."
                        : "Anyone nearby can capture unencrypted traffic. Turn on a VPN.",
                    severity: activeVPN != nil ? .caution : .alert
                ))
            case .unknown:
                checks.append(AuditCheck(
                    id: "link",
                    category: "LINK",
                    title: "Wi-Fi security unreadable",
                    detail: "Grant Location access so macOS exposes full Wi-Fi security & SSID.",
                    severity: .info
                ))
            }
        } else if let iface = route.defaultInterface {
            checks.append(AuditCheck(
                id: "link",
                category: "LINK",
                title: "Wired / Direct (\(iface))",
                detail: "Traffic routed over physical interface \(iface).",
                severity: .ok
            ))
        }

        // 2. VPN / Tunnel Route
        if let vpn = activeVPN {
            checks.append(AuditCheck(
                id: "vpn",
                category: "TUNNEL",
                title: "\(vpn.name) active",
                detail: "Encrypted tunnel shields traffic from local Wi-Fi and ISP observers.",
                severity: .ok
            ))
        } else if dns.hasTunnelResolver {
            checks.append(AuditCheck(
                id: "vpn",
                category: "TUNNEL",
                title: "Tunnel interface active (\(dns.tunnelInterface ?? "utun"))",
                detail: "Active utun resolver detected in system routing.",
                severity: .ok
            ))
        } else {
            let sev: AuditSeverity = zone == .untrusted ? .caution : .info
            if sev == .caution { score -= 15 }
            checks.append(AuditCheck(
                id: "vpn",
                category: "TUNNEL",
                title: "Direct ISP exit (no VPN)",
                detail: zone == .untrusted
                    ? "On public Wi-Fi without a VPN. Consider enabling a tunnel."
                    : "Standard direct route on \(zone.label.lowercased()) network.",
                severity: sev
            ))
        }

        // 3. DNS Privacy
        switch dns.posture {
        case .vpnTunnel:
            checks.append(AuditCheck(
                id: "dns",
                category: "DNS",
                title: dns.providerLabel,
                detail: "Domain lookups routed through tunnel (\(dns.servers.prefix(2).joined(separator: ", "))).",
                severity: .ok
            ))
        case .trustedProvider:
            checks.append(AuditCheck(
                id: "dns",
                category: "DNS",
                title: dns.providerLabel,
                detail: "Resolvers: \(dns.servers.prefix(2).joined(separator: ", ")).",
                severity: .ok
            ))
        case .localRouter:
            let sev: AuditSeverity = (zone == .untrusted && activeVPN == nil) ? .caution : .info
            if sev == .caution { score -= 15 }
            checks.append(AuditCheck(
                id: "dns",
                category: "DNS",
                title: dns.providerLabel,
                detail: "Local network / ISP can see domain names you look up outside DoH browsers.",
                severity: sev
            ))
        case .custom:
            checks.append(AuditCheck(
                id: "dns",
                category: "DNS",
                title: dns.providerLabel,
                detail: "Custom resolver active (\(dns.servers.prefix(2).joined(separator: ", "))).",
                severity: .info
            ))
        case .unknown:
            score -= 10
            checks.append(AuditCheck(
                id: "dns",
                category: "DNS",
                title: "No reachable DNS resolver",
                detail: "Domain resolution may fail or be blocked by a captive portal.",
                severity: .caution
            ))
        }

        // 4. Evil Twin & Gateway ARP Fingerprint Watch
        if let pinned = pinnedFingerprint {
            if let expectedGW = pinned.gatewayMAC,
               let currentGW = route.gatewayMAC,
               expectedGW.lowercased() != currentGW.lowercased() {
                hasGatewayAnomaly = true
                score -= 35
                checks.append(AuditCheck(
                    id: "arp",
                    category: "GATEWAY",
                    title: "Gateway MAC changed",
                    detail: "Expected \(expectedGW), now seeing \(currentGW). Verify router or watch for ARP spoofing.",
                    severity: .alert
                ))
            }
            if wifi.isConnected && wifi.security != .unknown && wifi.security.strengthRank < pinned.strongestSecurityRank {
                hasSecurityDowngrade = true
                score -= 35
                checks.append(AuditCheck(
                    id: "downgrade",
                    category: "EVIL TWIN",
                    title: "Encryption downgraded on \(pinned.ssid)",
                    detail: "Previously stronger security; now \(wifi.security.rawValue). Possible rogue AP.",
                    severity: .alert
                ))
            }
        }

        // 5. Private Wi-Fi Address (MAC Randomization)
        if wifi.isConnected, let isPrivate = wifi.isPrivateMAC {
            if isPrivate {
                checks.append(AuditCheck(
                    id: "mac",
                    category: "MAC",
                    title: "Private Wi-Fi Address active",
                    detail: "Randomized locally-administered MAC (\(wifi.hardwareMAC ?? "—")) limits device tracking.",
                    severity: .ok
                ))
            } else {
                let sev: AuditSeverity = zone == .untrusted ? .caution : .info
                if sev == .caution { score -= 10 }
                checks.append(AuditCheck(
                    id: "mac",
                    category: "MAC",
                    title: "Fixed hardware MAC exposed",
                    detail: zone == .untrusted
                        ? "Hardware MAC (\(wifi.hardwareMAC ?? "—")) is trackable across public networks."
                        : "Hardware MAC (\(wifi.hardwareMAC ?? "—")) is fine on trusted networks.",
                    severity: sev
                ))
            }
        }

        // 6. Proxy / Interception Check
        if proxy.isAnyProxyActive {
            score -= 18
            checks.append(AuditCheck(
                id: "proxy",
                category: "PROXY",
                title: "\(proxy.summary) active",
                detail: "System proxy is routing or inspecting traffic. Verify this is intentional.",
                severity: .caution
            ))
        }

        // 7. LAN Exposure & Dev Ports
        if !exposure.exposedUserPorts.isEmpty {
            let portList = exposure.exposedUserPorts.prefix(4).map { "\($0.process):\($0.port)" }.joined(separator: ", ")
            let sev: AuditSeverity = zone == .untrusted ? .caution : .info
            if sev == .caution { score -= 14 }
            checks.append(AuditCheck(
                id: "ports",
                category: "LAN",
                title: "\(exposure.exposedUserPorts.count) port\(exposure.exposedUserPorts.count == 1 ? "" : "s") bound to 0.0.0.0",
                detail: "Reachable by \(exposure.neighborCount) LAN peers: \(portList).",
                severity: sev
            ))
        } else {
            checks.append(AuditCheck(
                id: "ports",
                category: "LAN",
                title: "No dev ports exposed on LAN",
                detail: "\(exposure.neighborCount) active peer\(exposure.neighborCount == 1 ? "" : "s") on local subnet.",
                severity: .ok
            ))
        }

        // 8. mDNS / Bonjour Name Broadcast ("What Your Mac Shouts to the Room")
        if let mdnsName = localBroadcastName, !mdnsName.isEmpty, exposure.neighborCount > 0 {
            let sev: AuditSeverity = zone == .untrusted ? .caution : .info
            if sev == .caution { score -= 6 }
            checks.append(AuditCheck(
                id: "mdns",
                category: "BONJOUR",
                title: "Broadcasting as \(mdnsName)",
                detail: zone == .untrusted
                    ? "Visible via mDNS to \(exposure.neighborCount) strangers on this public Wi-Fi."
                    : "Local mDNS name visible to \(exposure.neighborCount) device\(exposure.neighborCount == 1 ? "" : "s") on your LAN.",
                severity: sev
            ))
        }

        // 9. Live Outbound Connection X-Ray (Plaintext HTTP :80 check)
        if let xray = connectionXRay {
            if xray.plaintextHTTPCount > 0 {
                score -= 12
                let culprits = xray.topApps.filter(\.hasPlaintextHTTP).map(\.name).joined(separator: ", ")
                checks.append(AuditCheck(
                    id: "xray",
                    category: "X-RAY",
                    title: "\(xray.plaintextHTTPCount) unencrypted HTTP (:80) socket\(xray.plaintextHTTPCount == 1 ? "" : "s")",
                    detail: "Active plaintext traffic from \(culprits.isEmpty ? "background app" : culprits) (\(xray.totalOutboundSockets) total sockets).",
                    severity: .caution
                ))
            } else if xray.totalOutboundSockets > 0 {
                let appsList = xray.topApps.prefix(3).map { "\($0.name)(\($0.connectionCount))" }.joined(separator: ", ")
                checks.append(AuditCheck(
                    id: "xray",
                    category: "X-RAY",
                    title: "\(xray.totalOutboundSockets) live sockets · 0 plaintext HTTP",
                    detail: "Active apps: \(appsList)\(xray.continuityPeerLinks > 0 ? " · +\(xray.continuityPeerLinks) Apple Continuity links" : "").",
                    severity: .ok
                ))
            }
        }

        let clampedScore = min(max(score, 0), 100)
        let worstSeverity = checks.map(\.severity).max() ?? .ok

        let level: TrustLevel
        let headline: String
        if worstSeverity == .alert {
            level = .alert
            if hasGatewayAnomaly {
                headline = "Gateway MAC changed — verify network"
            } else if hasSecurityDowngrade {
                headline = "Security downgraded — possible rogue AP"
            } else {
                headline = "Unencrypted connection — enable VPN"
            }
        } else if worstSeverity == .caution {
            level = .caution
            headline = checks.first(where: { $0.severity == .caution })?.title ?? "Review network posture"
        } else if activeVPN != nil || dns.hasTunnelResolver {
            level = .shielded
            headline = "Encrypted link & tunnel active"
        } else {
            level = .trusted
            headline = "Clean route · \(zone.label.lowercased()) network"
        }

        // Sort highest severity first so issues are never buried
        checks.sort { $0.severity > $1.severity }

        return TrustAudit(
            level: level,
            score: clampedScore,
            headline: headline,
            checks: checks,
            hasGatewayAnomaly: hasGatewayAnomaly,
            hasSecurityDowngrade: hasSecurityDowngrade
        )
    }
}
