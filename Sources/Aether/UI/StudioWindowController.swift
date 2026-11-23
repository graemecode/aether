import AetherCore
import AppKit
import SwiftUI

/// Custom Studio NSWindow that closes cleanly on Escape without ever triggering AppKit double-release.
private final class StudioNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }
}

/// Expandable dark-obsidian Aether Studio workstation window (matching Satie's Studio pattern).
@MainActor
final class StudioWindowController: NSObject, NSWindowDelegate {
    private var window: StudioNSWindow?

    func show() {
        if let existing = window {
            AppState.shared.isStudioOpen = true
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = AetherStudioView(state: AppState.shared)

        let win = StudioNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Aether Studio"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor(red: 0.026, green: 0.030, blue: 0.038, alpha: 1.0)
        win.appearance = NSAppearance(named: .darkAqua)
        win.minSize = NSSize(width: 840, height: 560)
        // CRITICAL: AppKit defaults isReleasedWhenClosed = true, which causes SIGSEGV in
        // -[_NSWindowTransformAnimation dealloc] when owned by Swift ARC. Keep window retained & reused.
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: view)
        win.delegate = self
        win.center()

        self.window = win
        AppState.shared.isStudioOpen = true
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        AppState.shared.isStudioOpen = false
    }

    func windowWillClose(_ notification: Notification) {
        // Keep `self.window` retained (isReleasedWhenClosed = false) so AppKit close animations
        // never dereference a freed window and reopening Studio is instantaneous.
        AppState.shared.isStudioOpen = false
    }
}

// MARK: - Studio Workstation View

struct AetherStudioView: View {
    enum BottomLeftTab: String, CaseIterable, Identifiable {
        case lanDevices = "LAN DEVICES"
        case connections = "CONNECTIONS"
        var id: String { rawValue }
    }

    @ObservedObject var state: AppState
    @State private var selectedBand: WiFiBand = .band24
    @State private var bottomLeftTab: BottomLeftTab = .lanDevices
    @State private var askInput: String = ""
    @Namespace private var bandNS
    @Namespace private var bottomTabNS

    private let bg = Color(red: 0.026, green: 0.030, blue: 0.038)
    private let cardBg = Color.white.opacity(0.034)
    private let inkSoft = Color.white.opacity(0.74)
    private let inkDim = Color.white.opacity(0.44)

