import AetherCore
import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenStudio: () -> Void
    let onQuit: () -> Void
    var onRequestResize: (() -> Void)? = nil

    @State private var passwordPromptSSID: String?
    @State private var passwordInput: String = ""
    @State private var privacyDetailSection: PrivacyDetailSection = .none
    @State private var insightIndex: Int = 0

    @Namespace private var trustZoneNS
    @Namespace private var dnsPresetNS
    @Namespace private var detailModeNS
    @Namespace private var menuBarModeNS

    private enum PrivacyDetailSection {
        case none, lanDevices, technicalAudit
    }

    private let hairSoft = Color.white.opacity(0.085)
    private let inkSoft = Color.white.opacity(0.75)
    private let inkDim = Color.white.opacity(0.45)

    var body: some View {
        VStack(spacing: 12) {
            if state.isDisconnected {
                disconnectedHeader

                if state.showSettingsWhileDisconnected {
                    VStack(alignment: .leading, spacing: 11) {
                        morePanel
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.036))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(cardRimOverlay(cornerRadius: 11))
                } else {
                    disconnectedWiFiCard
                }
            } else {
                // 1. Full-Bleed OLED Instrument Stage (FLUX / SPECTRUM / ROUTE) + ↗ Studio Expand
                InstrumentStageView(state: state, onOpenStudio: onOpenStudio)

                // Captive Portal Alert Bar (only shown when intercepted by hotel/airport portal)
                if state.captivePortal.isDetected {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.72, blue: 0.30))
                            .frame(width: 6, height: 6)
                            .shadow(color: Color(red: 1.0, green: 0.72, blue: 0.30).opacity(0.7), radius: 3)
                        Text("Wi-Fi sign-in required")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.95))
                        Spacer()
                        Button("Sign In") { state.openCaptivePortal() }
                            .font(.system(size: 9.6, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(Color(red: 1.0, green: 0.72, blue: 0.30).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(red: 1.0, green: 0.72, blue: 0.30).opacity(0.36), lineWidth: 1))
                }

                // 2. Relatable 4-Step Connection Health Chain (Wi-Fi › Router › Lookup › Internet)
                hopHealthStrip

                // Calm Upstream-Down Diagnosis (when router responds but ISP/portal blocks internet)
                if state.isUpstreamDown && !state.captivePortal.isDetected {
                    HStack(spacing: 8) {
                        Circle().fill(Color(red: 1.0, green: 0.72, blue: 0.30)).frame(width: 5.5, height: 5.5)
                        Text("Router is up, but internet isn't responding")
                            .font(.system(size: 10.0, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer()
                        Button("Check Sign-In") { state.checkCaptivePortalManually() }
                            .buttonStyle(AetherHairlineButtonStyle())
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color(red: 1.0, green: 0.72, blue: 0.30).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(red: 1.0, green: 0.72, blue: 0.30).opacity(0.28), lineWidth: 1))
                }

                // One-Time Calm Setup Strip (disappears permanently on dismiss or once Location is granted)
                if state.shouldShowOnboardingStrip {
                    onboardingStrip
                        .transition(.opacity)
                }

                // 3. Four Sculpted Circular Mode Glyphs (SPEED · PRIVACY · WI-FI · MORE)
                HStack(spacing: 0) {
                    ForEach(PanelTab.allCases) { tab in
                        let isActive = state.activeTab == tab
                        Button {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                                state.selectTab(tab)
                            }
                        } label: {
                            VStack(spacing: 5) {
                                AetherTabGlyph(
                                    tab: tab,
                                    isActive: isActive,
                                    badgeColor: badgeColor(for: tab),
                                    size: 38
                                )
                                Text(tab.shortLabel)
                                    .font(.system(size: 8.4, weight: isActive ? .semibold : .regular, design: .monospaced))
                                    .foregroundColor(isActive ? .white : inkDim)
                                    .tracking(0.55)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("\(tab.help) (⌘\(tab.rawValue + 1))")
                        .accessibilityLabel(tab.shortLabel)
                        .accessibilityHint(tab.help)
                        .accessibilityAddTraits(isActive ? [.isSelected] : [])
                    }
                }
                .padding(.top, 1)

                // 4. Focused Active Instrument Card
                activeTabCard
            }

            // 5. Transient Status Banner
            if let banner = state.statusBanner {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.32, green: 0.92, blue: 0.66))
                        .frame(width: 4.5, height: 4.5)
                    Text(banner)
                        .font(.system(size: 10.2, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(hairSoft, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if state.isStatusItemBehindNotch {
                Text("⌘-drag Aether right of the camera notch to keep it visible")
                    .font(.system(size: 9.2))
                    .foregroundColor(inkDim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 396)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.036, green: 0.041, blue: 0.050),
                    Color(red: 0.026, green: 0.030, blue: 0.038)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            // Anodized sapphire-glass specular rim on outer chassis
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.08), Color.white.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - 4-Step Human Connection Chain

    private var hopHealthStrip: some View {
        HoverSurfaceButton {
            withAnimation(.easeInOut(duration: 0.2)) {
                state.stageMode = .route
            }
            state.performHaptic()
        } content: {
            HStack(spacing: 0) {
                hopCell(
                    label: state.isProMode ? "LINK" : "WI-FI",
                    value: state.isProMode
                        ? (state.wifi.isConnected ? "\(state.wifi.snr)dB" : (state.isWired ? "WIRE" : "—"))
                        : HumanSummary.humanSignalLabel(wifi: state.wifi, isWired: state.isWired),
                    color: linkQualityColor
                )
                hopChevron
                hopCell(
                    label: "ROUTER",
                    value: state.isProMode
                        ? ByteRateFormatter.ms(state.hopHealth.routerMs)
                        : HumanSummary.humanHopLabel(ms: state.hopHealth.routerMs, warn: 25, bad: 60),
                    color: latencyColor(state.hopHealth.routerMs, warn: 25, bad: 60)
                )
                hopChevron
                hopCell(
                    label: state.isProMode ? "DNS" : "LOOKUP",
                    value: state.isProMode
                        ? ByteRateFormatter.ms(state.hopHealth.dnsMs)
                        : HumanSummary.humanHopLabel(ms: state.hopHealth.dnsMs, warn: 55, bad: 120),
                    color: latencyColor(state.hopHealth.dnsMs, warn: 55, bad: 120)
                )
                hopChevron
                hopCell(
                    label: state.isProMode ? "WEB" : "INTERNET",
                    value: state.isProMode
                        ? ByteRateFormatter.ms(state.hopHealth.internetMs)
                        : HumanSummary.humanHopLabel(ms: state.hopHealth.internetMs, warn: 70, bad: 150),
                    color: latencyColor(state.hopHealth.internetMs, warn: 70, bad: 150)
                )
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
        }
        .help("\(state.hopHealth.bottleneckSummary) · Click to view live route")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection path")
        .accessibilityValue("Wi-Fi \(HumanSummary.humanSignalLabel(wifi: state.wifi, isWired: state.isWired)), Router \(HumanSummary.humanHopLabel(ms: state.hopHealth.routerMs, warn: 25, bad: 60)), Lookup \(HumanSummary.humanHopLabel(ms: state.hopHealth.dnsMs, warn: 55, bad: 120)), Internet \(HumanSummary.humanHopLabel(ms: state.hopHealth.internetMs, warn: 70, bad: 150))")
        .accessibilityHint("Switch hero visualization to Route view")
    }

    private func hopCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1.5) {
            Text(label)
                .font(.system(size: 7.4, weight: .semibold, design: .monospaced))
                .foregroundColor(inkDim)
                .tracking(0.5)
            Text(value)
                .font(state.isProMode
                      ? .system(size: 10.4, weight: .semibold, design: .monospaced)
                      : .system(size: 10.6, weight: .medium))
                .foregroundColor(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private var hopChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7.5, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.20))
    }

    // MARK: - Calm One-Time First-Run Setup Strip

    private var onboardingStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Make Aether your Wi-Fi bar")
                    .font(.system(size: 10.6, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { state.dismissOnboarding() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(inkDim)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss setup banner")
            }

            HStack(spacing: 6) {
                Button {
                    state.requestLocationAccess()
                } label: {
                    Text(state.needsManualLocationSettings ? "Open Location Settings" : "Show Wi-Fi Names")
                        .font(.system(size: 9.6, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 25)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    state.openControlCenterSettings()
                } label: {
                    Text("Hide Apple Wi-Fi")
                        .font(.system(size: 9.6, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                        .frame(maxWidth: .infinity)
                        .frame(height: 25)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6.5, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.048))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: - Disconnected-First Wi-Fi Picker Experience

    private var disconnectedHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white.opacity(0.13), lineWidth: 1))
                Image(systemName: state.wifi.powerOn ? "wifi" : "wifi.slash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(state.wifi.powerOn ? .white.opacity(0.92) : inkDim)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.wifi.powerOn ? "Join Wi-Fi" : "Wi-Fi Off")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(disconnectedSubtitle)
                    .font(.system(size: 8.6, weight: .medium, design: .monospaced))
                    .foregroundColor(inkDim)
                    .tracking(0.45)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if state.wifi.powerOn && !state.showSettingsWhileDisconnected {
                    Button {
                        Task { await state.scanNearbyNetworks() }
                    } label: {
                        Group {
                            if state.isScanningNetworks {
                                ProgressView().controlSize(.mini).scaleEffect(0.65)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.84))
                            }
                        }
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isScanningNetworks)
                    .help("Scan for nearby Wi-Fi networks (R)")
                    .accessibilityLabel("Scan nearby Wi-Fi networks")
                }

                Button {
                    state.toggleWiFiPower()
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(state.wifi.powerOn ? .white.opacity(0.88) : Color(red: 1.0, green: 0.45, blue: 0.40))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(state.wifi.powerOn ? "Turn Wi-Fi Off" : "Turn Wi-Fi On")
                .accessibilityLabel(state.wifi.powerOn ? "Turn Wi-Fi Off" : "Turn Wi-Fi On")

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        state.showSettingsWhileDisconnected.toggle()
                    }
                    state.performHaptic()
                    DispatchQueue.main.async { onRequestResize?() }
                } label: {
                    Image(systemName: state.showSettingsWhileDisconnected ? "wifi" : "slider.horizontal.3")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(state.showSettingsWhileDisconnected ? .black : .white.opacity(0.84))
                        .frame(width: 26, height: 26)
                        .background(state.showSettingsWhileDisconnected ? Color.white : Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(state.showSettingsWhileDisconnected ? Color.clear : Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(state.showSettingsWhileDisconnected ? "Back to Wi-Fi Networks" : "Settings & Tools")
                .accessibilityLabel(state.showSettingsWhileDisconnected ? "Back to Wi-Fi Networks" : "Settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color(red: 0.048, green: 0.056, blue: 0.070), Color(red: 0.024, green: 0.028, blue: 0.036)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(cardRimOverlay(cornerRadius: 11))
    }

    private var disconnectedSubtitle: String {
        if !state.wifi.powerOn { return "RADIO POWERED OFF" }
        if state.isScanningNetworks { return "SCANNING AIRWAVES…" }
        if !state.nearbyNetworks.isEmpty {
            let n = state.nearbyNetworks.count
            return "\(n) \(n == 1 ? "NETWORK" : "NETWORKS") NEARBY"
        }
        if !state.rawScanBSSIDs.isEmpty {
            let n = state.rawScanBSSIDs.count
            return "\(n) \(n == 1 ? "SIGNAL" : "SIGNALS") IN RANGE · NAMES HIDDEN"
        }
        return "NOT CONNECTED"
    }

    private var disconnectedWiFiCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !state.wifi.powerOn {
                VStack(spacing: 9) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(Color.white.opacity(0.58))
                    Text("Wi-Fi is turned off")
                        .font(.system(size: 12.6, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    Text("Turn Wi-Fi on to scan and join nearby networks.")
                        .font(.system(size: 9.8))
                        .foregroundColor(inkDim)
                        .multilineTextAlignment(.center)
                    Button("Turn Wi-Fi On") {
                        state.toggleWiFiPower()
                    }
                    .font(.system(size: 10.4, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 29)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else {
                if !state.hasLocationAccess {
                    locationPermissionCard(compact: false)
                }

                if !state.nearbyNetworks.isEmpty {
                    nearbyNetworksList(maxHeight: 268, limit: 16)
                } else if state.hasLocationAccess {
                    HStack(spacing: 8) {
                        if state.isScanningNetworks {
                            ProgressView().controlSize(.small).scaleEffect(0.72)
                            Text("Scanning for nearby Wi-Fi networks…")
                                .font(.system(size: 10.4))
                                .foregroundColor(inkSoft)
                        } else {
                            Text("No Wi-Fi networks found in range.")
                                .font(.system(size: 10.4))
                                .foregroundColor(inkDim)
                            Spacer()
                            Button("Scan Again") { Task { await state.scanNearbyNetworks() } }
                                .buttonStyle(AetherHairlineButtonStyle())
                        }
                    }
                    .padding(.vertical, 10)
                }

                // Fallback: macOS exposes saved profile names even before Location Services is granted!
                if state.nearbyNetworks.isEmpty && !state.knownSSIDs.isEmpty {
                    savedNetworksSection(maxHeight: 175)
                }

                if let err = state.connectionError {
                    Text(err)
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.52))
                }
            }

            Divider().background(hairSoft)

            HStack(spacing: 12) {
                Button("MACOS WI-FI ↗") { state.openWiFiSettings() }
                    .buttonStyle(QuietFooterLinkStyle(active: true))
                    .help("Open macOS Wi-Fi Settings")

                Button("STUDIO ↗") { onOpenStudio() }
                    .buttonStyle(QuietFooterLinkStyle())

                Spacer()

                Button("QUIT") { onQuit() }
                    .buttonStyle(QuietFooterLinkStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.036))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(cardRimOverlay(cornerRadius: 11))
    }

    private func locationPermissionCard(compact: Bool) -> some View {
        let signalCount = state.rawScanBSSIDs.count
        let title: String = {
            if signalCount > 0 {
                return "\(signalCount) Wi-Fi \(signalCount == 1 ? "signal" : "signals") nearby — names hidden"
            }
            return "Show Wi-Fi Names"
        }()
        let subtitle: String = {
            if !state.locationServicesEnabled {
                return "Location Services is turned off in System Settings. Enable it to list nearby Wi-Fi names."
            }
            if state.locationAuthStatus == .denied || state.locationAuthStatus == .restricted {
                return "Location permission for Aether is off. Turn it on in Privacy & Security → Location Services."
            }
            return "macOS requires Location permission to reveal nearby Wi-Fi names. Location data never leaves your Mac."
        }()

        return VStack(alignment: .leading, spacing: compact ? 6.5 : 8) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(.system(size: compact ? 10.6 : 11.2, weight: .semibold))
                    .foregroundColor(.white.opacity(0.96))
                Text(subtitle)
                    .font(.system(size: 9.4))
                    .foregroundColor(inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Button {
                    state.requestLocationAccess()
                } label: {
                    Text(state.needsManualLocationSettings ? "Open Location Settings" : "Continue")
                        .font(.system(size: 9.8, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                }
                .buttonStyle(.plain)

                if !state.needsManualLocationSettings {
                    Button {
                        state.openLocationSettings()
                    } label: {
                        Text("Settings")
                            .font(.system(size: 9.6, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6.5, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Open Privacy & Security → Location Services")
                }
            }
        }
        .padding(9.5)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8.5, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }

    private func savedNetworksSection(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("KNOWN NETWORKS")
                    .font(.system(size: 7.8, weight: .semibold, design: .monospaced))
                    .foregroundColor(inkDim)
                    .tracking(0.55)
                Spacer()
                Text("1-CLICK JOIN")
                    .font(.system(size: 7.4, weight: .medium, design: .monospaced))
                    .foregroundColor(inkDim)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(state.knownSSIDs.prefix(12), id: \.self) { ssid in
                        VStack(spacing: 6) {
                            HoverSurfaceButton(cornerRadius: 7.5) {
                                Task {
                                    let ok = await state.connectToNetwork(ssid: ssid, password: nil)
                                    if !ok, let err = state.connectionError, !err.localizedCaseInsensitiveContains("not in range") {
                                        passwordInput = ""
                                        passwordPromptSSID = ssid
                                        DispatchQueue.main.async { onRequestResize?() }
                                    }
                                }
                            } content: {
                                HStack(spacing: 8) {
                                    Image(systemName: "wifi")
                                        .font(.system(size: 9.8, weight: .medium))
                                        .foregroundColor(inkSoft)
                                    Text(ssid)
                                        .font(.system(size: 11.0, weight: .regular))
                                        .foregroundColor(.white.opacity(0.90))
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    if state.connectingSSID == ssid {
                                        ProgressView().controlSize(.mini).scaleEffect(0.7)
                                    } else {
                                        Text("Join")
                                            .font(.system(size: 9.0, weight: .medium))
                                            .foregroundColor(inkDim)
                                    }
                                }
                                .padding(.horizontal, 8.5)
                                .frame(height: 29)
                            }

                            if passwordPromptSSID == ssid {
                                HStack(spacing: 6) {
                                    SecureField("Wi-Fi password", text: $passwordInput)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11))
                                        .padding(.horizontal, 8)
                                        .frame(height: 27)
                                        .background(Color.black.opacity(0.48))
                                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 6.5, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
                                        .onSubmit { submitPasswordConnect(ssid: ssid) }

                                    Button("Join") { submitPasswordConnect(ssid: ssid) }
                                        .font(.system(size: 9.6, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 11)
                                        .frame(height: 27)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                                        .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: maxHeight)
        }
    }

    private func nearbyNetworksList(maxHeight: CGFloat, limit: Int) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(state.nearbyNetworks.prefix(limit)) { net in
                    let isKnown = state.knownSSIDs.contains(net.ssid)
                    VStack(spacing: 6) {
                        HoverSurfaceButton(cornerRadius: 7.5, highlighted: net.isCurrent) {
                            handleNetworkTap(net)
                        } content: {
                            HStack(spacing: 8) {
                                MiniSignalBars(bars: net.signalBars)

                                Text(net.ssid)
                                    .font(.system(size: 11.2, weight: net.isCurrent ? .semibold : .regular))
                                    .foregroundColor(net.isCurrent ? .white : Color.white.opacity(0.88))
                                    .lineLimit(1)

                                if net.isCurrent {
                                    Circle()
                                        .fill(Color(red: 0.28, green: 0.90, blue: 0.64))
                                        .frame(width: 5, height: 5)
                                        .shadow(color: Color(red: 0.28, green: 0.90, blue: 0.64).opacity(0.7), radius: 2.5)
                                } else if isKnown && !state.isProMode {
                                    Text("Saved")
                                        .font(.system(size: 8.0, weight: .medium))
                                        .foregroundColor(inkDim)
                                }

                                Spacer(minLength: 4)

                                if state.connectingSSID == net.ssid {
                                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                                } else {
                                    Text(net.band.shortBadge)
                                        .font(.system(size: 8.0, weight: .semibold, design: .monospaced))
                                        .foregroundColor(net.band == .band6 || net.band == .band5 ? Color(red: 0.72, green: 0.88, blue: 1.0) : inkDim)
                                        .padding(.horizontal, 4.5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                                    if net.security == .open {
                                        Text("Open")
                                            .font(.system(size: 8.6, weight: .medium))
                                            .foregroundColor(Color(red: 1.0, green: 0.54, blue: 0.50))
                                    } else {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8.4))
                                            .foregroundColor(inkDim)
                                    }

                                    if state.isProMode {
                                        Text("\(net.rssi)")
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .foregroundColor(inkDim)
                                            .frame(width: 24, alignment: .trailing)
                                    }
                                }
                            }
                            .padding(.horizontal, 8.5)
                            .frame(height: 30)
                        }

                        if passwordPromptSSID == net.ssid {
                            HStack(spacing: 6) {
                                SecureField("Wi-Fi password", text: $passwordInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .frame(height: 27)
                                    .background(Color.black.opacity(0.48))
                                    .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 6.5, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
                                    .onSubmit { submitPasswordConnect(ssid: net.ssid) }

                                Button("Join") { submitPasswordConnect(ssid: net.ssid) }
                                    .font(.system(size: 9.6, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 11)
                                    .frame(height: 27)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                                    .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: maxHeight)
    }

    private func cardRimOverlay(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.06), Color.white.opacity(0.09)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
    }

    // MARK: - Active Tab Card Container

    @ViewBuilder
    private var activeTabCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            switch state.activeTab {
            case .speed:
                speedPanel
            case .shield:
                privacyPanel
            case .networks:
                wifiPanel
            case .tools:
                morePanel
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.036))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.06), Color.white.opacity(0.09)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - TAB 1: SPEED (Tight, Zero-Redundancy Satie Proportions + Graceful Offline States)

    private var speedPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !state.wifi.isConnected && !state.isWired {
                // Intentional, serene offline empty state
                VStack(spacing: 8) {
                    Image(systemName: state.wifi.powerOn ? "wifi.exclamationmark" : "wifi.slash")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(Color.white.opacity(0.65))
                    Text(state.wifi.powerOn ? "Not connected to a network" : "Wi-Fi is turned off")
                        .font(.system(size: 12.2, weight: .semibold))
                        .foregroundColor(.white.opacity(0.94))
                    Text(state.wifi.powerOn
                         ? "Pick a nearby Wi-Fi network or plug in Ethernet to see live speed, call quality, and privacy posture."
                         : "Turn Wi-Fi back on to inspect signal strength, speed, and nearby networks.")
                        .font(.system(size: 9.8))
                        .foregroundColor(inkDim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(state.wifi.powerOn ? "Choose Wi-Fi" : "Turn Wi-Fi On") {
                        if state.wifi.powerOn {
                            state.selectTab(.networks)
                            Task { await state.scanNearbyNetworks() }
                        } else {
                            state.toggleWiFiPower()
                        }
                    }
                    .font(.system(size: 10.2, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            } else {
            // 1. Three Relatable Activity Readiness Cards (Video Calls · 4K Video · Live & Games)
            HStack(spacing: 6) {
                ForEach(state.activityReadiness) { item in
                    let accent = readinessColor(item.status)
                    ZStack(alignment: .topLeading) {
                        RadialGradient(
                            colors: [accent.opacity(0.11), Color.clear],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 72
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4.5) {
                                Image(systemName: readinessIcon(for: item.id))
                                    .font(.system(size: 8.6, weight: .semibold))
                                    .foregroundColor(accent)
                                Text(item.activity)
                                    .font(.system(size: 8.8, weight: .medium))
                                    .foregroundColor(inkDim)
                                    .lineLimit(1)
                            }
                            Text(item.verdict)
                                .font(.system(size: 11.6, weight: .semibold))
                                .foregroundColor(.white.opacity(0.96))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.032))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(accent.opacity(0.18), lineWidth: 0.9))
                    .help(item.detail)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.activity)
                    .accessibilityValue("\(item.verdict). \(item.detail)")
                }
            }

            // 2. Editorial "Behind the Signal" Pull-Quote Card (tap to cycle live measured RF facts)
            let insights = state.signalInsights
            if !insights.isEmpty {
                let idx = insightIndex % insights.count
                let insight = insights[idx]
                HoverSurfaceButton(cornerRadius: 8.5) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        insightIndex = (insightIndex + 1) % max(1, insights.count)
                    }
                    state.performHaptic()
                } content: {
                    HStack(alignment: .top, spacing: 9) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.72))
                            .frame(width: 2.2)
                            .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 2.5) {
                            HStack {
                                Text(insight.eyebrow)
                                    .font(.system(size: 7.4, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.74, green: 0.90, blue: 1.0).opacity(0.88))
                                    .tracking(0.6)
                                Spacer()
                                if insights.count > 1 {
                                    HStack(spacing: 3.5) {
                                        ForEach(0..<insights.count, id: \.self) { dot in
                                            Circle()
                                                .fill(Color.white.opacity(dot == idx ? 0.85 : 0.22))
                                                .frame(width: dot == idx ? 4.5 : 3.5, height: dot == idx ? 4.5 : 3.5)
                                        }
                                    }
                                }
                            }
                            Text(insight.headline)
                                .font(.system(size: 10.8, weight: .medium))
                                .foregroundColor(.white.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(insight.footnote)
                                .font(.system(size: 9.2))
                                .foregroundColor(inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .help("Tap to cycle live radio insights")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(insight.eyebrow): \(insight.headline)")
                .accessibilityValue(insight.footnote)
                .accessibilityHint("Activate to read next live signal insight")
            }

            // 3. Sleek 1-Row Speed & Call Test Strip (expands cleanly only while testing or showing results)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.isProMode ? "RESPONSIVENESS & SPEED" : "Speed & Call Test")
                            .font(state.isProMode
                                  ? .system(size: 8.6, weight: .semibold, design: .monospaced)
                                  : .system(size: 10.8, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                        Text(state.qualityResult?.plainEnglishVerdict ?? "Measures real throughput & bufferbloat under load")
                            .font(.system(size: 9.3))
                            .foregroundColor(inkDim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button {
                        state.runQualityTest()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: state.isRunningQualityTest ? "waveform" : "bolt.fill")
                                .font(.system(size: 8.8, weight: .semibold))
                            Text(state.isRunningQualityTest ? "Testing…" : "Run Test")
                                .font(.system(size: 9.6, weight: .semibold))
                        }
                        .foregroundColor(state.isRunningQualityTest ? .white.opacity(0.9) : .black)
                        .padding(.horizontal, 11)
                        .frame(height: 25)
                        .background(state.isRunningQualityTest ? Color.white.opacity(0.12) : Color.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isRunningQualityTest)
                    .help("Run Apple networkQuality speed & responsiveness test (Space)")
                }

                if state.isRunningQualityTest {
                    IndeterminateShimmerBar()
                        .frame(height: 3)
                } else if let q = state.qualityResult {
                    HStack(spacing: 6) {
                        miniStatPill(label: "DOWNLOAD", value: String(format: "%.0f Mbps", q.downloadMbps))
                        miniStatPill(label: "UPLOAD", value: String(format: "%.0f Mbps", q.uploadMbps))
                        miniStatPill(
                            label: state.isProMode ? "RPM" : "SMOOTHNESS",
                            value: state.isProMode ? "\(q.responsivenessRPM) \(q.responsivenessRating)" : q.responsivenessRating.capitalized,
                            highlight: q.responsivenessRPM < 300 ? Color(red: 1.0, green: 0.72, blue: 0.34) : Color(red: 0.32, green: 0.90, blue: 0.64)
                        )
                    }
                }
            }
            .padding(.top, 2)

            // 4. Pulse-grade Session Traffic, Active Interfaces & Parent-Grouped App Bandwidth
            Divider().background(hairSoft)

            VStack(alignment: .leading, spacing: 8) {
                // 4a. Session Totals Strip: Received · Sent · Peak
                HStack(spacing: 0) {
                    sessionMetricColumn(
                        label: "Received",
                        value: ByteRateFormatter.totalBytes(state.sessionDownBytes)
                    )
                    sessionMetricColumn(
                        label: "Sent",
                        value: ByteRateFormatter.totalBytes(state.sessionUpBytes)
                    )
                    sessionMetricColumn(
                        label: "Peak",
                        value: state.sessionPeakBytesPerSec >= 1_024
                            ? ByteRateFormatter.menuBar(state.sessionPeakBytesPerSec)
                            : "—"
                    )
                }

                // 4b. Active Interfaces (Wi-Fi / Ethernet / VPN with click-to-copy live IPs)
                if !state.activeInterfaces.isEmpty {
                    VStack(alignment: .leading, spacing: 3.5) {
                        Text(state.isProMode ? "INTERFACES" : "Interfaces")
                            .font(state.isProMode
                                  ? .system(size: 8.0, weight: .semibold, design: .monospaced)
                                  : .system(size: 9.8, weight: .semibold))
                            .foregroundColor(inkDim)
                        ForEach(state.activeInterfaces.prefix(3)) { iface in
                            Button {
                                state.copyToClipboard(iface.ipAddress, label: iface.ipAddress)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: interfaceSymbol(iface.kind))
                                        .font(.system(size: 10.2, weight: .medium))
                                        .foregroundColor(iface.kind == .vpn
                                                         ? Color(red: 0.34, green: 0.90, blue: 0.66)
                                                         : inkSoft)
                                        .frame(width: 14, alignment: .center)
                                    Text(iface.displayName)
                                        .font(.system(size: 10.6, weight: .medium))
                                        .foregroundColor(.white.opacity(0.92))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(iface.ipAddress)
                                        .font(.system(size: 10.0, weight: .regular, design: .monospaced))
                                        .foregroundColor(inkSoft)
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Click to copy \(iface.displayName) IP (\(iface.bsdName))")
                        }
                    }
                }

                // 4c. Live Parent-Grouped Processes with Real macOS App Icons (shows active apps >= 1 KB/s)
                let activeApps = state.topProcesses.filter { $0.totalBytesPerSec >= 1_024 }
                if !activeApps.isEmpty {
                    VStack(alignment: .leading, spacing: 4.5) {
                        HStack {
                            Text(state.isProMode ? "PROCESSES" : "Processes")
                                .font(state.isProMode
                                      ? .system(size: 8.0, weight: .semibold, design: .monospaced)
                                      : .system(size: 9.8, weight: .semibold))
                                .foregroundColor(inkDim)
                            Spacer()
                            Button("Connections ↗") {
                                state.studioFocusConnections = true
                                onOpenStudio()
                            }
                            .buttonStyle(QuietFooterLinkStyle())
                        }

                        let maxRate = max(activeApps.first?.totalBytesPerSec ?? 1, 1)
                        VStack(spacing: 4.5) {
                            ForEach(activeApps.prefix(5)) { proc in
                                let displayName = proc.appBundlePath != nil
                                    ? proc.name
                                    : (state.isProMode ? proc.name : HumanSummary.friendlyProcessName(proc.name))
                                HStack(spacing: 7.5) {
                                    AppProcessIconView(
                                        appBundlePath: proc.appBundlePath,
                                        pid: proc.pid,
                                        processName: proc.name,
                                        size: 16
                                    )

                                    Text(displayName)
                                        .font(.system(size: 10.8, weight: .medium))
                                        .foregroundColor(.white.opacity(0.94))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(minWidth: 96, maxWidth: 132, alignment: .leading)

                                    GeometryReader { geo in
                                        let frac = min(1.0, max(0.05, proc.totalBytesPerSec / maxRate))
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.white.opacity(0.065))
                                            Capsule()
                                                .fill(proc.uploadBytesPerSec > proc.downloadBytesPerSec
                                                      ? Color(red: 1.0, green: 0.78, blue: 0.48).opacity(0.88)
                                                      : Color(red: 0.74, green: 0.90, blue: 1.0).opacity(0.88))
                                                .frame(width: geo.size.width * frac)
                                                .animation(.easeOut(duration: 0.35), value: frac)
                                        }
                                    }
                                    .frame(height: 3.5)

                                    Text(state.isProMode
                                         ? "↓\(ByteRateFormatter.compact(proc.downloadBytesPerSec)) ↑\(ByteRateFormatter.compact(proc.uploadBytesPerSec))"
                                         : ByteRateFormatter.menuBar(proc.totalBytesPerSec))
                                        .font(.system(size: state.isProMode ? 8.6 : 9.8, weight: .medium, design: .monospaced))
                                        .foregroundColor(inkSoft)
                                        .monospacedDigit()
                                        .frame(width: state.isProMode ? 82 : 66, alignment: .trailing)
                                }
                                .help(processTooltip(proc, displayName: displayName))
                            }
                        }
                    }
                }
            }
            } // end connected branch
        }
    }

    private func sessionMetricColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(label)
                .font(.system(size: 9.2, weight: .medium))
                .foregroundColor(inkDim)
            Text(value)
                .font(.system(size: 12.2, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.96))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interfaceSymbol(_ kind: ActiveInterfaceKind) -> String {
        switch kind {
        case .wifi: return "wifi"
        case .vpn: return "lock.shield"
        case .ethernet: return "cable.connector"
        case .other: return "network"
        }
    }

    private func processTooltip(_ proc: ProcessBandwidth, displayName: String) -> String {
        let rates = "↓ \(ByteRateFormatter.menuBar(proc.downloadBytesPerSec)) · ↑ \(ByteRateFormatter.menuBar(proc.uploadBytesPerSec))"
        if proc.processCount > 1 {
            return "\(displayName) (\(proc.processCount) processes) · \(rates)"
        }
        return "\(displayName) · \(rates)"
    }

    private func miniStatPill(label: String, value: String, highlight: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(label)
                .font(.system(size: 7.4, weight: .semibold, design: .monospaced))
                .foregroundColor(inkDim)
            Text(value)
                .font(.system(size: 10.4, weight: .semibold, design: .monospaced))
                .foregroundColor(highlight)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - TAB 2: PRIVACY

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. "Who Can See You?" 3-Actor Human Story with icons & left severity hairline
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(state.isProMode ? "PRIVACY POSTURE · \(state.trustAudit.score)/100" : "Who Can See You Here?")
                        .font(state.isProMode
                              ? .system(size: 8.8, weight: .semibold, design: .monospaced)
                              : .system(size: 11.4, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    Spacer()
                }

                VStack(spacing: 6) {
                    ForEach(state.privacyActors) { row in
                        let col = auditColor(row.severity)
                        HStack(alignment: .top, spacing: 8.5) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(col.opacity(0.85))
                                .frame(width: 2.2)
                                .padding(.vertical, 2)

                            Image(systemName: actorIcon(for: row.id))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(col.opacity(0.92))
                                .frame(width: 15)
                                .padding(.top, 1.5)

                            VStack(alignment: .leading, spacing: 1.5) {
                                HStack {
                                    Text(row.actor)
                                        .font(.system(size: 10.8, weight: .medium))
                                        .foregroundColor(.white.opacity(0.94))
                                    Spacer()
                                    Text(row.verdict)
                                        .font(.system(size: 10.0, weight: .semibold))
                                        .foregroundColor(col)
                                }
                                Text(row.detail)
                                    .font(.system(size: 9.4))
                                    .foregroundColor(inkDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.032))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(hairSoft, lineWidth: 0.8))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.actor)
                        .accessibilityValue("\(row.verdict). \(row.detail)")
                    }
                }
            }

            if state.trustAudit.hasGatewayAnomaly || state.trustAudit.hasSecurityDowngrade {
                HStack {
                    Text("Replaced your router? Re-verify this network.")
                        .font(.system(size: 9.6))
                        .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.60))
                    Spacer()
                    Button("Trust Router") { state.trustCurrentFingerprint() }
                        .buttonStyle(AetherHairlineButtonStyle())
                }
                .padding(8)
                .background(Color(red: 1.0, green: 0.36, blue: 0.32).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // 2. Where Are You? (Sliding spring pill)
            VStack(alignment: .leading, spacing: 4.5) {
                Text("WHERE ARE YOU?")
                    .font(.system(size: 7.6, weight: .semibold, design: .monospaced))
                    .foregroundColor(inkDim)
                    .tracking(0.5)
                HStack(spacing: 3) {
                    ForEach(TrustZone.allCases) { zone in
                        let on = state.currentTrustZone == zone
                        let title = zone == .untrusted ? "PUBLIC" : zone.label
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                state.setTrustZone(zone)
                            }
                        } label: {
                            Text(title)
                                .font(.system(size: 8.6, weight: on ? .semibold : .regular, design: .monospaced))
                                .foregroundColor(on ? .black : inkSoft)
                                .frame(maxWidth: .infinity)
                                .frame(height: 23)
                                .background {
                                    if on {
                                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                            .fill(Color.white)
                                            .matchedGeometryEffect(id: "trustZonePill", in: trustZoneNS)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(zone.subtitle)
                    }
                }
                .padding(2.5)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            }

            // 3. 1-Click Private Lookups (hidden or redirects cleanly to System Settings in MAS sandbox)
            if !state.isSandboxed {
                VStack(alignment: .leading, spacing: 4.5) {
                HStack {
                    Text(state.isProMode ? "1-CLICK DNS" : "WEBSITE LOOKUPS (DNS)")
                        .font(.system(size: 7.6, weight: .semibold, design: .monospaced))
                        .foregroundColor(inkDim)
                        .tracking(0.5)
                    Spacer()
                    Text(state.isApplyingDNS ? "Updating…" : state.dns.providerLabel)
                        .font(.system(size: 9.0))
                        .foregroundColor(inkSoft)
                        .lineLimit(1)
                }
                HStack(spacing: 3) {
                    ForEach(DNSPreset.allCases) { preset in
                        let on = state.detectedDNSPreset == preset
                        let label: String = {
                            if state.isProMode { return preset.label }
                            switch preset {
                            case .automatic:  return "Auto"
                            case .cloudflare: return "Cloudflare"
                            case .quad9:      return "Quad9"
                            case .google:     return "Google"
                            }
                        }()
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                state.applyDNSPreset(preset)
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 9.4, weight: on ? .semibold : .regular))
                                .foregroundColor(on ? .black : inkSoft)
                                .frame(maxWidth: .infinity)
                                .frame(height: 23)
                                .background {
                                    if on {
                                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                            .fill(Color.white)
                                            .matchedGeometryEffect(id: "dnsPresetPill", in: dnsPresetNS)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isApplyingDNS)
                    }
                }
                .padding(2.5)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
                }
            }

            // 4. Two Clean Expandable Deep-Dive Pills
            HStack(spacing: 6) {
                drawerPill(
                    title: "Who's on Wi-Fi (\(state.lanDevices.count))",
                    active: privacyDetailSection == .lanDevices
                ) {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        privacyDetailSection = (privacyDetailSection == .lanDevices) ? .none : .lanDevices
                    }
                    DispatchQueue.main.async { onRequestResize?() }
                }

                drawerPill(
                    title: "Technical Audit (\(state.trustAudit.checks.count))",
                    active: privacyDetailSection == .technicalAudit
                ) {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        privacyDetailSection = (privacyDetailSection == .technicalAudit) ? .none : .technicalAudit
                    }
                    DispatchQueue.main.async { onRequestResize?() }
                }
            }

            if privacyDetailSection == .lanDevices {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(state.lanDevices.prefix(12)) { dev in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(dev.isGateway ? Color(red: 0.28, green: 0.90, blue: 0.64) : (dev.isLocalMac ? .white : Color.white.opacity(0.35)))
                                    .frame(width: 5, height: 5)
                                VStack(alignment: .leading, spacing: 0.5) {
                                    Text(dev.displayName)
                                        .font(.system(size: 10.4, weight: .medium))
                                        .foregroundColor(.white.opacity(0.92))
                                        .lineLimit(1)
                                    Text(dev.vendor)
                                        .font(.system(size: 8.6))
                                        .foregroundColor(inkDim)
                                }
                                Spacer()
                                Text(dev.ip)
                                    .font(.system(size: 9.0, design: .monospaced))
                                    .foregroundColor(inkSoft)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 145)
                .transition(.opacity)
            } else if privacyDetailSection == .technicalAudit {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(state.trustAudit.checks) { check in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(auditColor(check.severity))
                                    .frame(width: 5.5, height: 5.5)
                                    .padding(.top, 4.5)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(check.category)
                                            .font(.system(size: 7.8, weight: .semibold, design: .monospaced))
                                            .foregroundColor(inkDim)
                                            .frame(width: 48, alignment: .leading)
                                        Text(check.title)
                                            .font(.system(size: 10.4, weight: .medium))
                                            .foregroundColor(.white.opacity(0.92))
                                            .lineLimit(1)
                                    }
                                    Text(check.detail)
                                        .font(.system(size: 9.2))
                                        .foregroundColor(inkDim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxHeight: 155)
                .transition(.opacity)
            }

            if let firstVPN = state.vpns.first, !firstVPN.isConnected && state.currentTrustZone == .untrusted {
                Button {
                    state.toggleVPN(firstVPN)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10.5))
                        Text("Turn On \(firstVPN.name)")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func drawerPill(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 9.6, weight: active ? .semibold : .medium))
                    .foregroundColor(active ? .black : inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: active ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8.0, weight: .semibold))
                    .foregroundColor(active ? .black : inkDim)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(active ? Color.white : Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7.5, style: .continuous).stroke(active ? Color.clear : hairSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - TAB 3: WI-FI

    private var wifiPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !state.hasLocationAccess {
                locationPermissionCard(compact: true)
            }

            if let roam = state.channelAnalysis.roamingNudge {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.0, green: 0.76, blue: 0.36)).frame(width: 6, height: 6)
                    Text("Faster \(roam.targetBand.rawValue) signal available for \(roam.ssid)")
                        .font(.system(size: 10.0, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(2)
                    Spacer()
                    Button(state.isRoaming ? "Switching…" : "Switch") {
                        state.roamToBetterAP()
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .frame(height: 23)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color(red: 1.0, green: 0.76, blue: 0.36).opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(red: 1.0, green: 0.76, blue: 0.36).opacity(0.32), lineWidth: 1))
            }

            if state.wifi.isConnected {
                HStack(spacing: 6) {
                    Button {
                        state.stageMode = .spectrum
                        state.performHaptic()
                    } label: {
                        HStack(spacing: 5) {
                            Text(state.channelAnalysis.congestionLabel)
                                .font(.system(size: 7.8, weight: .semibold, design: .monospaced))
                                .foregroundColor(congestionColor)
                            Text(state.channelAnalysis.recommendationSummary)
                                .font(.system(size: 9.5))
                                .foregroundColor(inkSoft)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if state.wifi.ssid != nil && (!state.isSandboxed || state.wifi.security == .open) {
                        Button {
                            state.generateShareQR()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 9.8, weight: .medium))
                                Text(state.isLoadingQR ? "…" : (state.qrSharePayload != nil ? "Hide" : "Share Wi-Fi"))
                                    .font(.system(size: 9.4, weight: .medium))
                            }
                            .foregroundColor(state.qrSharePayload != nil ? .black : .white.opacity(0.92))
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(state.qrSharePayload != nil ? Color.white : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Generate a scannable QR code for this Wi-Fi network (uses Keychain / Touch ID)")
                    }
                }
            }

            if let qrPayload = state.qrSharePayload, let qrSSID = state.qrShareSSID {
                WiFiQRCodeCard(ssid: qrSSID, payload: qrPayload) {
                    state.qrSharePayload = nil
                    state.qrShareSSID = nil
                    DispatchQueue.main.async { onRequestResize?() }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            HStack {
                Text(state.isProMode ? "WI-FI NETWORKS" : "Nearby Wi-Fi")
                    .font(state.isProMode
                          ? .system(size: 8.8, weight: .semibold, design: .monospaced)
                          : .system(size: 10.6, weight: .semibold))
                    .foregroundColor(inkSoft)
                Spacer()
                Button {
                    Task { await state.scanNearbyNetworks() }
                } label: {
                    HStack(spacing: 4) {
                        if state.isScanningNetworks {
                            ProgressView().controlSize(.mini).scaleEffect(0.65)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9.2, weight: .medium))
                        }
                        Text(state.isScanningNetworks ? "Scanning…" : "Refresh")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(inkSoft)
                }
                .buttonStyle(.plain)
                .disabled(state.isScanningNetworks)
            }

            if !state.wifi.powerOn {
                HStack {
                    Text("Wi-Fi is turned off.")
                        .font(.system(size: 10.6))
                        .foregroundColor(inkDim)
                    Spacer()
                    Button("Turn On") { state.toggleWiFiPower() }
                        .buttonStyle(AetherHairlineButtonStyle())
                }
                .padding(.vertical, 6)
            } else if !state.nearbyNetworks.isEmpty {
                nearbyNetworksList(maxHeight: 165, limit: 12)
            } else if !state.knownSSIDs.isEmpty {
                savedNetworksSection(maxHeight: 145)
            } else {
                Text(state.isScanningNetworks ? "Looking for nearby Wi-Fi networks…" : "No named networks visible yet — tap Refresh or Allow Location above.")
                    .font(.system(size: 10))
                    .foregroundColor(inkDim)
                    .padding(.vertical, 4)
            }

            if let err = state.connectionError {
                Text(err)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.52))
            }

            if !state.vpns.isEmpty {
                Divider().background(hairSoft)
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.isProMode ? "VPN TUNNELS" : "VPN & Privacy Tunnels")
                        .font(state.isProMode
                              ? .system(size: 8.8, weight: .semibold, design: .monospaced)
                              : .system(size: 10.6, weight: .semibold))
                        .foregroundColor(inkSoft)

                    ForEach(state.vpns) { vpn in
                        HStack {
                            Circle()
                                .fill(vpn.isConnected ? Color(red: 0.25, green: 0.90, blue: 0.62) : Color.white.opacity(0.24))
                                .frame(width: 6, height: 6)
                                .shadow(color: vpn.isConnected ? Color(red: 0.25, green: 0.90, blue: 0.62).opacity(0.7) : .clear, radius: 3)
                            Text(vpn.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.92))
                            Spacer()
                            Button(vpn.isConnected ? "Disconnect" : "Connect") {
                                state.toggleVPN(vpn)
                            }
                            .buttonStyle(AetherHairlineButtonStyle(prominent: vpn.isConnected))
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 31)
                        .background(Color.white.opacity(0.032))
                        .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7.5, style: .continuous).stroke(hairSoft, lineWidth: 0.8))
                    }
                }
            }
        }
    }

    // MARK: - TAB 4: MORE

    private var morePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Simple vs Pro Detail Level (Matched-geometry sliding pill)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Display Detail")
                        .font(.system(size: 10.6, weight: .medium))
                        .foregroundColor(.white.opacity(0.94))
                    Text(state.isProMode ? "Raw dBm, ms, BSSID & RF specs" : "Plain English first, tech on tap")
                        .font(.system(size: 9.2))
                        .foregroundColor(inkDim)
                }
                Spacer()
                HStack(spacing: 2) {
                    slidingModeChip(title: "Simple", active: !state.isProMode, id: "detailPill", ns: detailModeNS) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) { state.isProMode = false }
                        state.performHaptic()
                    }
                    slidingModeChip(title: "Pro", active: state.isProMode, id: "detailPill", ns: detailModeNS) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) { state.isProMode = true }
                        state.performHaptic()
                    }
                }
                .padding(2.5)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            }

            // Menu Bar Display Mode (Matched-geometry sliding pill)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Menu Bar")
                        .font(.system(size: 10.6, weight: .medium))
                        .foregroundColor(.white.opacity(0.94))
                    Text(menuBarModeCaption)
                        .font(.system(size: 9.2))
                        .foregroundColor(inkDim)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        slidingModeChip(title: mode.label.capitalized, active: state.menuBarMode == mode, id: "mbPill", ns: menuBarModeNS) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) { state.menuBarMode = mode }
                            state.performHaptic()
                        }
                    }
                }
                .padding(2.5)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            }

            Divider().background(hairSoft)

            // Copyable Identity Chips with hover illumination
            VStack(spacing: 5) {
                copyRow(label: state.isProMode ? "LOCAL IP" : "This Mac", value: state.route.localIP ?? "—")
                copyRow(label: state.isProMode ? "GATEWAY" : "Router", value: state.route.gatewayIP ?? "—")
                copyRow(
                    label: state.isProMode ? "MAC" : "Wi-Fi ID",
                    value: state.wifi.hardwareMAC ?? "—",
                    tag: state.wifi.isPrivateMAC == true ? "Private" : (state.wifi.isPrivateMAC == false ? "Hardware" : nil)
                )

                // On-Demand Public IP
                HStack(spacing: 6) {
                    Text(state.isProMode ? "PUBLIC IP" : "Online As")
                        .font(.system(size: 9.2, weight: .medium))
                        .foregroundColor(inkDim)
                        .frame(width: 68, alignment: .leading)

                    if let pub = state.publicIP {
                        Button {
                            state.copyToClipboard(pub.ip, label: "Public IP")
                        } label: {
                            HStack(spacing: 4) {
                                Text(pub.ip)
                                    .font(.system(size: 10.0, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.94))
                                if !pub.locationSummary.isEmpty {
                                    Text("· \(pub.locationSummary)")
                                        .font(.system(size: 9.2))
                                        .foregroundColor(inkDim)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9.0))
                                    .foregroundColor(inkDim)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer()
                        Button(state.isFetchingPublicIP ? "Checking…" : "Check") {
                            state.revealPublicIP()
                        }
                        .buttonStyle(AetherHairlineButtonStyle())
                        .disabled(state.isFetchingPublicIP)
                    }
                }
                .padding(.horizontal, 8.5)
                .frame(height: 28)
                .background(Color.white.opacity(0.032))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(hairSoft, lineWidth: 0.8))
            }

            HStack(spacing: 5) {
                if !state.isSandboxed {
                    Button("Refresh DNS") { state.flushDNS() }
                        .buttonStyle(AetherHairlineButtonStyle())
                        .frame(maxWidth: .infinity)
                }
                Button("Login Check") { state.checkCaptivePortalManually() }
                    .buttonStyle(AetherHairlineButtonStyle())
                    .frame(maxWidth: .infinity)
                Button("Hide Apple Wi-Fi") { state.openControlCenterSettings() }
                    .buttonStyle(AetherHairlineButtonStyle())
                    .frame(maxWidth: .infinity)
                    .help("Open Control Center Settings to hide Apple's built-in Wi-Fi icon")
            }

            Divider().background(hairSoft)

            HStack(spacing: 10) {
                Button("STUDIO ↗") { onOpenStudio() }
                    .buttonStyle(QuietFooterLinkStyle(active: true))

                Button(state.launchAtLogin ? "LOGIN: ON" : "LOGIN: OFF") {
                    state.toggleLaunchAtLogin()
                }
                .buttonStyle(QuietFooterLinkStyle(active: state.launchAtLogin))

                Button("REPORT") {
                    state.copyDiagnosticsReport()
                }
                .buttonStyle(QuietFooterLinkStyle())

                Button("PRIVACY") {
                    state.openPrivacyPolicy()
                }
                .buttonStyle(QuietFooterLinkStyle())
                .help("Open Aether Privacy Policy")

                Spacer()

                Button("QUIT") { onQuit() }
                    .buttonStyle(QuietFooterLinkStyle())
            }
        }
    }

    private func slidingModeChip(title: String, active: Bool, id: String, ns: Namespace.ID, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9.4, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .black : inkSoft)
                .padding(.horizontal, 8.5)
                .frame(height: 21)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .fill(Color.white)
                            .matchedGeometryEffect(id: id, in: ns)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func copyRow(label: String, value: String, tag: String? = nil) -> some View {
        HoverSurfaceButton(cornerRadius: 7) {
            guard value != "—" else { return }
            state.copyToClipboard(value, label: label)
        } content: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 9.2, weight: .medium))
                    .foregroundColor(inkDim)
                    .frame(width: 68, alignment: .leading)
                Text(value)
                    .font(.system(size: 10.0, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                if let tag {
                    Text(tag)
                        .font(.system(size: 8.0, weight: .semibold))
                        .foregroundColor(tag == "Private" ? Color(red: 0.30, green: 0.90, blue: 0.64) : inkDim)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Spacer()
                if value != "—" {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9.0))
                        .foregroundColor(inkDim)
                }
            }
            .padding(.horizontal, 8.5)
            .frame(height: 28)
        }
    }

    // MARK: - Actions & Styling Helpers

    private func handleNetworkTap(_ net: NearbyNetwork) {
        if net.isCurrent { return }
        if net.security == .open {
            passwordPromptSSID = nil
            Task { await state.connectToNetwork(ssid: net.ssid, password: nil) }
        } else if state.knownSSIDs.contains(net.ssid) && passwordPromptSSID != net.ssid {
            // Try saved macOS Keychain credentials first; drop down password field if auth fails
            passwordPromptSSID = nil
            Task {
                let ok = await state.connectToNetwork(ssid: net.ssid, password: nil)
                if !ok {
                    passwordInput = ""
                    passwordPromptSSID = net.ssid
                    DispatchQueue.main.async { onRequestResize?() }
                }
            }
        } else if passwordPromptSSID == net.ssid {
            passwordPromptSSID = nil
        } else {
            passwordInput = ""
            passwordPromptSSID = net.ssid
            DispatchQueue.main.async { onRequestResize?() }
        }
    }

    private func submitPasswordConnect(ssid: String) {
        let pw = passwordInput
        passwordPromptSSID = nil
        passwordInput = ""
        Task { await state.connectToNetwork(ssid: ssid, password: pw) }
    }

    private func readinessIcon(for id: String) -> String {
        switch id {
        case "calls":  return "video.fill"
        case "stream": return "play.tv.fill"
        default:       return "bolt.horizontal.fill"
        }
    }

    private func actorIcon(for id: String) -> String {
        switch id {
        case "airwaves": return "wave.3.right"
        case "isp":      return "globe"
        default:         return "laptopcomputer.and.iphone"
        }
    }

    private var menuBarModeCaption: String {
        switch state.menuBarMode {
        case .iconOnly:    return "Just the minimal Wi-Fi icon"
        case .autoSpeed:   return "Shows speed when active"
        case .alwaysSpeed: return "Always shows live speed"
        }
    }

    private func readinessColor(_ status: ReadinessStatus) -> Color {
        switch status {
        case .great:   return Color(red: 0.28, green: 0.90, blue: 0.64)
        case .okay:    return Color(red: 1.00, green: 0.78, blue: 0.38)
        case .poor:    return Color(red: 1.00, green: 0.44, blue: 0.40)
        case .offline: return inkDim
        }
    }

    private var congestionColor: Color {
        switch state.channelAnalysis.congestionLabel {
        case "CLEAR":    return Color(red: 0.28, green: 0.90, blue: 0.64)
        case "LIGHT":    return Color(red: 0.72, green: 0.88, blue: 1.0)
        case "MODERATE": return Color(red: 1.00, green: 0.76, blue: 0.36)
        case "CROWDED":  return Color(red: 1.00, green: 0.44, blue: 0.40)
        default:         return inkDim
        }
    }

    private func badgeColor(for tab: PanelTab) -> Color? {
        if tab == .shield {
            switch state.trustAudit.level {
            case .alert:    return Color(red: 1.0, green: 0.42, blue: 0.38)
            case .caution:  return Color(red: 1.0, green: 0.74, blue: 0.34)
            case .shielded: return Color(red: 0.25, green: 0.90, blue: 0.62)
            default:        return nil
            }
        }
        if tab == .networks && state.channelAnalysis.roamingNudge != nil {
            return Color(red: 1.0, green: 0.76, blue: 0.36)
        }
        return nil
    }

    private var linkQualityColor: Color {
        if state.isWired { return Color(red: 0.74, green: 0.90, blue: 1.0) }
        guard state.wifi.isConnected else { return inkDim }
        if state.wifi.snr >= 25 { return Color(red: 0.78, green: 0.92, blue: 1.0) }
        if state.wifi.snr >= 15 { return Color(red: 1.0, green: 0.78, blue: 0.42) }
        return Color(red: 1.0, green: 0.46, blue: 0.42)
    }

    private func latencyColor(_ ms: Double?, warn: Double, bad: Double) -> Color {
        guard let ms else { return inkDim }
        if ms >= bad { return Color(red: 1.0, green: 0.46, blue: 0.42) }
        if ms >= warn { return Color(red: 1.0, green: 0.78, blue: 0.42) }
        return Color.white.opacity(0.92)
    }

    private func severityColor(from level: TrustLevel) -> Color {
        switch level {
        case .shielded: return Color(red: 0.30, green: 0.90, blue: 0.64)
        case .trusted:  return Color(red: 0.72, green: 0.88, blue: 1.0)
        case .caution:  return Color(red: 1.00, green: 0.76, blue: 0.38)
        case .alert:    return Color(red: 1.00, green: 0.44, blue: 0.40)
        case .offline:  return inkDim
        }
    }

    private func auditColor(_ sev: AuditSeverity) -> Color {
        switch sev {
        case .ok:      return Color(red: 0.28, green: 0.88, blue: 0.62)
        case .info:    return Color.white.opacity(0.48)
        case .caution: return Color(red: 1.0, green: 0.74, blue: 0.34)
        case .alert:   return Color(red: 1.0, green: 0.42, blue: 0.38)
        }
    }
}

