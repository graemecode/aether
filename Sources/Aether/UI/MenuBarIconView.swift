import AetherCore
import AppKit
import Foundation

/// Ultra-tight fixed-width Retina menu bar instrument inspired by Braun / Satie geometry.
/// Every display mode uses a 100% constant width so the menu bar NEVER shifts other icons left or right:
///   - `.iconOnly`    (22pt fixed): 3-arc geometric Wi-Fi emblem + integrated trust focal dot.
///   - `.autoSpeed`   (28pt fixed, DEFAULT): Wi-Fi emblem + two color-coded micro `▾ / ▴` speed arrows
///                    whose luminance & hue encode live download/upload intensity (idle -> trickle -> active -> burst).
///   - `.alwaysSpeed` (50pt fixed): Wi-Fi emblem + compact right-aligned numeric `▾ 41M / ▴ 6.5M` stack.
final class MenuBarIconView: NSView {
    private var signalBars: Int = 0
    private var isPowerOn: Bool = true
    private var isConnected: Bool = false
    private var isWired: Bool = false
    private var trustLevel: TrustLevel = .offline
    private var downloadRate: Double = 0
    private var uploadRate: Double = 0
    private var displayMode: MenuBarDisplayMode = .autoSpeed

    static let iconOnlyWidth: CGFloat = 22
    static let activityArrowsWidth: CGFloat = 28
    static let iconWithSpeedWidth: CGFloat = 50

    static func width(for mode: MenuBarDisplayMode) -> CGFloat {
        switch mode {
        case .iconOnly:    return iconOnlyWidth
        case .autoSpeed:   return activityArrowsWidth
        case .alwaysSpeed: return iconWithSpeedWidth
        }
    }

    var preferredWidth: CGFloat {
        Self.width(for: displayMode)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func update(
        wifi: WiFiSnapshot,
        audit: TrustAudit,
        throughput: ThroughputSample,
        mode: MenuBarDisplayMode,
        isWired: Bool
    ) -> Bool {
        let oldWidth = preferredWidth

        self.signalBars = wifi.signalBars
        self.isPowerOn = wifi.powerOn
        self.isConnected = wifi.isConnected || isWired
        self.isWired = isWired
        self.trustLevel = audit.level
        self.downloadRate = throughput.downloadBytesPerSec
        self.uploadRate = throughput.uploadBytesPerSec
        self.displayMode = mode

        needsDisplay = true
        return preferredWidth != oldWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let h = bounds.height

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let inkGray: CGFloat = isDark ? 1.0 : 0.0

        // Center of the 13.4pt-wide Wi-Fi emblem (left-anchored when paired with arrows/speed, centered when icon-only)
        let glyphCenterX: CGFloat = displayMode == .iconOnly ? bounds.width * 0.5 : 8.5
        let midY: CGFloat = h * 0.5

        if isWired {
            drawWiredGlyph(ctx: ctx, cx: glyphCenterX, midY: midY, inkGray: inkGray)
        } else {
            drawWiFiArcs(ctx: ctx, cx: glyphCenterX, midY: midY, inkGray: inkGray)
        }

        switch displayMode {
        case .iconOnly:
            break
        case .autoSpeed:
            drawColorActivityArrows(ctx: ctx, cx: 21.5, midY: midY, inkGray: inkGray, isDark: isDark)
        case .alwaysSpeed:
            drawTightSpeedStack(ctx: ctx, startX: 18.0, midY: midY, inkGray: inkGray)
        }
    }

    // MARK: - Geometric 3-Arc Wi-Fi Emblem + Integrated Trust Focal Dot

    private func drawWiFiArcs(ctx: CGContext, cx: CGFloat, midY: CGFloat, inkGray: CGFloat) {
        // Origin sits at bottom of the 12pt tall silhouette so arcs sweep symmetrically upward
        let origin = CGPoint(x: cx, y: midY - 4.7)
        let radii: [CGFloat] = [4.1, 6.8, 9.5]
        let startAngle: CGFloat = .pi * 0.25 // 45° (upper-right)
        let endAngle: CGFloat = .pi * 0.75   // 135° (upper-left)

        ctx.setLineCap(.round)
        ctx.setLineWidth(1.42)

        for (idx, r) in radii.enumerated() {
            let neededBars = idx + 2 // inner=2, mid=3, outer=4
            let active = isPowerOn && isConnected && (signalBars >= neededBars)
            let alpha: CGFloat
            if !isPowerOn {
                alpha = 0.24
            } else if !isConnected {
                alpha = 0.30
            } else {
                alpha = active ? 0.94 : 0.24
            }
            ctx.setStrokeColor(gray: inkGray, alpha: alpha)
            ctx.beginPath()
            ctx.addArc(center: origin, radius: r, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            ctx.strokePath()
        }

        // Focal origin dot doubles as the semantic trust indicator (zero extra horizontal space!)
        let dotR: CGFloat = 1.68
        let dotRect = CGRect(x: origin.x - dotR, y: origin.y - dotR, width: dotR * 2, height: dotR * 2)
        if let trustColor = trustDotColor {
            ctx.setFillColor(trustColor)
        } else {
            let dotAlpha: CGFloat = (isPowerOn && isConnected) ? 0.96 : 0.34
            ctx.setFillColor(gray: inkGray, alpha: dotAlpha)
        }
        ctx.fillEllipse(in: dotRect)

        // Crisp diagonal slash when Wi-Fi radio is off
        if !isPowerOn {
            ctx.setStrokeColor(gray: inkGray, alpha: 0.88)
            ctx.setLineWidth(1.25)
            ctx.move(to: CGPoint(x: cx - 6.0, y: midY - 5.2))
            ctx.addLine(to: CGPoint(x: cx + 6.0, y: midY + 5.6))
            ctx.strokePath()
        }
    }

    private func drawWiredGlyph(ctx: CGContext, cx: CGFloat, midY: CGFloat, inkGray: CGFloat) {
        ctx.setStrokeColor(gray: inkGray, alpha: 0.90)
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - 5.5, y: midY))
        ctx.addLine(to: CGPoint(x: cx + 5.5, y: midY))
        ctx.strokePath()

        let dotR: CGFloat = 2.2
        ctx.setFillColor(trustDotColor ?? CGColor(gray: inkGray, alpha: 0.96))
        ctx.fillEllipse(in: CGRect(x: cx - dotR, y: midY - dotR, width: dotR * 2, height: dotR * 2))
    }

