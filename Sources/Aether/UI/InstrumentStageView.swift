import AetherCore
import SwiftUI

/// Full-bleed OLED Obsidian Instrument Stage — milled-glass & luminous-ribbon craft inspired by Satie.
/// Renders three switchable live network visualizations:
///   1. FLUX     — Multi-layer harmonic silk ribbons with Gaussian bloom & pulsing live cursor
///   2. SPECTRUM — Luminous dual-pass Gaussian RF channel spectrum (or concentric polar SNR field)
///   3. ROUTE    — Curved architectural 4-node circuit with comet-tail packets & frosted VPN shield
struct InstrumentStageView: View {
    @ObservedObject var state: AppState
    let onOpenStudio: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false
    @State private var peekSwitcher = false
    @State private var peekTask: Task<Void, Never>?
    @Namespace private var modePillNS

    private let inkSoft = Color.white.opacity(0.74)
    private let inkDim = Color.white.opacity(0.46)

    var body: some View {
        ZStack {
            // Pure OLED obsidian cavity with subtle vertical optical depth
            LinearGradient(
                colors: [
                    Color(red: 0.026, green: 0.030, blue: 0.040),
                    Color(red: 0.014, green: 0.017, blue: 0.023)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Whisper-subtle atmospheric radial aura matched to trust posture
            RadialGradient(
                colors: [auraColor.opacity(0.26), auraColor.opacity(0.06), Color.clear],
                center: UnitPoint(x: 0.5, y: 0.62),
                startRadius: 8,
                endRadius: 195
            )
            .blendMode(.screen)
            .animation(.easeInOut(duration: 0.8), value: state.trustAudit.level)
            .allowsHitTesting(false)

            // Live 20fps periodic vector instrument canvas (strictly stops when popover closes or Reduce Motion is on -> 0% idle CPU)
            if state.stageMode == .spectrum && state.wifi.isConnected && !state.channelAnalysis.lobes(for: state.wifi.band).isEmpty {
                ChannelSpectrumCanvas(
                    lobes: state.channelAnalysis.lobes(for: state.wifi.band),
                    band: state.wifi.band,
                    recommendedChannel: state.channelAnalysis.recommendedChannel,
                    compact: true
                )
                .allowsHitTesting(false)
            } else if state.isPopoverOpen && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        switch state.stageMode {
                        case .flux:
                            drawFluxHarmonicRibbons(ctx: &ctx, size: size, time: t)
                        case .spectrum:
                            drawSpectrumField(ctx: &ctx, size: size, time: t)
                        case .route:
                            drawRouteCircuit(ctx: &ctx, size: size, time: t)
                        }
                    }
                }
                .allowsHitTesting(false)
            } else {
                Canvas { ctx, size in
                    switch state.stageMode {
                    case .flux:
                        drawFluxHarmonicRibbons(ctx: &ctx, size: size, time: 0)
                    case .spectrum:
                        drawSpectrumField(ctx: &ctx, size: size, time: 0)
                    case .route:
                        drawRouteCircuit(ctx: &ctx, size: size, time: 0)
                    }
                }
                .allowsHitTesting(false)
            }

            // Soft top vignette so floating typography reads effortlessly over bright peaks
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.76), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 66)
                Spacer()
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
            }
            .allowsHitTesting(false)

            // Tap anywhere on the stage to cycle instrument modes (exact Satie gesture)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) {
                        state.cycleStageMode()
                    }
                    revealSwitcherBriefly()
                }

            // Floating Overlay Header & Footer Telemetry
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(state.heroTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(state.heroSubtitle)
                            .font(.system(size: 8.6, weight: .medium, design: .monospaced))
                            .foregroundColor(inkSoft)
                            .tracking(0.3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .allowsHitTesting(false)

                    Spacer(minLength: 4)

                    HStack(spacing: 5.5) {
                        // Trust Posture Pill
                        Button {
                            state.selectTab(.shield)
                        } label: {
                            HStack(spacing: 4.5) {
                                Circle()
                                    .fill(trustAccent)
                                    .frame(width: 5.5, height: 5.5)
                                    .shadow(color: trustAccent.opacity(0.75), radius: 3)
                                Text(state.trustPillLabel)
                                    .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundColor(.white.opacity(0.94))
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Color.black.opacity(0.52))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(trustAccent.opacity(0.36), lineWidth: 0.85))
                        }
                        .buttonStyle(.plain)
                        .help("\(state.trustAudit.headline) (\(state.trustAudit.score)/100)")

                        StagePowerButton(isOn: state.wifi.powerOn) {
                            state.toggleWiFiPower()
                        }

                        StageExpandButton(action: onOpenStudio)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 11)

                Spacer()

                HStack(alignment: .bottom) {
                    if !(isHovering || peekSwitcher) {
                        Text(stageFooterReadout)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(inkSoft)
                            .tracking(0.35)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                        Spacer()
                        if state.stageMode == .flux {
                            Text("SESSION \(ByteRateFormatter.totalBytes(state.sessionDownBytes)) ↓ · \(ByteRateFormatter.totalBytes(state.sessionUpBytes)) ↑")
                                .font(.system(size: 7.6, weight: .regular, design: .monospaced))
                                .foregroundColor(inkDim)
                                .lineLimit(1)
                        }
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 13)
                .padding(.bottom, 9)
                .allowsHitTesting(false)
            }

            // Hover-revealed frosted glass instrument mode switcher (0% clutter at rest)
            VStack {
                Spacer()
                HStack(spacing: 1.5) {
                    ForEach(StageMode.allCases) { mode in
                        let selected = state.stageMode == mode
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) {
                                state.stageMode = mode
                            }
                            state.performHaptic()
                        } label: {
                            Text(mode.title)
                                .font(.system(size: 9.2, weight: selected ? .semibold : .medium))
                                .foregroundColor(selected ? .black : Color.white.opacity(0.78))
                                .padding(.horizontal, 10)
                                .frame(height: 21)
                                .background {
                                    if selected {
                                        Capsule()
                                            .fill(Color.white)
                                            .matchedGeometryEffect(id: "stageModePill", in: modePillNS)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.black.opacity(0.66))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
                .padding(.bottom, 9)
                .opacity((isHovering || peekSwitcher) ? 1.0 : 0.0)
                .offset(y: (isHovering || peekSwitcher) ? 0 : 4)
                .animation(.easeInOut(duration: 0.18), value: isHovering)
                .animation(.easeInOut(duration: 0.18), value: peekSwitcher)
                .allowsHitTesting(isHovering || peekSwitcher)
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            // Sapphire-glass top specular rim highlight
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.06), Color.white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(state.heroTitle), \(state.heroSubtitle), \(stageFooterReadout)")
        .accessibilityHint("Tap stage to cycle Flux, Spectrum, and Route views")
    }

    // MARK: - 1. FLUX Multi-Layer Harmonic Silk Ribbons with Luminous Bloom

    private func drawFluxHarmonicRibbons(ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let samples = state.throughputHistory
        guard samples.count >= 2 else { return }

        let padX: CGFloat = 12
        let midY: CGFloat = size.height * 0.60
        let maxUpH: CGFloat = size.height * 0.30
        let maxDownH: CGFloat = size.height * 0.21
        let plotW = size.width - padX * 2

        // Calibrated horizon baseline + micro graduation ticks
        var horizon = Path()
        horizon.move(to: CGPoint(x: padX, y: midY))
        horizon.addLine(to: CGPoint(x: size.width - padX, y: midY))
        ctx.stroke(horizon, with: .color(Color.white.opacity(0.12)), lineWidth: 0.75)

        for tickIdx in 0...12 {
            let tx = padX + (CGFloat(tickIdx) / 12.0) * plotW
            var tick = Path()
            tick.move(to: CGPoint(x: tx, y: midY - 2.0))
            tick.addLine(to: CGPoint(x: tx, y: midY + 2.0))
            ctx.stroke(tick, with: .color(Color.white.opacity(tickIdx % 3 == 0 ? 0.16 : 0.06)), lineWidth: 0.6)
        }

        // Honest floor at 2 MB/s so 10–30 KB/s idle chatter looks serene & calm,
        // while real megabyte downloads/uploads swell dramatically across the stage.
        let rawPeak = max(state.peakThroughputBytesPerSec, 2_000_000)
        func norm(_ v: Double) -> CGFloat {
            let linear = min(max(v / rawPeak, 0), 1)
            return CGFloat(pow(linear, 0.45))
        }

        let count = samples.count

        // Draw 2 subtle harmonic echo silk threads behind the primary ribbon for Satie-like depth
        let downColor = Color(red: 0.72, green: 0.92, blue: 1.0)
        let upColor = Color(red: 1.0, green: 0.79, blue: 0.48)

        for layer in [2, 1, 0] {
            let scale: CGFloat = layer == 0 ? 1.0 : (layer == 1 ? 0.72 : 0.44)
            let phaseShift = Double(layer) * 0.95
            var downPts: [CGPoint] = []
            var upPts: [CGPoint] = []
            downPts.reserveCapacity(count)
            upPts.reserveCapacity(count)

            for i in 0..<count {
                let u = Double(i) / Double(count - 1)
                let x = padX + CGFloat(u) * plotW
                // Whisper-subtle living carrier breath at rest (never frantic)
                let idleBreath = sin(u * Double.pi) * (1.2 + 0.65 * sin(time * 0.95 + u * 5.0 + phaseShift))
                let dVal = norm(samples[i].downloadBytesPerSec) * maxUpH * scale
                let uVal = norm(samples[i].uploadBytesPerSec) * maxDownH * scale
                downPts.append(CGPoint(x: x, y: midY - dVal - CGFloat(idleBreath) * scale))
                upPts.append(CGPoint(x: x, y: midY + uVal + CGFloat(idleBreath * 0.65) * scale))
            }

            let dPath = smoothPath(through: downPts)
            let uPath = smoothPath(through: upPts)

            if layer == 0 {
                // Soft gradient under-fill
                var dFill = dPath
                dFill.addLine(to: CGPoint(x: downPts.last!.x, y: midY))
                dFill.addLine(to: CGPoint(x: downPts.first!.x, y: midY))
                dFill.closeSubpath()
                ctx.fill(
                    dFill,
                    with: .linearGradient(
                        Gradient(colors: [downColor.opacity(0.24), downColor.opacity(0.0)]),
                        startPoint: CGPoint(x: 0, y: midY - maxUpH),
                        endPoint: CGPoint(x: 0, y: midY)
                    )
                )

                var uFill = uPath
                uFill.addLine(to: CGPoint(x: upPts.last!.x, y: midY))
                uFill.addLine(to: CGPoint(x: upPts.first!.x, y: midY))
                uFill.closeSubpath()
                ctx.fill(
                    uFill,
                    with: .linearGradient(
                        Gradient(colors: [upColor.opacity(0.20), upColor.opacity(0.0)]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: 0, y: midY + maxDownH)
                    )
                )

                // Outer luminous bloom + razor-sharp white-tinted core stroke
                ctx.stroke(dPath, with: .color(downColor.opacity(0.26)), style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round))
                ctx.stroke(dPath, with: .color(Color.white.opacity(0.95)), style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))

                ctx.stroke(uPath, with: .color(upColor.opacity(0.22)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                ctx.stroke(uPath, with: .color(upColor.opacity(0.90)), style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))

                // Pulsing beacon halo at live right edge
                let pulse = 0.5 + 0.5 * sin(time * 3.0)
                if let lastD = downPts.last {
                    let hr = CGFloat(5.5 + pulse * 3.5)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: lastD.x - hr, y: lastD.y - hr, width: hr * 2, height: hr * 2)),
                        with: .color(downColor.opacity(0.22 * (1.0 - pulse * 0.4)))
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: lastD.x - 2.6, y: lastD.y - 2.6, width: 5.2, height: 5.2)),
                        with: .color(.white)
                    )
                }
                if let lastU = upPts.last {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: lastU.x - 2.1, y: lastU.y - 2.1, width: 4.2, height: 4.2)),
                        with: .color(upColor)
                    )
                }
            } else {
                // Translucent harmonic echo silk strands
                let alpha = layer == 1 ? 0.22 : 0.11
                ctx.stroke(dPath, with: .color(downColor.opacity(alpha)), lineWidth: 0.8)
                ctx.stroke(uPath, with: .color(upColor.opacity(alpha * 0.85)), lineWidth: 0.75)
            }
        }
    }

    // MARK: - 2. SPECTRUM Polar RF SNR Field (Fallback when scan lobes empty)

    private func drawSpectrumField(ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width * 0.50, y: size.height * 0.58)
        let maxR = min(size.width * 0.28, size.height * 0.37)

        for frac in [0.36, 0.68, 1.0] as [CGFloat] {
            let r = maxR * frac
            ctx.stroke(
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                with: .color(Color.white.opacity(frac == 1.0 ? 0.14 : 0.08)),
                lineWidth: 0.75
            )
        }

        let sigFrac = CGFloat(state.wifi.isConnected ? max(0.20, state.wifi.signalFraction) : 0.14)
        let snrRatio = CGFloat(min(max(Double(state.wifi.snr) / 45.0, 0.1), 1.0))
        let loops = 18
        for k in 0..<loops {
            let fk = Double(k)
            let phase = fk / Double(loops) * Double.pi * 2.0 + time * 0.36
            let alpha = 0.08 + (k % 3 == 0 ? 0.44 : 0.14)
            var p = Path()
            let steps = 68
            for i in 0...steps {
                let u = Double(i) / Double(steps) * Double.pi * 2.0
                let ripple = (1.0 - Double(snrRatio)) * 0.16 * sin(u * 5.0 + phase * 1.7)
                    + 0.06 * cos(u * 3.0 - time * 1.05 + fk)
                let rad = maxR * sigFrac * CGFloat(0.66 + 0.30 * sin(fk * 0.65) + ripple)
                let pt = CGPoint(x: center.x + CGFloat(cos(u)) * rad, y: center.y + CGFloat(sin(u)) * rad * 0.90)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(auraColor.opacity(alpha)), lineWidth: k % 4 == 0 ? 1.15 : 0.65)
        }

        let sweepAngle = time * 0.50
        var sweep = Path()
        sweep.move(to: center)
        sweep.addLine(to: CGPoint(
            x: center.x + CGFloat(cos(sweepAngle)) * maxR,
            y: center.y + CGFloat(sin(sweepAngle)) * maxR
        ))
        ctx.stroke(sweep, with: .color(Color.white.opacity(0.24)), lineWidth: 0.85)

        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - 2.8, y: center.y - 2.8, width: 5.6, height: 5.6)),
            with: .color(.white)
        )
    }

    // MARK: - 3. ROUTE Architectural Curved Circuit with Comet-Tail Packets

    private func drawRouteCircuit(ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let baseY = size.height * 0.61
        let pts: [CGPoint] = [
            CGPoint(x: size.width * 0.13, y: baseY + 6),
            CGPoint(x: size.width * 0.38, y: baseY - 5),
            CGPoint(x: size.width * 0.62, y: baseY - 5),
            CGPoint(x: size.width * 0.87, y: baseY + 6)
        ]
        let labels = state.isProMode ? ["MAC", "ROUTER", "DNS", "WEB"] : ["MAC", "ROUTER", "LOOKUP", "INTERNET"]
        let latencies: [Double?] = [
            state.wifi.isConnected ? Double(state.wifi.snr) : nil,
            state.hopHealth.routerMs,
            state.hopHealth.dnsMs,
            state.hopHealth.internetMs
        ]
        let hasVPN = state.activeVPN != nil || state.dns.hasTunnelResolver

        // VPN frosted shield envelope spanning Router -> Internet
        if hasVPN {
            let tunnelRect = CGRect(x: pts[1].x - 20, y: baseY - 30, width: (pts[3].x - pts[1].x) + 40, height: 58)
            let envPath = Path(roundedRect: tunnelRect, cornerRadius: 14)
            let shieldGreen = Color(red: 0.26, green: 0.90, blue: 0.64)
            ctx.fill(envPath, with: .color(shieldGreen.opacity(0.055)))
            ctx.stroke(
                envPath,
                with: .color(shieldGreen.opacity(0.38)),
                style: StrokeStyle(lineWidth: 0.9, dash: [4.0, 3.0])
            )
            let vpnTitle = (state.activeVPN?.name ?? "TUNNEL").uppercased()
            let vpnText = Text("ENCRYPTED · \(vpnTitle)")
                .font(.system(size: 7.4, weight: .semibold, design: .monospaced))
                .foregroundColor(shieldGreen.opacity(0.88))
            ctx.draw(vpnText, at: CGPoint(x: tunnelRect.midX, y: tunnelRect.maxY + 8), anchor: .center)
        }

        // Draw curved Bézier circuit traces with comet-tail packet pulses
        for i in 0..<(pts.count - 1) {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            let ctrl = CGPoint(x: (p0.x + p1.x) * 0.5, y: min(p0.y, p1.y) - 10)
            let hopMs = latencies[i + 1]
            let traceColor = hopColor(ms: hopMs, encrypted: hasVPN && i >= 1)

            var curve = Path()
            curve.move(to: p0)
            curve.addQuadCurve(to: p1, control: ctrl)
            ctx.stroke(curve, with: .color(traceColor.opacity(0.14)), lineWidth: 4.0)
            ctx.stroke(curve, with: .color(traceColor.opacity(0.42)), lineWidth: 1.15)

            if state.wifi.isConnected || state.isWired {
                let speed = hopMs.map { max(0.32, min(1.5, 28.0 / max($0, 4.0))) } ?? 0.45
                let frac = (time * speed + Double(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
                // Draw 5 trailing comet pearls along the quadratic Bézier
                for step in 0..<5 {
                    let tPos = max(0.0, frac - Double(step) * 0.035)
                    let pt = quadBezierPoint(p0: p0, ctrl: ctrl, p1: p1, t: CGFloat(tPos))
                    let r = CGFloat(2.5 - Double(step) * 0.35)
                    let a = 0.98 - Double(step) * 0.19
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                        with: .color(step == 0 ? .white : traceColor.opacity(a))
                    )
                }
            }

            let midPt = quadBezierPoint(p0: p0, ctrl: ctrl, p1: p1, t: 0.5)
            let labelStr = state.isProMode ? ByteRateFormatter.ms(hopMs) : HumanSummary.humanHopLabel(ms: hopMs, warn: 45, bad: 110)
            let text = Text(labelStr)
                .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
                .foregroundColor(traceColor.opacity(0.92))
            ctx.draw(text, at: CGPoint(x: midPt.x, y: midPt.y - 11), anchor: .center)
        }

        // Draw 4 sculptural nodes with breathing halo
        let pulse = 0.5 + 0.5 * sin(time * 2.4)
        for i in 0..<pts.count {
            let pt = pts[i]
            let active = (i == 0) || (latencies[i] != nil)
            let nodeColor = i == 0 ? Color.white : hopColor(ms: latencies[i], encrypted: hasVPN && i >= 2)
            let r: CGFloat = 10.5

            if active {
                let haloR = r + CGFloat(2.5 + pulse * 2.5)
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: pt.x - haloR, y: pt.y - haloR, width: haloR * 2, height: haloR * 2)),
                    with: .color(nodeColor.opacity(0.14 * (1.0 - pulse * 0.5))),
                    lineWidth: 0.9
                )
            }

            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                with: .color(Color(red: 0.026, green: 0.030, blue: 0.040))
            )
            ctx.stroke(
                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                with: .color(nodeColor.opacity(active ? 0.88 : 0.25)),
                lineWidth: 1.2
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - 2.6, y: pt.y - 2.6, width: 5.2, height: 5.2)),
                with: .color(nodeColor.opacity(active ? 0.98 : 0.30))
            )

            let lbl = Text(labels[i])
                .font(.system(size: 7.6, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(active ? 0.74 : 0.34))
            ctx.draw(lbl, at: CGPoint(x: pt.x, y: pt.y + 18), anchor: .center)
        }
    }

    // MARK: - Math & Styling Helpers

    private func quadBezierPoint(p0: CGPoint, ctrl: CGPoint, p1: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1.0 - t
        let x = u * u * p0.x + 2 * u * t * ctrl.x + t * t * p1.x
        let y = u * u * p0.y + 2 * u * t * ctrl.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }

    private func smoothPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count >= 2 else { return path }
        path.move(to: pts[0])
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) * 0.5, y: (pts[i - 1].y + pts[i].y) * 0.5)
            path.addQuadCurve(to: mid, control: pts[i - 1])
        }
        path.addLine(to: pts.last!)
        return path
    }

    private func hopColor(ms: Double?, encrypted: Bool) -> Color {
        guard let ms else { return Color.white.opacity(0.32) }
        if ms > 110 { return Color(red: 1.0, green: 0.45, blue: 0.42) }
        if ms > 45 { return Color(red: 1.0, green: 0.78, blue: 0.42) }
        return encrypted
            ? Color(red: 0.30, green: 0.90, blue: 0.65)
            : Color(red: 0.78, green: 0.90, blue: 1.0)
    }

    private func revealSwitcherBriefly() {
        peekTask?.cancel()
        peekSwitcher = true
        peekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            peekSwitcher = false
        }
    }

    private var stageFooterReadout: String {
        switch state.stageMode {
        case .flux:
            let d = ByteRateFormatter.detailed(state.currentThroughput.downloadBytesPerSec)
            let u = ByteRateFormatter.detailed(state.currentThroughput.uploadBytesPerSec)
            return "↓ \(d)  ·  ↑ \(u)"
        case .spectrum:
            if state.wifi.isConnected {
                return "\(state.rfPhysics.signalPowerLabel.uppercased()) · \(state.rfPhysics.snrMultiplierLabel.uppercased()) · \(state.rfPhysics.estimatedRangeLabel.uppercased())"
            }
            return state.isWired ? "WIRED INTERFACE ACTIVE" : "RADIO IDLE"
        case .route:
            return state.hopHealth.bottleneckSummary.uppercased()
        }
    }

    private var auraColor: Color {
        switch state.trustAudit.level {
        case .shielded: return Color(red: 0.28, green: 0.88, blue: 0.68)
        case .trusted:  return Color(red: 0.60, green: 0.78, blue: 1.00)
        case .caution:  return Color(red: 1.00, green: 0.76, blue: 0.42)
        case .alert:    return Color(red: 1.00, green: 0.42, blue: 0.40)
        case .offline:  return Color(red: 0.68, green: 0.74, blue: 0.82)
        }
    }

    private var trustAccent: Color {
        switch state.trustAudit.level {
        case .shielded: return Color(red: 0.25, green: 0.92, blue: 0.64)
        case .trusted:  return Color(red: 0.72, green: 0.88, blue: 1.00)
        case .caution:  return Color(red: 1.00, green: 0.74, blue: 0.34)
        case .alert:    return Color(red: 1.00, green: 0.42, blue: 0.38)
        case .offline:  return Color.white.opacity(0.38)
        }
    }
}

private struct StagePowerButton: View {
    let isOn: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 9.8, weight: .semibold))
                .foregroundColor(isOn ? Color.white.opacity(hovered ? 1.0 : 0.78) : Color(red: 1.0, green: 0.56, blue: 0.52))
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(hovered ? 0.72 : 0.48))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(hovered ? 0.32 : 0.14), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(isOn ? "Turn Wi-Fi Off" : "Turn Wi-Fi On")
        .accessibilityLabel(isOn ? "Turn Wi-Fi Off" : "Turn Wi-Fi On")
    }
}

private struct StageExpandButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9.2, weight: .medium))
                .foregroundColor(Color.white.opacity(hovered ? 0.98 : 0.58))
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(hovered ? 0.72 : 0.48))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(hovered ? 0.32 : 0.14), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open Aether Studio — RF Spectrum, Jitter Timeline & LAN Map (⌘E)")
        .accessibilityLabel("Open Aether Studio Window")
    }
}