    var body: some View {
        VStack(spacing: 14) {
            // Top Studio Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 8) {
                        Text("Aether Studio")
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundColor(.white)
                        Text("·")
                            .foregroundColor(inkDim)
                        Text(state.heroTitle)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.86))
                    }
                    Text(state.studioHeadline)
                        .font(.system(size: 11.2, weight: .regular))
                        .foregroundColor(inkSoft)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await state.scanNearbyNetworks()
                            await state.refreshEnvironment(includeHops: true)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text(state.isScanningNetworks ? "Scanning…" : "Rescan")
                                .font(.system(size: 10.2, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 11)
                        .frame(height: 27)
                        .background(Color.white.opacity(0.065))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        state.copyDiagnosticsReport()
                    } label: {
                        Text("Export Report")
                            .font(.system(size: 10.2, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .frame(height: 27)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)

            // 6-Cell RF Physics & Live X-Ray Telemetry Strip
            HStack(spacing: 8) {
                physicsMetricCell(
                    label: "RF POWER",
                    value: state.rfPhysics.signalPowerLabel,
                    sub: state.rfPhysics.centerFreqMHz > 0 ? "\(state.rfPhysics.centerFreqMHz) MHz" : "—"
                )
                physicsMetricCell(
                    label: "SIGNAL / NOISE",
                    value: state.rfPhysics.snrMultiplierLabel,
                    sub: state.wifi.isConnected ? "\(state.wifi.snr) dB SNR" : "—"
                )
                physicsMetricCell(
                    label: "EST. DISTANCE",
                    value: state.rfPhysics.estimatedRangeLabel.components(separatedBy: " · ").first ?? "—",
                    sub: state.rfPhysics.estimatedRangeLabel.components(separatedBy: " · ").dropFirst().first ?? "Path loss"
                )
                physicsMetricCell(
                    label: "REAL TCP MAX",
                    value: state.rfPhysics.realMaxTcpMbps > 0 ? "~\(state.rfPhysics.realMaxTcpMbps) Mbps" : "—",
                    sub: "Half-duplex PHY \(Int(round(state.wifi.txRateMbps)))M"
                )
                physicsMetricCell(
                    label: "AIRDROP RADIO",
                    value: state.awdl.isActive ? (state.awdl.isStealingAirtime ? "Hopping" : "Active") : "Idle",
                    sub: "\(state.awdl.totalPackets) awdl0 pkts",
                    accent: state.awdl.isStealingAirtime ? Color(red: 1.0, green: 0.74, blue: 0.34) : .white
                )
                #if APP_STORE
                physicsMetricCell(
                    label: "IPv6 · PRIVACY",
                    value: state.hasGlobalIPv6 ? "Native IPv6" : "IPv4 Only",
                    sub: state.wifi.isPrivateMAC == true ? "Private Wi-Fi MAC" : "Hardware MAC"
                )
                #else
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        bottomLeftTab = .connections
                    }
                } label: {
                    physicsMetricCell(
                        label: "LIVE X-RAY · IPv6",
                        value: "\(state.connectionXRay.totalOutboundSockets) Sockets",
                        sub: "\(state.connectionXRay.plaintextHTTPCount) HTTP · \(state.hasGlobalIPv6 ? "Native IPv6" : "IPv4 only")",
                        accent: state.connectionXRay.plaintextHTTPCount > 0 ? Color(red: 1.0, green: 0.50, blue: 0.46) : .white
                    )
                }
                .buttonStyle(.plain)
                .help("View active apps and live outbound connections")
                #endif
            }

            // Top Row: RF Channel Spectrum Analyzer (Left) + Multi-Hop Latency/Jitter Timeline (Right)
            HStack(spacing: 14) {
                spectrumCard
                latencyTimelineCard
            }
            .frame(maxHeight: .infinity)

            // Bottom Row: LAN Devices / Live Apps & Connections (Left) + Connection Event Log (Right)
            HStack(spacing: 14) {
                devicesOrConnectionsCard
                eventLogCard
            }
            .frame(maxHeight: .infinity)

            // Quiet On-Device "Ask Aether" Command Strip (0% idle cost, 100% local)
            studioAskBar
        }
        .padding(18)
        .background(bg)
        .onAppear {
            if state.wifi.band == .band5 || state.wifi.band == .band6 || state.wifi.band == .band24 {
                selectedBand = state.wifi.band
            }
            if state.studioFocusConnections {
                bottomLeftTab = .connections
                state.studioFocusConnections = false
            }
            Task { await state.scanNearbyNetworks() }
        }
        .onChange(of: state.studioFocusConnections) { _, shouldFocus in
            if shouldFocus {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    bottomLeftTab = .connections
                }
                state.studioFocusConnections = false
            }
        }
    }

    // MARK: - 1. RF Channel Spectrum & Interference Analyzer

    private var spectrumCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RF CHANNEL SPECTRUM")
                        .font(.system(size: 9.0, weight: .semibold, design: .monospaced))
                        .foregroundColor(inkSoft)
                        .tracking(0.6)
                    Text(state.channelAnalysis.recommendationSummary)
                        .font(.system(size: 10.6))
                        .foregroundColor(inkDim)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach([WiFiBand.band24, .band5, .band6], id: \.self) { band in
                        let on = selectedBand == band
                        let count = state.channelAnalysis.lobes(for: band).count
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                selectedBand = band
                            }
                        } label: {
                            Text("\(band.shortBadge) (\(count))")
                                .font(.system(size: 8.6, weight: on ? .semibold : .regular, design: .monospaced))
                                .foregroundColor(on ? .black : inkSoft)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background {
                                    if on {
                                        Capsule()
                                            .fill(Color.white)
                                            .matchedGeometryEffect(id: "studioBandPill", in: bandNS)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2.5)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
            }

            ChannelSpectrumCanvas(
                lobes: state.channelAnalysis.lobes(for: selectedBand),
                band: selectedBand,
                recommendedChannel: selectedBand == state.wifi.band ? state.channelAnalysis.recommendedChannel : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(specularBorder(radius: 9, subtle: true))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Radio frequency channel spectrum for \(selectedBand.rawValue)")
            .accessibilityValue("\(state.channelAnalysis.lobes(for: selectedBand).count) access points visible. \(state.channelAnalysis.recommendationSummary)")

            if let roam = state.channelAnalysis.roamingNudge {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.0, green: 0.76, blue: 0.36)).frame(width: 6, height: 6)
                    Text(roam.reason)
                        .font(.system(size: 10.2))
                        .foregroundColor(.white.opacity(0.88))
                        .lineLimit(1)
                    Spacer()
                    Button(state.isRoaming ? "Switching…" : "Switch Now") {
                        state.roamToBetterAP()
                    }
                    .font(.system(size: 9.2, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(specularBorder(radius: 12))
    }

    // MARK: - 2. Multi-Hop Latency, Jitter & Packet Loss Timeline (Interactive Crosshair!)

    private var latencyTimelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LATENCY, JITTER & LOSS")
                        .font(.system(size: 9.0, weight: .semibold, design: .monospaced))
                        .foregroundColor(inkSoft)
                        .tracking(0.6)
                    Text(state.stability.verdict)
                        .font(.system(size: 10.6))
                        .foregroundColor(inkDim)
                        .lineLimit(1)
                }
                Spacer()
                Text(state.stability.callGrade.rawValue)
                    .font(.system(size: 8.6, weight: .semibold, design: .monospaced))
                    .foregroundColor(callGradeColor(state.stability.callGrade))
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(callGradeColor(state.stability.callGrade).opacity(0.14))
                    .clipShape(Capsule())
            }

            LatencyTimelineCanvas(samples: state.latencyHistory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(specularBorder(radius: 9, subtle: true))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Multi-hop latency, jitter, and packet loss timeline")
                .accessibilityValue(state.stability.verdict)

            HStack(spacing: 14) {
                legendChip(color: Color(red: 0.78, green: 0.92, blue: 1.0), text: "Internet \(ByteRateFormatter.ms(state.hopHealth.internetMs))")
                legendChip(color: Color(red: 1.0, green: 0.80, blue: 0.50), text: "Lookup \(ByteRateFormatter.ms(state.hopHealth.dnsMs))")
                legendChip(color: Color(red: 0.34, green: 0.90, blue: 0.66), text: "Router \(ByteRateFormatter.ms(state.hopHealth.routerMs))")
                Spacer()
                Text("Hover graph to inspect")
                    .font(.system(size: 8.4))
                    .foregroundColor(inkDim)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(specularBorder(radius: 12))
    }

    // MARK: - 3. LAN Devices & Live Apps / Outbound Connections

    private var devicesOrConnectionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                #if APP_STORE
                Text("DEVICES ON THIS WI-FI (\(state.lanDevices.count))")
                    .font(.system(size: 9.0, weight: .semibold, design: .monospaced))
                    .foregroundColor(inkSoft)
                    .tracking(0.6)
                #else
                HStack(spacing: 2) {
                    ForEach(BottomLeftTab.allCases) { tab in
                        let on = bottomLeftTab == tab
                        let count = tab == .lanDevices ? state.lanDevices.count : state.connectionXRay.totalOutboundSockets
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                bottomLeftTab = tab
                            }
                        } label: {
                            Text("\(tab.rawValue) (\(count))")
                                .font(.system(size: 8.4, weight: on ? .semibold : .regular, design: .monospaced))
                                .foregroundColor(on ? .black : inkSoft)
                                .padding(.horizontal, 8.5)
                                .frame(height: 22)
                                .background {
                                    if on {
                                        Capsule()
                                            .fill(Color.white)
                                            .matchedGeometryEffect(id: "studioBottomTabPill", in: bottomTabNS)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2.5)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                #endif

                Spacer()

                Text(bottomLeftTab == .lanDevices
                     ? "ARP · OUI · mDNS"
                     : "\(state.connectionXRay.uniqueRemoteHosts) HOSTS · PEAK \(state.sessionPeakBytesPerSec >= 1_024 ? ByteRateFormatter.menuBar(state.sessionPeakBytesPerSec) : "—")")
                    .font(.system(size: 8.0, design: .monospaced))
                    .foregroundColor(inkDim)
                    .lineLimit(1)
            }

            #if APP_STORE
            lanDevicesList
            #else
            if bottomLeftTab == .lanDevices {
                lanDevicesList
            } else {
                appsAndConnectionsList
            }
            #endif
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(specularBorder(radius: 12))
    }

    private var lanDevicesList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 4) {
                ForEach(state.lanDevices) { dev in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(dev.isGateway ? Color(red: 0.30, green: 0.90, blue: 0.64) : (dev.isLocalMac ? Color.white : Color.white.opacity(0.35)))
                            .frame(width: 5.5, height: 5.5)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(dev.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.94))
                                    .lineLimit(1)
                                if dev.isGateway {
                                    miniTag("ROUTER", color: Color(red: 0.30, green: 0.90, blue: 0.64))
                                } else if dev.isLocalMac {
                                    miniTag("THIS MAC", color: .white)
                                } else if dev.isPrivateMAC {
                                    miniTag("PRIVATE MAC", color: Color(red: 0.72, green: 0.86, blue: 1.0))
                                }
                            }
                            Text("\(dev.vendor) · \(dev.mac)")
                                .font(.system(size: 8.6, design: .monospaced))
                                .foregroundColor(inkDim)
                        }

                        Spacer()

                        Button {
                            state.copyToClipboard(dev.ip, label: dev.ip)
                        } label: {
                            Text(dev.ip)
                                .font(.system(size: 9.8, weight: .medium, design: .monospaced))
                                .foregroundColor(inkSoft)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5.5)
                    .background(Color.white.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
    }

    private var appsAndConnectionsList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                // Active interfaces summary strip
                if !state.activeInterfaces.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(state.activeInterfaces.prefix(3)) { iface in
                            Button {
                                state.copyToClipboard(iface.ipAddress, label: iface.ipAddress)
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(iface.kind == .vpn
                                              ? Color(red: 0.30, green: 0.90, blue: 0.64)
                                              : Color(red: 0.74, green: 0.90, blue: 1.0))
                                        .frame(width: 5, height: 5)
                                    Text(iface.displayName)
                                        .font(.system(size: 9.2, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.88))
                                    Text(iface.ipAddress)
                                        .font(.system(size: 9.0, design: .monospaced))
                                        .foregroundColor(inkDim)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.04))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                // Active Bandwidth Apps (Parent-Grouped with Real App Icons)
                let activeApps = state.topProcesses.filter { $0.totalBytesPerSec >= 1_024 }
                if !activeApps.isEmpty {
                    VStack(spacing: 3.5) {
                        ForEach(activeApps.prefix(5)) { proc in
                            HStack(spacing: 8) {
                                AppProcessIconView(
                                    appBundlePath: proc.appBundlePath,
                                    pid: proc.pid,
                                    processName: proc.name,
                                    size: 16
                                )
                                Text(proc.name)
                                    .font(.system(size: 10.8, weight: .medium))
                                    .foregroundColor(.white.opacity(0.94))
                                    .lineLimit(1)
                                if proc.processCount > 1 {
                                    miniTag("\(proc.processCount) PROCS", color: Color.white.opacity(0.75))
                                }
                                Spacer()
                                Text("↓ \(ByteRateFormatter.menuBar(proc.downloadBytesPerSec))")
                                    .font(.system(size: 9.0, design: .monospaced))
                                    .foregroundColor(Color(red: 0.74, green: 0.90, blue: 1.0).opacity(0.9))
                                    .monospacedDigit()
                                Text("↑ \(ByteRateFormatter.menuBar(proc.uploadBytesPerSec))")
                                    .font(.system(size: 9.0, design: .monospaced))
                                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.48).opacity(0.9))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.032))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }

                // Live Outbound Sockets ("Who talks to whom")
                if state.connectionXRay.connections.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No outbound sockets captured yet.")
                            .font(.system(size: 10.8, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        Text("Live per-app socket inspection shows which remote hosts and services each app is talking to.")
                            .font(.system(size: 9.8))
                            .foregroundColor(inkDim)
                    }
                    .padding(.top, 6)
                } else {
                    VStack(spacing: 3.5) {
                        ForEach(state.connectionXRay.connections.prefix(40)) { conn in
                            HStack(spacing: 7.5) {
                                AppProcessIconView(
                                    appBundlePath: conn.appBundlePath,
                                    pid: conn.pid,
                                    processName: conn.appName,
                                    size: 15
                                )

                                Text(conn.appName)
                                    .font(.system(size: 10.6, weight: .medium))
                                    .foregroundColor(.white.opacity(0.94))
                                    .lineLimit(1)
                                    .frame(minWidth: 76, maxWidth: 112, alignment: .leading)

                                miniTag(
                                    conn.serviceLabel,
                                    color: conn.isPlaintextHTTP
                                        ? Color(red: 1.0, green: 0.48, blue: 0.44)
                                        : Color(red: 0.72, green: 0.86, blue: 1.0)
                                )

                                if conn.socketCount > 1 {
                                    Text("×\(conn.socketCount)")
                                        .font(.system(size: 8.6, weight: .semibold, design: .monospaced))
                                        .foregroundColor(inkDim)
                                }

                                Spacer()

                                Button {
                                    let endpoint = "\(conn.remoteHost):\(conn.remotePort)"
                                    state.copyToClipboard(endpoint, label: endpoint)
                                } label: {
                                    Text("\(conn.remoteHost):\(conn.remotePort)")
                                        .font(.system(size: 9.2, design: .monospaced))
                                        .foregroundColor(inkSoft)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .buttonStyle(.plain)
                                .help("Click to copy remote endpoint")
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(Color.white.opacity(0.022))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. Connection Event Timeline

    private var eventLogCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("CONNECTION EVENT LOG")
                    .font(.system(size: 9.0, weight: .semibold, design: .monospaced))
                    .foregroundColor(inkSoft)
                    .tracking(0.6)
                Spacer()
                Button {
                    state.explainStudioEvents()
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8.2, weight: .semibold))
                        Text(state.isExplainingEvents ? "Analyzing…" : "Explain")
                            .font(.system(size: 8.8, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.72, green: 0.90, blue: 1.0))
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.24), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .disabled(state.isExplainingEvents)
                .help("Summarize recent events & live stability on-device")

                Text("\(state.events.count) EVENTS")
                    .font(.system(size: 8.0, design: .monospaced))
                    .foregroundColor(inkDim)
            }

            if let summary = state.studioEventSummary {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(summary.usedOnDeviceModel ? "ON-DEVICE ANALYSIS" : "LOCAL ANALYSIS")
                            .font(.system(size: 7.6, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.88))
                            .tracking(0.5)
                        Text(summary.text)
                            .font(.system(size: 10.4))
                            .foregroundColor(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button {
                        state.studioEventSummary = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(inkDim)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.20), lineWidth: 0.8))
            }

            if state.events.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Everything steady — no roams or drops recorded yet.")
                        .font(.system(size: 11.2, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                    Text("Aether automatically records access point roams, 5G → 2.4G drops, latency spikes, upstream drops, VPN switches, and router changes.")
                        .font(.system(size: 10.2))
                        .foregroundColor(inkDim)
                }
                .padding(.top, 8)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 4) {
                        ForEach(state.events) { ev in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.timeFmt.string(from: ev.timestamp))
                                    .font(.system(size: 8.6, design: .monospaced))
                                    .foregroundColor(inkDim)
                                    .frame(width: 52, alignment: .leading)

                                Text(ev.kind.rawValue)
                                    .font(.system(size: 7.8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(eventColor(ev.severity))
                                    .frame(width: 54, alignment: .leading)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ev.title)
                                        .font(.system(size: 10.8, weight: .medium))
                                        .foregroundColor(.white.opacity(0.94))
                                    Text(ev.detail)
                                        .font(.system(size: 9.4))
                                        .foregroundColor(inkDim)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5.5)
                            .background(Color.white.opacity(0.025))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(specularBorder(radius: 12))
    }

    // MARK: - 5. Quiet On-Device "Ask Aether" Bar

    private var studioAskBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let ans = state.studioAnswer {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8.6, weight: .semibold))
                                .foregroundColor(Color(red: 0.72, green: 0.90, blue: 1.0))
                            Text(ans.usedOnDeviceModel ? "ON-DEVICE · \(ans.question.uppercased())" : "LOCAL · \(ans.question.uppercased())")
                                .font(.system(size: 8.0, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.9))
                                .lineLimit(1)
                        }
                        Text(ans.text)
                            .font(.system(size: 10.8))
                            .foregroundColor(.white.opacity(0.94))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 6) {
                        Button("Copy") {
                            state.copyToClipboard(ans.text, label: "Answer")
                        }
                        .font(.system(size: 9.2, weight: .medium))
                        .foregroundColor(inkSoft)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)

                        Button {
                            state.studioAnswer = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9.0, weight: .semibold))
                                .foregroundColor(inkDim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.22), lineWidth: 0.85)
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.85))

                TextField(
                    state.isOnDeviceAIAvailable
                        ? "Ask Aether on-device (e.g. “Can I take a Zoom call?” or “Write an ISP note”)…"
                        : "Ask Aether about this connection…",
                    text: $askInput
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11.0))
                .foregroundColor(.white)
                .onSubmit {
                    submitStudioQuestion()
                }

                if askInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 5) {
                        quickAskChip("Zoom ready?", prompt: "Can I take a video call right now?")
                        quickAskChip("Why slow?", prompt: "What is the main bottleneck slowing this connection down right now?")
                        quickAskChip("ISP note", prompt: "Write a concise factual summary of these network measurements that I can paste to my ISP or IT support.")
                    }
                } else {
                    Button(state.isAnsweringQuestion ? "Thinking…" : "Ask") {
                        submitStudioQuestion()
                    }
                    .font(.system(size: 9.8, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 11)
                    .frame(height: 23)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .disabled(state.isAnsweringQuestion)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(specularBorder(radius: 10, subtle: true))
        }
    }

    private func quickAskChip(_ label: String, prompt: String) -> some View {
        Button(label) {
            state.askAether(prompt)
        }
        .font(.system(size: 9.2, weight: .medium))
        .foregroundColor(inkSoft)
        .padding(.horizontal, 8.5)
        .frame(height: 22)
        .background(Color.white.opacity(0.055))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.11), lineWidth: 0.75))
        .buttonStyle(.plain)
        .disabled(state.isAnsweringQuestion)
    }

    private func submitStudioQuestion() {
        let q = askInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        askInput = ""
        state.askAether(q)
    }

    // MARK: - Helpers

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func specularBorder(radius: CGFloat, subtle: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(subtle ? 0.12 : 0.18),
                        Color.white.opacity(subtle ? 0.04 : 0.06),
                        Color.white.opacity(subtle ? 0.06 : 0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
    }

    private func physicsMetricCell(label: String, value: String, sub: String, accent: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2.5) {
            Text(label)
                .font(.system(size: 7.4, weight: .semibold, design: .monospaced))
                .foregroundColor(inkDim)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 12.0, weight: .semibold, design: .monospaced))
                .foregroundColor(accent.opacity(0.96))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 8.6))
                .foregroundColor(inkDim)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(specularBorder(radius: 9, subtle: true))
    }

    private func legendChip(color: Color, text: String) -> some View {
        HStack(spacing: 4.5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9.0, weight: .medium))
                .foregroundColor(inkSoft)
        }
    }

    private func miniTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 7.2, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
    }

    private func callGradeColor(_ grade: CallReadinessGrade) -> Color {
        switch grade {
        case .solid:   return Color(red: 0.28, green: 0.90, blue: 0.64)
        case .fair:    return Color(red: 1.00, green: 0.78, blue: 0.40)
        case .choppy:  return Color(red: 1.00, green: 0.44, blue: 0.40)
        case .offline: return Color.white.opacity(0.45)
        }
    }

    private func eventColor(_ sev: AuditSeverity) -> Color {
        switch sev {
        case .ok:      return Color(red: 0.28, green: 0.90, blue: 0.64)
        case .info:    return Color(red: 0.72, green: 0.88, blue: 1.0)
        case .caution: return Color(red: 1.00, green: 0.76, blue: 0.36)
        case .alert:   return Color(red: 1.00, green: 0.44, blue: 0.40)
        }
    }
}

