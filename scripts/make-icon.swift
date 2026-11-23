import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift make-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    // macOS squircle-like rounded rect
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = rect.width * 0.225
    let clipPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()

    // Deep anodized obsidian-sapphire backdrop with top optical depth
    let cs = CGColorSpaceCreateDeviceRGB()
    let bgGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.085, green: 0.135, blue: 0.205, alpha: 1),
            CGColor(red: 0.036, green: 0.055, blue: 0.088, alpha: 1),
            CGColor(red: 0.016, green: 0.022, blue: 0.036, alpha: 1)
        ] as CFArray,
        locations: [0.0, 0.54, 1.0]
    )!
    ctx.drawRadialGradient(
        bgGrad,
        startCenter: CGPoint(x: s * 0.5, y: s * 0.62),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.5, y: s * 0.48),
        endRadius: s * 0.58,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Subtle sea-glass emerald optical glow rising from the focal beacon
    let origin = CGPoint(x: s * 0.5, y: s * 0.345)
    let coreGlow = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.24, green: 0.90, blue: 0.66, alpha: 0.32),
            CGColor(red: 0.24, green: 0.90, blue: 0.66, alpha: 0.08),
            CGColor(red: 0.24, green: 0.90, blue: 0.66, alpha: 0.0)
        ] as CFArray,
        locations: [0.0, 0.42, 1.0]
    )!
    ctx.drawRadialGradient(coreGlow, startCenter: origin, startRadius: 0, endCenter: origin, endRadius: s * 0.36, options: [.drawsBeforeStartLocation])

    // Subtle precision concentric RF calibration rings
    ctx.setStrokeColor(CGColor(red: 0.78, green: 0.90, blue: 1.0, alpha: 0.11))
    ctx.setLineWidth(max(1.0, s * 0.0032))
    ctx.strokeEllipse(in: CGRect(x: s * 0.175, y: s * 0.175, width: s * 0.65, height: s * 0.65))
    ctx.setStrokeColor(CGColor(red: 0.78, green: 0.90, blue: 1.0, alpha: 0.065))
    ctx.strokeEllipse(in: CGRect(x: s * 0.285, y: s * 0.285, width: s * 0.43, height: s * 0.43))

    // Luminous precision RF wavefront arcs radiating cleanly above the focal point (zero overlap!)
    let radii: [(CGFloat, CGFloat, CGFloat)] = [
        (s * 0.135, 0.96, 0.028),
        (s * 0.235, 0.80, 0.024),
        (s * 0.335, 0.52, 0.020),
        (s * 0.430, 0.24, 0.015)
    ]
    ctx.setLineCap(.round)
    for (r, alpha, lwFrac) in radii {
        // Soft outer bloom pass
        ctx.setStrokeColor(CGColor(red: 0.70, green: 0.90, blue: 1.0, alpha: alpha * 0.24))
        ctx.setLineWidth(max(2.0, s * lwFrac * 2.1))
        ctx.beginPath()
        ctx.addArc(center: origin, radius: r, startAngle: .pi * 0.24, endAngle: .pi * 0.76, clockwise: false)
        ctx.strokePath()

        // Razor-sharp core arc
        ctx.setStrokeColor(CGColor(red: 0.93, green: 0.97, blue: 1.0, alpha: alpha))
        ctx.setLineWidth(max(1.4, s * lwFrac))
        ctx.beginPath()
        ctx.addArc(center: origin, radius: r, startAngle: .pi * 0.24, endAngle: .pi * 0.76, clockwise: false)
        ctx.strokePath()
    }

    // Sea-glass emerald focal beacon (Aether signature)
    let dotR = s * 0.044
    ctx.setFillColor(CGColor(red: 0.26, green: 0.92, blue: 0.66, alpha: 0.30))
    ctx.fillEllipse(in: CGRect(x: origin.x - dotR * 1.65, y: origin.y - dotR * 1.65, width: dotR * 3.3, height: dotR * 3.3))
    ctx.setFillColor(CGColor(red: 0.28, green: 0.92, blue: 0.66, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: origin.x - dotR, y: origin.y - dotR, width: dotR * 2, height: dotR * 2))
    // Tiny crisp inner specular highlight
    let specR = dotR * 0.38
    ctx.setFillColor(CGColor(red: 0.88, green: 1.0, blue: 0.95, alpha: 0.72))
    ctx.fillEllipse(in: CGRect(x: origin.x - specR, y: origin.y + dotR * 0.12 - specR, width: specR * 2, height: specR * 2))

    // Anodized sapphire-glass outer specular rim
    ctx.addPath(clipPath)
    ctx.setStrokeColor(CGColor(red: 0.84, green: 0.92, blue: 1.0, alpha: 0.28))
    ctx.setLineWidth(max(1.2, s * 0.009))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    if let data = renderIcon(size: px) {
        try data.write(to: outDir.appendingPathComponent(name))
    }
}