    // MARK: - Fixed-Width Color-Coded Speed Activity Arrows (28pt Total — Zero Menu Bar Shifting)

    /// Encodes live download (top ▾) & upload (bottom ▴) speed tiers via color & luminance in a constant 8pt slot:
    ///   - Idle (< 1 KB/s):        whisper dim monochrome (18% alpha)
    ///   - Trickle (1–80 KB/s):    crisp soft monochrome (56% alpha)
    ///   - Active (80 KB/s–2 MB/s): luminous ice-blue (down) / warm amber (up)
    ///   - Burst (>= 2 MB/s):      vivid cyan-emerald (down) / bright coral-gold (up) + subtle crisp glow
    private func drawColorActivityArrows(ctx: CGContext, cx: CGFloat, midY: CGFloat, inkGray: CGFloat, isDark: Bool) {
        let downColor = activityColor(bytesPerSec: isConnected ? downloadRate : 0, isUpload: false, inkGray: inkGray, isDark: isDark)
        let upColor = activityColor(bytesPerSec: isConnected ? uploadRate : 0, isUpload: true, inkGray: inkGray, isDark: isDark)

        drawActivityChevron(ctx: ctx, cx: cx, cy: midY + 3.8, pointingUp: false, color: downColor.fill, glow: downColor.glow)
        drawActivityChevron(ctx: ctx, cx: cx, cy: midY - 3.8, pointingUp: true, color: upColor.fill, glow: upColor.glow)
    }

    private func activityColor(bytesPerSec: Double, isUpload: Bool, inkGray: CGFloat, isDark: Bool) -> (fill: CGColor, glow: CGColor?) {
        if bytesPerSec < 1_024 {
            return (CGColor(gray: inkGray, alpha: 0.20), nil)
        }
        if bytesPerSec < 80_000 {
            return (CGColor(gray: inkGray, alpha: 0.58), nil)
        }
        if bytesPerSec < 2_000_000 {
            if isUpload {
                let c = isDark
                    ? CGColor(red: 1.00, green: 0.74, blue: 0.34, alpha: 0.94)
                    : CGColor(red: 0.86, green: 0.48, blue: 0.04, alpha: 0.95)
                return (c, nil)
            } else {
                let c = isDark
                    ? CGColor(red: 0.52, green: 0.84, blue: 1.00, alpha: 0.94)
                    : CGColor(red: 0.06, green: 0.46, blue: 0.88, alpha: 0.95)
                return (c, nil)
            }
        }
        // Heavy burst (>= 2 MB/s)
        if isUpload {
            let c = isDark
                ? CGColor(red: 1.00, green: 0.56, blue: 0.26, alpha: 1.0)
                : CGColor(red: 0.88, green: 0.32, blue: 0.08, alpha: 1.0)
            let g = CGColor(red: 1.00, green: 0.62, blue: 0.28, alpha: 0.42)
            return (c, g)
        } else {
            let c = isDark
                ? CGColor(red: 0.24, green: 0.94, blue: 0.74, alpha: 1.0)
                : CGColor(red: 0.02, green: 0.58, blue: 0.48, alpha: 1.0)
            let g = CGColor(red: 0.28, green: 0.94, blue: 0.78, alpha: 0.42)
            return (c, g)
        }
    }