// MARK: - Luminous Dual-Pass Gaussian RF Channel Spectrum Canvas

struct ChannelSpectrumCanvas: View {
    let lobes: [ChannelLobe]
    let band: WiFiBand
    var recommendedChannel: Int? = nil
    var compact: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let padL: CGFloat = compact ? 10 : 24
            let padR: CGFloat = compact ? 10 : 14
            let padT: CGFloat = compact ? 42 : 18
            let padB: CGFloat = compact ? 44 : 24
            let plotW = max(10, size.width - padL - padR)
            let plotH = max(10, size.height - padT - padB)
            let baseY = padT + plotH

            let (minCh, maxCh, axisTicks): (Double, Double, [Int]) = {
                switch band {
                case .band24:  return (-1.0, 14.0, [1, 3, 6, 9, 11, 13])
                case .band5:   return (30.0, 170.0, [36, 48, 64, 100, 132, 149, 161])
                case .band6:   return (1.0, 233.0, [1, 37, 69, 101, 149, 197])
                case .unknown: return (-1.0, 14.0, [1, 6, 11])
                }
            }()

            func xForChannel(_ ch: Double) -> CGFloat {
                let frac = (ch - minCh) / max(1, (maxCh - minCh))
                return padL + CGFloat(frac) * plotW
            }

