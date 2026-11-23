import AetherCore
import SwiftUI

/// Precision Swiss monochrome geometric emblems matching Satie's Dieter Rams aesthetic:
/// SPEED (calibrated dial & live needle) · PRIVACY (faceted architectural shield + core) ·
/// WI-FI (concentric RF wavefronts) · MORE (precision sliders / calibration nodes).
struct AetherTabGlyph: View {
    let tab: PanelTab
    let isActive: Bool
    var badgeColor: Color? = nil
    var size: CGFloat = 38

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width * 0.5, y: sz.height * 0.5)
                let r = min(sz.width, sz.height) * 0.44
                let lw: CGFloat = max(1.15, size * 0.034)
                let thinLW: CGFloat = max(0.95, lw * 0.78)

                let primary: Color = isActive ? .black : Color.white.opacity(isHovered ? 0.96 : 0.78)
                let secondary: Color = isActive ? .black.opacity(0.42) : Color.white.opacity(isHovered ? 0.48 : 0.30)
                let strokeStyle = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
                let thinStyle = StrokeStyle(lineWidth: thinLW, lineCap: .round, lineJoin: .round)

                let outer = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                if isActive {
                    ctx.fill(outer, with: .color(.white))
                } else {
                    ctx.fill(outer, with: .color(Color.white.opacity(isHovered ? 0.095 : 0.038)))
                    ctx.stroke(outer, with: .color(Color.white.opacity(isHovered ? 0.46 : 0.20)), lineWidth: thinLW)
                }

                let ir = r * 0.62

                switch tab {
                case .speed:
                    var arc = Path()
                    arc.addArc(
                        center: CGPoint(x: center.x, y: center.y + ir * 0.12),
                        radius: ir * 0.88,
                        startAngle: .degrees(150),
                        endAngle: .degrees(390),
                        clockwise: false
                    )
                    ctx.stroke(arc, with: .color(secondary), style: thinStyle)

                    var activeArc = Path()
                    activeArc.addArc(
                        center: CGPoint(x: center.x, y: center.y + ir * 0.12),
                        radius: ir * 0.88,
                        startAngle: .degrees(150),
                        endAngle: .degrees(305),
                        clockwise: false
                    )
                    ctx.stroke(activeArc, with: .color(primary), style: strokeStyle)

                    let pivot = CGPoint(x: center.x, y: center.y + ir * 0.16)
                    let angle = -42.0 * Double.pi / 180.0
                    let tip = CGPoint(
                        x: pivot.x + CGFloat(cos(angle)) * ir * 0.72,
                        y: pivot.y + CGFloat(sin(angle)) * ir * 0.72
                    )
                    var needle = Path()
                    needle.move(to: pivot)
                    needle.addLine(to: tip)
                    ctx.stroke(needle, with: .color(primary), style: strokeStyle)

                    let dotR: CGFloat = max(1.8, size * 0.052)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: pivot.x - dotR, y: pivot.y - dotR, width: dotR * 2, height: dotR * 2)),
                        with: .color(primary)
                    )

                case .shield:
                    let topY = center.y - ir * 0.88
                    let shoulderY = center.y - ir * 0.56
                    let midY = center.y + ir * 0.08
                    let botY = center.y + ir * 0.90
                    let halfW = ir * 0.74

                    var shield = Path()
                    shield.move(to: CGPoint(x: center.x, y: topY))
                    shield.addLine(to: CGPoint(x: center.x + halfW, y: shoulderY))
                    shield.addLine(to: CGPoint(x: center.x + halfW, y: midY))
                    shield.addQuadCurve(
                        to: CGPoint(x: center.x, y: botY),
                        control: CGPoint(x: center.x + halfW * 0.76, y: botY - ir * 0.22)
                    )
                    shield.addQuadCurve(
                        to: CGPoint(x: center.x - halfW, y: midY),
                        control: CGPoint(x: center.x - halfW * 0.76, y: botY - ir * 0.22)
                    )
                    shield.addLine(to: CGPoint(x: center.x - halfW, y: shoulderY))
                    shield.closeSubpath()
                    ctx.stroke(shield, with: .color(primary), style: strokeStyle)

                    let coreR: CGFloat = max(1.8, size * 0.052)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)),
                        with: .color(secondary)
                    )

                case .networks:
                    let origin = CGPoint(x: center.x, y: center.y + ir * 0.56)
                    let radii: [(CGFloat, Bool)] = [
                        (ir * 0.48, true),
                        (ir * 0.86, true),
                        (ir * 1.24, false)
                    ]
                    for (rad, bright) in radii {
                        var arc = Path()
                        arc.addArc(
                            center: origin,
                            radius: rad,
                            startAngle: .degrees(225),
                            endAngle: .degrees(315),
                            clockwise: false
                        )
                        ctx.stroke(arc, with: .color(bright ? primary : secondary), style: strokeStyle)
                    }
                    let dotR: CGFloat = max(1.9, size * 0.055)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: origin.x - dotR, y: origin.y - dotR, width: dotR * 2, height: dotR * 2)),
                        with: .color(primary)
                    )

                case .tools:
                    let offsets: [(y: CGFloat, knob: CGFloat, bright: Bool)] = [
                        (-0.56, -0.28, true),
                        ( 0.00,  0.32, true),
                        ( 0.56, -0.10, false)
                    ]
                    let halfSpan = ir * 0.84
                    let knobR = max(2.0, size * 0.055)
                    for row in offsets {
                        let y = center.y + row.y * ir
                        let kx = center.x + row.knob * halfSpan
                        var line = Path()
                        line.move(to: CGPoint(x: center.x - halfSpan, y: y))
                        line.addLine(to: CGPoint(x: center.x + halfSpan, y: y))
                        ctx.stroke(line, with: .color(secondary), style: thinStyle)

                        let knob = Path(ellipseIn: CGRect(x: kx - knobR, y: y - knobR, width: knobR * 2, height: knobR * 2))
                        ctx.fill(knob, with: .color(isActive ? .white : Color(red: 0.032, green: 0.036, blue: 0.044)))
                        ctx.stroke(knob, with: .color(row.bright ? primary : secondary), style: strokeStyle)
                    }
                }
            }
            .frame(width: size, height: size)

            if let badgeColor, !isActive {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 6.5, height: 6.5)
                    .overlay(Circle().stroke(Color(red: 0.032, green: 0.036, blue: 0.044), lineWidth: 1.4))
                    .offset(x: -1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .background {
            if isActive {
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: size + 6, height: size + 6)
                    .blur(radius: 6)
            }
        }
        .scaleEffect(isHovered && !isActive ? 1.04 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.26, dampingFraction: 0.80), value: isActive)
        .onHover { isHovered = $0 }
        .accessibilityHidden(true)
    }
}

/// Crisp 4-bar architectural signal meter for nearby network rows.
struct MiniSignalBars: View {
    let bars: Int
    var width: CGFloat = 15
    var height: CGFloat = 11

    var body: some View {
        Canvas { ctx, sz in
            let count = 4
            let barW: CGFloat = 2.0
            let gap: CGFloat = 1.6
            let totalW = CGFloat(count) * barW + CGFloat(count - 1) * gap
            let startX = (sz.width - totalW) * 0.5
            let fracs: [CGFloat] = [0.34, 0.56, 0.78, 1.0]
            for i in 0..<count {
                let bh = sz.height * fracs[i]
                let rect = CGRect(x: startX + CGFloat(i) * (barW + gap), y: sz.height - bh, width: barW, height: bh)
                let active = i < bars
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: 0.9),
                    with: .color(Color.white.opacity(active ? 0.94 : 0.18))
                )
            }
        }
        .frame(width: width, height: height)
    }
}