    private func drawActivityChevron(ctx: CGContext, cx: CGFloat, cy: CGFloat, pointingUp: Bool, color: CGColor, glow: CGColor?) {
        let halfW: CGFloat = 2.75
        let halfH: CGFloat = 1.95
        ctx.saveGState()
        if let glow {
            ctx.setShadow(offset: .zero, blur: 2.6, color: glow)
        }
        ctx.setFillColor(color)
        ctx.beginPath()
        if pointingUp {
            ctx.move(to: CGPoint(x: cx, y: cy + halfH))
            ctx.addLine(to: CGPoint(x: cx + halfW, y: cy - halfH))
            ctx.addLine(to: CGPoint(x: cx - halfW, y: cy - halfH))
        } else {
            ctx.move(to: CGPoint(x: cx, y: cy - halfH))
            ctx.addLine(to: CGPoint(x: cx + halfW, y: cy + halfH))
            ctx.addLine(to: CGPoint(x: cx - halfW, y: cy + halfH))
        }
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - Compact Right-Aligned Speed Stack (50pt Total — Matches Native Menu Bar Density)

    private func drawTightSpeedStack(ctx: CGContext, startX: CGFloat, midY: CGFloat, inkGray: CGFloat) {
        let downActive = downloadRate >= 1_024
        let upActive = uploadRate >= 1_024
        let downDominant = downloadRate >= uploadRate

        let downAlpha: CGFloat = downActive ? (downDominant ? 0.98 : 0.78) : 0.42
        let upAlpha: CGFloat = upActive ? (!downDominant ? 0.98 : 0.72) : 0.38

        // Top row (download): micro ▾ + compact right-aligned rate
        drawMicroArrow(ctx: ctx, cx: startX + 1.8, cy: midY + 4.0, pointingUp: false, gray: inkGray, alpha: downAlpha)
        // Bottom row (upload): micro ▴ + compact right-aligned rate
        drawMicroArrow(ctx: ctx, cx: startX + 1.8, cy: midY - 4.0, pointingUp: true, gray: inkGray, alpha: upAlpha)

        let textX = startX + 5.2
        let textW = max(12, bounds.width - textX - 1.5)

        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.lineBreakMode = .byClipping

        let downFont = NSFont.monospacedDigitSystemFont(ofSize: 8.3, weight: downDominant && downActive ? .semibold : .medium)
        let upFont = NSFont.monospacedDigitSystemFont(ofSize: 8.3, weight: !downDominant && upActive ? .semibold : .regular)

        let downAttrs: [NSAttributedString.Key: Any] = [
            .font: downFont,
            .foregroundColor: NSColor(white: inkGray, alpha: downAlpha),
            .paragraphStyle: para
        ]
        let upAttrs: [NSAttributedString.Key: Any] = [
            .font: upFont,
            .foregroundColor: NSColor(white: inkGray, alpha: upAlpha),
            .paragraphStyle: para
        ]

        let downStr = ByteRateFormatter.compact(downloadRate)
        let upStr = ByteRateFormatter.compact(uploadRate)

        let downRect = CGRect(x: textX, y: midY - 0.5, width: textW, height: 10.2)
        let upRect = CGRect(x: textX, y: midY - 8.8, width: textW, height: 10.2)
        (downStr as NSString).draw(in: downRect, withAttributes: downAttrs)
        (upStr as NSString).draw(in: upRect, withAttributes: upAttrs)
    }

    private func drawMicroArrow(ctx: CGContext, cx: CGFloat, cy: CGFloat, pointingUp: Bool, gray: CGFloat, alpha: CGFloat) {
        let halfW: CGFloat = 2.05
        let halfH: CGFloat = 1.45
        ctx.setFillColor(gray: gray, alpha: alpha)
        ctx.beginPath()
        if pointingUp {
            ctx.move(to: CGPoint(x: cx, y: cy + halfH))
            ctx.addLine(to: CGPoint(x: cx + halfW, y: cy - halfH))
            ctx.addLine(to: CGPoint(x: cx - halfW, y: cy - halfH))
        } else {
            ctx.move(to: CGPoint(x: cx, y: cy - halfH))
            ctx.addLine(to: CGPoint(x: cx + halfW, y: cy + halfH))
            ctx.addLine(to: CGPoint(x: cx - halfW, y: cy + halfH))
        }
        ctx.closePath()
        ctx.fillPath()
    }

    private var trustDotColor: CGColor? {
        switch trustLevel {
        case .shielded:
            return CGColor(red: 0.22, green: 0.90, blue: 0.62, alpha: 0.98) // Emerald shield origin
        case .trusted:
            return nil // Clean monochrome
        case .caution:
            return CGColor(red: 1.00, green: 0.74, blue: 0.30, alpha: 0.98) // Warm amber
        case .alert:
            return CGColor(red: 1.00, green: 0.40, blue: 0.36, alpha: 0.98) // Coral alert
        case .offline:
            return nil
        }
    }
}