            func yForRSSI(_ rssi: Int) -> CGFloat {
                let clamped = Double(min(max(rssi, -95), -30))
                let frac = (clamped + 95.0) / 65.0
                return baseY - CGFloat(frac) * plotH
            }

            for dbm in [-40, -65, -90] {
                let y = yForRSSI(dbm)
                var line = Path()
                line.move(to: CGPoint(x: padL, y: y))
                line.addLine(to: CGPoint(x: size.width - padR, y: y))
                ctx.stroke(line, with: .color(Color.white.opacity(dbm == -90 ? 0.14 : 0.05)), lineWidth: 0.7)
            }

            if let rec = recommendedChannel {
                let rx = xForChannel(Double(rec))
                var guide = Path()
                guide.move(to: CGPoint(x: rx, y: padT))
                guide.addLine(to: CGPoint(x: rx, y: baseY))
                ctx.stroke(
                    guide,
                    with: .color(Color(red: 0.28, green: 0.92, blue: 0.66).opacity(0.36)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [3, 3])
                )
            }

            let ordered = lobes.sorted { a, b in
                if a.isCurrent != b.isCurrent { return !a.isCurrent }
                return a.rssi < b.rssi
            }

            for lobe in ordered {
                let centerCh = Double(lobe.channel)
                let halfSpan: Double = {
                    if band == .band24 {
                        return lobe.widthMHz >= 40 ? 4.0 : 2.2
                    } else {
                        return max(2.2, Double(lobe.widthMHz) / 10.0)
                    }
                }()
                let peakY = yForRSSI(lobe.rssi)
                let lobeH = max(4, baseY - peakY)

                var curve = Path()
                let steps = 40
                for i in 0...steps {
                    let u = Double(i) / Double(steps)
                    let ch = (centerCh - halfSpan) + u * (halfSpan * 2.0)
                    let x = xForChannel(ch)
                    let shape = pow(sin(u * Double.pi), 1.35)
                    let y = baseY - CGFloat(shape) * lobeH
                    if i == 0 { curve.move(to: CGPoint(x: x, y: baseY)) }
                    curve.addLine(to: CGPoint(x: x, y: y))
                }
                curve.addLine(to: CGPoint(x: xForChannel(centerCh + halfSpan), y: baseY))

                var fillPath = curve
                fillPath.closeSubpath()

                let strokeColor: Color = lobe.isCurrent
                    ? Color(red: 0.30, green: 0.94, blue: 0.70)
                    : Color(red: 0.64, green: 0.80, blue: 1.0)

                ctx.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            strokeColor.opacity(lobe.isCurrent ? 0.36 : 0.13),
                            strokeColor.opacity(0.01)
                        ]),
                        startPoint: CGPoint(x: 0, y: peakY),
                        endPoint: CGPoint(x: 0, y: baseY)
                    )
                )

                // Dual-pass luminous bloom on the active Wi-Fi AP lobe
                if lobe.isCurrent {
                    ctx.stroke(curve, with: .color(strokeColor.opacity(0.28)), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
                    ctx.stroke(curve, with: .color(Color.white.opacity(0.94)), style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))

                    let peakX = xForChannel(centerCh)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: peakX - 2.6, y: peakY - 2.6, width: 5.2, height: 5.2)),
                        with: .color(.white)
                    )
                } else {
                    ctx.stroke(curve, with: .color(strokeColor.opacity(0.42)), style: StrokeStyle(lineWidth: 0.95, lineCap: .round, lineJoin: .round))
                }

                if !compact && (lobe.isCurrent || lobe.rssi >= -68) {
                    let lbl = Text(lobe.isCurrent ? "● \(lobe.ssid)" : lobe.ssid)
                        .font(.system(size: 8.4, weight: lobe.isCurrent ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(lobe.isCurrent ? .white : Color.white.opacity(0.54))
                    ctx.draw(lbl, at: CGPoint(x: xForChannel(centerCh), y: max(padT + 6, peakY - 9)), anchor: .center)
                }
            }

            for ch in axisTicks {
                let x = xForChannel(Double(ch))
                let isRec = (ch == recommendedChannel)
                let t = Text("\(ch)")
                    .font(.system(size: compact ? 7.8 : 8.5, weight: isRec ? .bold : .regular, design: .monospaced))
                    .foregroundColor(isRec ? Color(red: 0.30, green: 0.94, blue: 0.68) : Color.white.opacity(0.42))
                ctx.draw(t, at: CGPoint(x: x, y: baseY + 10), anchor: .center)
            }
        }
    }
}

