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

    // Midnight-slate Strange Chances radial gradient
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.09, green: 0.16, blue: 0.24, alpha: 1),
            CGColor(red: 0.040, green: 0.065, blue: 0.105, alpha: 1),
            CGColor(red: 0.022, green: 0.032, blue: 0.052, alpha: 1)
        ] as CFArray,
        locations: [0.0, 0.56, 1.0]
    )!
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    ctx.drawRadialGradient(grad, startCenter: center, startRadius: s * 0.04, endCenter: center, endRadius: s * 0.56, options: [])

    // Subtle precision concentric RF calibration rings
    ctx.setStrokeColor(CGColor(red: 0.78, green: 0.90, blue: 1.0, alpha: 0.13))
    ctx.setLineWidth(max(1.0, s * 0.004))
    ctx.strokeEllipse(in: CGRect(x: s * 0.17, y: s * 0.17, width: s * 0.66, height: s * 0.66))
    ctx.setStrokeColor(CGColor(red: 0.78, green: 0.90, blue: 1.0, alpha: 0.08))
    ctx.strokeEllipse(in: CGRect(x: s * 0.27, y: s * 0.27, width: s * 0.46, height: s * 0.46))

    // Luminous precision RF wavefront arcs radiating from lower focal point
    let origin = CGPoint(x: s * 0.5, y: s * 0.35)
    let radii: [(CGFloat, CGFloat, CGFloat)] = [
        (s * 0.13, 0.94, 0.022),
        (s * 0.23, 0.80, 0.019),
        (s * 0.33, 0.56, 0.016),
        (s * 0.43, 0.28, 0.012)
    ]
    ctx.setLineCap(.round)
    for (r, alpha, lwFrac) in radii {
        ctx.setStrokeColor(CGColor(red: 0.92, green: 0.97, blue: 1.0, alpha: alpha))
        ctx.setLineWidth(max(1.2, s * lwFrac))
        ctx.beginPath()
        ctx.addArc(center: origin, radius: r, startAngle: .pi * 0.24, endAngle: .pi * 0.76, clockwise: false)
        ctx.strokePath()
    }

    // Sea-glass emerald shield core point (Aether focal signature)
    let dotR = s * 0.036
    ctx.setFillColor(CGColor(red: 0.28, green: 0.90, blue: 0.66, alpha: 0.98))
    ctx.fillEllipse(in: CGRect(x: origin.x - dotR, y: origin.y - dotR, width: dotR * 2, height: dotR * 2))

    // Crisp outer rim stroke
    ctx.addPath(clipPath)
    ctx.setStrokeColor(CGColor(red: 0.84, green: 0.92, blue: 1.0, alpha: 0.26))
    ctx.setLineWidth(max(1.0, s * 0.008))
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
