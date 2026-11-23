import AetherCore
import AppKit
import Foundation

/// Ultra-tight Retina menu bar instrument inspired by Braun / Satie geometry.
/// - Left: crisp 3-arc geometric Wi-Fi emblem whose focal origin dot doubles as the
///   semantic trust badge (emerald = VPN-shielded, monochrome = trusted, amber = caution, coral = alert).
/// - Right (optional, flush 3.5pt gap, left-aligned): compact two-row `▾ / ▴` speed readout
///   with custom CoreGraphics micro-arrows and tabular digits (`50pt` total width vs `20pt` icon-only).
final class MenuBarIconView: NSView {
    private var signalBars: Int = 0
    private var isPowerOn: Bool = true
    private var isConnected: Bool = false
    private var isWired: Bool = false
    private var trustLevel: TrustLevel = .offline
    private var downloadRate: Double = 0
    private var uploadRate: Double = 0
    private var showSpeedText: Bool = false

    static let iconOnlyWidth: CGFloat = 22
    static let iconWithSpeedWidth: CGFloat = 50

    var preferredWidth: CGFloat {
        showSpeedText ? Self.iconWithSpeedWidth : Self.iconOnlyWidth
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

        let activeTraffic = (downloadRate + uploadRate) >= 250_000 // only expand in Auto mode on real transfers (>= ~250 KB/s)
        switch mode {
        case .iconOnly:
            self.showSpeedText = false
        case .autoSpeed:
            self.showSpeedText = isConnected && activeTraffic
        case .alwaysSpeed:
            self.showSpeedText = isConnected
        }

        needsDisplay = true
        return preferredWidth != oldWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let h = bounds.height

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let inkGray: CGFloat = isDark ? 1.0 : 0.0

        // Center of the 13.4pt-wide Wi-Fi emblem (left-anchored when showing speed, centered when icon-only)
        let glyphCenterX: CGFloat = showSpeedText ? 8.5 : bounds.width * 0.5
        let midY: CGFloat = h * 0.5

        if isWired {
            drawWiredGlyph(ctx: ctx, cx: glyphCenterX, midY: midY, inkGray: inkGray)
        } else {
            drawWiFiArcs(ctx: ctx, cx: glyphCenterX, midY: midY, inkGray: inkGray)
        }

        if showSpeedText {
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