// MARK: - Interactive Multi-Hop Latency & Drop Timeline Canvas (With Hover Crosshair!)

struct LatencyTimelineCanvas: View {
    let samples: [LatencySample]
    @State private var hoverLocation: CGPoint?

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let padL: CGFloat = 28
                    let padR: CGFloat = 10
                    let padT: CGFloat = 14
                    let padB: CGFloat = 16
                    let plotW = max(10, size.width - padL - padR)
                    let plotH = max(10, size.height - padT - padB)
                    let baseY = padT + plotH

                    let maxMs = max(
                        50.0,
                        samples.compactMap { max($0.internetMs ?? 0, max($0.dnsMs ?? 0, $0.routerMs ?? 0)) }.max() ?? 50.0
                    ) * 1.15

                    for frac in [0.0, 0.5, 1.0] as [CGFloat] {
                        let y = baseY - frac * plotH
                        var line = Path()
                        line.move(to: CGPoint(x: padL, y: y))
                        line.addLine(to: CGPoint(x: size.width - padR, y: y))
                        ctx.stroke(line, with: .color(Color.white.opacity(frac == 0 ? 0.14 : 0.06)), lineWidth: 0.7)

                        let val = Int(round(Double(frac) * maxMs))
                        let lbl = Text("\(val)")
                            .font(.system(size: 7.8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        ctx.draw(lbl, at: CGPoint(x: padL - 5, y: y), anchor: .trailing)
                    }

                    guard samples.count >= 2 else {
                        let hint = Text("Collecting live hop latency samples…")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.38))
                        ctx.draw(hint, at: CGPoint(x: size.width * 0.5, y: size.height * 0.5), anchor: .center)
                        return
                    }