// MARK: - Tactile Hover Surface & Animated Shimmer Bar

private struct HoverSurfaceButton<Content: View>: View {
    var cornerRadius: CGFloat = 9
    var highlighted: Bool = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.white.opacity(
                        highlighted ? (hovered ? 0.12 : 0.085) : (hovered ? 0.068 : 0.032)
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(hovered ? 0.19 : (highlighted ? 0.14 : 0.08)), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: hovered)
        .onHover { hovered = $0 }
    }
}

private struct IndeterminateShimmerBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.35

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                if reduceMotion {
                    Capsule().fill(Color(red: 0.72, green: 0.92, blue: 1.0).opacity(0.6))
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color(red: 0.72, green: 0.92, blue: 1.0), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.38)
                        .offset(x: phase * geo.size.width)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    phase = 0.72
                }
            }
        }
        .accessibilityLabel("Running speed and responsiveness test")
    }
}

private struct AetherHairlineButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.4, weight: .medium))
            .foregroundColor(.white.opacity(prominent ? 0.96 : 0.86))
            .padding(.horizontal, 8.5)
            .frame(height: 25)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : (prominent ? 0.11 : 0.048)))
            .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6.5, style: .continuous).stroke(Color.white.opacity(prominent ? 0.28 : 0.15), lineWidth: 1))
    }
}

private struct QuietFooterLinkStyle: ButtonStyle {
    var active: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8.6, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(Color.white.opacity(configuration.isPressed ? 0.98 : (active ? 0.86 : 0.44)))
            .contentShape(Rectangle())
    }
}