                    func xAt(_ i: Int) -> CGFloat {
                        padL + (CGFloat(i) / CGFloat(samples.count - 1)) * plotW
                    }

                    func yFor(_ ms: Double) -> CGFloat {
                        baseY - CGFloat(min(1.0, max(0.0, ms / maxMs))) * plotH
                    }

                    for (i, s) in samples.enumerated() where s.isDrop {
                        let x = xAt(i)
                        var bar = Path()
                        bar.move(to: CGPoint(x: x, y: padT))
                        bar.addLine(to: CGPoint(x: x, y: baseY))
                        ctx.stroke(bar, with: .color(Color(red: 1.0, green: 0.36, blue: 0.34).opacity(0.65)), lineWidth: 2.0)
                    }

                    func drawSeries(_ extractor: (LatencySample) -> Double?, color: Color, lineWidth: CGFloat, bloom: Bool = false) {
                        var p = Path()
                        var started = false
                        for (i, s) in samples.enumerated() {
                            if let v = extractor(s) {
                                let pt = CGPoint(x: xAt(i), y: yFor(v))
                                if !started {
                                    p.move(to: pt)
                                    started = true
                                } else {
                                    p.addLine(to: pt)
                                }
                            } else {
                                started = false
                            }
                        }
                        if bloom {
                            ctx.stroke(p, with: .color(color.opacity(0.24)), style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round))
                        }
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    }

                    drawSeries(\.routerMs, color: Color(red: 0.34, green: 0.90, blue: 0.66).opacity(0.78), lineWidth: 1.15)
                    drawSeries(\.dnsMs, color: Color(red: 1.0, green: 0.80, blue: 0.50).opacity(0.72), lineWidth: 1.15)
                    drawSeries(\.internetMs, color: Color(red: 0.82, green: 0.95, blue: 1.0).opacity(0.96), lineWidth: 1.65, bloom: true)

                    // Interactive hover crosshair vertical hairline + active sample dots
                    if let hIdx = hoveredSampleIndex(in: size) {
                        let hx = xAt(hIdx)
                        var crosshair = Path()
                        crosshair.move(to: CGPoint(x: hx, y: padT))
                        crosshair.addLine(to: CGPoint(x: hx, y: baseY))
                        ctx.stroke(crosshair, with: .color(Color.white.opacity(0.32)), style: StrokeStyle(lineWidth: 0.9, dash: [2.5, 2.5]))

                        let sample = samples[hIdx]
                        if let w = sample.internetMs {
                            let pt = CGPoint(x: hx, y: yFor(w))
                            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3.2, y: pt.y - 3.2, width: 6.4, height: 6.4)), with: .color(.white))
                        }
                    }
                }

                // Floating frosted inspection badge on hover
                if let hIdx = hoveredSampleIndex(in: geo.size) {
                    let s = samples[hIdx]
                    let badgeText = "\(Self.timeFmt.string(from: s.timestamp))  ·  R \(ByteRateFormatter.ms(s.routerMs))  ·  D \(ByteRateFormatter.ms(s.dnsMs))  ·  W \(s.isDrop ? "DROP" : ByteRateFormatter.ms(s.internetMs))"
                    Text(badgeText)
                        .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.95))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Color.black.opacity(0.78))
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
                        .padding(.top, 8)
                        .padding(.leading, 34)
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt): hoverLocation = pt
                case .ended: hoverLocation = nil
                }
            }
        }
    }

    private func hoveredSampleIndex(in size: CGSize) -> Int? {
        guard let pt = hoverLocation, samples.count >= 2 else { return nil }
        let padL: CGFloat = 28
        let padR: CGFloat = 10
        let plotW = max(10, size.width - padL - padR)
        let frac = min(1.0, max(0.0, (pt.x - padL) / plotW))
        let idx = Int(round(frac * CGFloat(samples.count - 1)))
        return min(max(idx, 0), samples.count - 1)
    }
}
