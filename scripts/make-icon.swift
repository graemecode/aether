import AppKit
import CoreImage
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift make-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let ciContext = CIContext(options: [.useSoftwareRenderer: false])

/// Builds a gracefully tapered optical crescent arc (thickest at apex, tapering smoothly to fine tips)
/// rather than blunt uniform-width rounded strokes.
func makeTaperedArcPath(
    center: CGPoint,
    radius: CGFloat,
    halfAngle: CGFloat,
    maxHalfWidth: CGFloat,
    steps: Int = 120
) -> CGPath {
    let path = CGMutablePath()
    let startTheta = CGFloat.pi * 0.5 - halfAngle
    let endTheta = CGFloat.pi * 0.5 + halfAngle

    var outerPts: [CGPoint] = []
    var innerPts: [CGPoint] = []
    outerPts.reserveCapacity(steps + 1)
    innerPts.reserveCapacity(steps + 1)

    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)          // 0 ... 1
        let u = (t - 0.5) * 2.0                      // -1 ... +1 (0 at apex)
        let theta = startTheta + (endTheta - startTheta) * t
        // Smooth optical bell taper with crisp subtle tip sharpness
        let env = pow(max(0, cos(u * .pi * 0.5)), 1.28)
        let hw = maxHalfWidth * (0.06 + 0.94 * env)

        let cosT = cos(theta)
        let sinT = sin(theta)
        outerPts.append(CGPoint(x: center.x + (radius + hw) * cosT, y: center.y + (radius + hw) * sinT))
        innerPts.append(CGPoint(x: center.x + (radius - hw) * cosT, y: center.y + (radius - hw) * sinT))
    }

    if let first = outerPts.first {
        path.move(to: first)
        for pt in outerPts.dropFirst() { path.addLine(to: pt) }
        for pt in innerPts.reversed() { path.addLine(to: pt) }
        path.closeSubpath()
    }
    return path
}

func makeBitmapContext(size: Int) -> CGContext? {
    let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    return CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

func blurredImage(_ cgImage: CGImage, radius: CGFloat, size: Int) -> CGImage? {
    let input = CIImage(cgImage: cgImage)
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(radius, forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage else { return nil }
    return ciContext.createCGImage(output, from: CGRect(x: 0, y: 0, width: size, height: size))
}

func renderMaster1024() -> CGImage? {
    let size = 1024
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    guard let ctx = makeBitmapContext(size: size) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Apple macOS HIG squircle proportions (~824x824 centered inside 1024x1024, clean alpha edge — macOS & CSS apply shadow)
    let inset = s * 0.097
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = rect.width * 0.224
    let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Clip all interior layers to the sapphire-obsidian monolith
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // 1. Machined Sapphire-Obsidian Monolith Base (deep directional studio lighting, sibling to Satie)
    let baseGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.105, green: 0.145, blue: 0.215, alpha: 1.0),
            CGColor(red: 0.045, green: 0.064, blue: 0.100, alpha: 1.0),
            CGColor(red: 0.015, green: 0.021, blue: 0.035, alpha: 1.0),
            CGColor(red: 0.008, green: 0.012, blue: 0.022, alpha: 1.0)
        ] as CFArray,
        locations: [0.0, 0.36, 0.74, 1.0]
    )!
    ctx.drawLinearGradient(
        baseGrad,
        start: CGPoint(x: s * 0.5, y: rect.maxY),
        end: CGPoint(x: s * 0.5, y: rect.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // 2. Overhead Studio Key-Light Sheen (catches the upper sapphire crown just like Satie)
    let crownLight = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.62, green: 0.76, blue: 0.96, alpha: 0.36),
            CGColor(red: 0.34, green: 0.48, blue: 0.68, alpha: 0.13),
            CGColor(red: 0.12, green: 0.20, blue: 0.34, alpha: 0.0)
        ] as CFArray,
        locations: [0.0, 0.45, 1.0]
    )!
    ctx.drawRadialGradient(
        crownLight,
        startCenter: CGPoint(x: s * 0.5, y: rect.maxY + s * 0.02),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.5, y: rect.maxY - s * 0.06),
        endRadius: s * 0.46,
        options: [.drawsBeforeStartLocation]
    )

    // 3. Subtle Recessed Optical Lens Dish (Leica / Braun precision instrument housing — zero collisions!)
    let dishCenter = CGPoint(x: s * 0.5, y: s * 0.495)
    let dishR = s * 0.335
    let dishRect = CGRect(x: dishCenter.x - dishR, y: dishCenter.y - dishR, width: dishR * 2, height: dishR * 2)

    ctx.saveGState()
    ctx.addEllipse(in: dishRect)
    ctx.clip()
    let dishGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.010, green: 0.015, blue: 0.025, alpha: 0.52),
            CGColor(red: 0.022, green: 0.036, blue: 0.058, alpha: 0.18),
            CGColor(red: 0.060, green: 0.095, blue: 0.145, alpha: 0.12)
        ] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(
        dishGrad,
        start: CGPoint(x: s * 0.5, y: dishRect.maxY),
        end: CGPoint(x: s * 0.5, y: dishRect.minY),
        options: []
    )
    ctx.restoreGState()

    // Whisper-fine optical dish bezel ring (coated Leica glass whisper)
    ctx.saveGState()
    ctx.setLineWidth(s * 0.002)
    ctx.setStrokeColor(CGColor(red: 0.72, green: 0.86, blue: 1.0, alpha: 0.055))
    ctx.strokeEllipse(in: dishRect)
    ctx.restoreGState()

    // 4. Focal Origin & Ambient Sea-Glass Emerald Light Wash on the Obsidian Surface
    let origin = CGPoint(x: s * 0.5, y: s * 0.34)
    let emeraldWash = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.18, green: 0.92, blue: 0.66, alpha: 0.34),
            CGColor(red: 0.16, green: 0.76, blue: 0.74, alpha: 0.14),
            CGColor(red: 0.20, green: 0.52, blue: 0.86, alpha: 0.04),
            CGColor(red: 0.10, green: 0.20, blue: 0.40, alpha: 0.0)
        ] as CFArray,
        locations: [0.0, 0.34, 0.68, 1.0]
    )!
    ctx.drawRadialGradient(
        emeraldWash,
        startCenter: origin,
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.5, y: s * 0.44),
        endRadius: s * 0.40,
        options: [.drawsBeforeStartLocation]
    )

    // 5. Build Luminous Wavefront Layer (3 Precision Tapered Optical Arcs + Emerald Beacon)
    let arcSpecs: [(radius: CGFloat, halfAngle: CGFloat, halfWidth: CGFloat, alpha: CGFloat)] = [
        (s * 0.132, 0.80, s * 0.0145, 0.98),
        (s * 0.226, 0.80, s * 0.0135, 0.84),
        (s * 0.320, 0.80, s * 0.0118, 0.58)
    ]

    if let glowCtx = makeBitmapContext(size: size) {
        glowCtx.setAllowsAntialiasing(true)
        glowCtx.setShouldAntialias(true)

        for spec in arcSpecs {
            let p = makeTaperedArcPath(
                center: origin,
                radius: spec.radius,
                halfAngle: spec.halfAngle,
                maxHalfWidth: spec.halfWidth * 1.15
            )
            glowCtx.addPath(p)
            glowCtx.setFillColor(CGColor(red: 0.58, green: 0.88, blue: 1.0, alpha: spec.alpha))
            glowCtx.fillPath()
        }

        // Emerald emitter into bloom layer
        let glowDotR = s * 0.052
        glowCtx.setFillColor(CGColor(red: 0.22, green: 0.96, blue: 0.68, alpha: 1.0))
        glowCtx.fillEllipse(in: CGRect(x: origin.x - glowDotR, y: origin.y - glowDotR, width: glowDotR * 2, height: glowDotR * 2))

        if let rawLight = glowCtx.makeImage() {
            // Wide soft atmospheric bloom (true Gaussian, zero hard pill edge!)
            if let wideBlur = blurredImage(rawLight, radius: s * 0.036, size: size) {
                ctx.saveGState()
                ctx.setBlendMode(.screen)
                ctx.setAlpha(0.68)
                ctx.draw(wideBlur, in: CGRect(x: 0, y: 0, width: s, height: s))
                ctx.restoreGState()
            }
            // Tight luminous halo right around the filaments
            if let tightBlur = blurredImage(rawLight, radius: s * 0.011, size: size) {
                ctx.saveGState()
                ctx.setBlendMode(.screen)
                ctx.setAlpha(0.82)
                ctx.draw(tightBlur, in: CGRect(x: 0, y: 0, width: s, height: s))
                ctx.restoreGState()
            }
        }
    }

    // 6. Crisp Silk-Light Tapered Wavefront Cores (continuous luminous glass — zero hard polygon seams!)
    for spec in arcSpecs {
        let arcPath = makeTaperedArcPath(
            center: origin,
            radius: spec.radius,
            halfAngle: spec.halfAngle,
            maxHalfWidth: spec.halfWidth
        )
        ctx.saveGState()
        ctx.addPath(arcPath)
        ctx.clip()

        let arcSpanX = spec.radius * sin(spec.halfAngle)
        let arcGrad = CGGradient(
            colorsSpace: cs,
            colors: [
                CGColor(red: 0.64, green: 0.86, blue: 1.0, alpha: spec.alpha * 0.28),
                CGColor(red: 0.96, green: 0.99, blue: 1.0, alpha: spec.alpha),
                CGColor(red: 0.64, green: 0.86, blue: 1.0, alpha: spec.alpha * 0.28)
            ] as CFArray,
            locations: [0.0, 0.5, 1.0]
        )!
        ctx.drawLinearGradient(
            arcGrad,
            start: CGPoint(x: origin.x - arcSpanX, y: origin.y),
            end: CGPoint(x: origin.x + arcSpanX, y: origin.y),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        // Smooth top-edge optical specular sheen (soft radial highlight at apex — no hard seam!)
        let apex = CGPoint(x: origin.x, y: origin.y + spec.radius + spec.halfWidth * 0.35)
        let sheenGrad = CGGradient(
            colorsSpace: cs,
            colors: [
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: spec.alpha * 0.55),
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            sheenGrad,
            startCenter: apex,
            startRadius: 0,
            endCenter: apex,
            endRadius: spec.radius * 0.55,
            options: [.drawsBeforeStartLocation]
        )
        ctx.restoreGState()
    }

    // 7. Refractive Sea-Glass Emerald Jewel Core (single continuous caustic glass sphere — NO stacked bullseye rings!)
    let jewelR = s * 0.046
    let jewelRect = CGRect(x: origin.x - jewelR, y: origin.y - jewelR, width: jewelR * 2, height: jewelR * 2)

    ctx.saveGState()
    ctx.addEllipse(in: jewelRect)
    ctx.clip()

    let jewelGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.90, green: 1.00, blue: 0.96, alpha: 1.0),
            CGColor(red: 0.34, green: 0.96, blue: 0.72, alpha: 1.0),
            CGColor(red: 0.12, green: 0.76, blue: 0.56, alpha: 1.0),
            CGColor(red: 0.04, green: 0.42, blue: 0.36, alpha: 1.0)
        ] as CFArray,
        locations: [0.0, 0.28, 0.70, 1.0]
    )!
    ctx.drawRadialGradient(
        jewelGrad,
        startCenter: CGPoint(x: origin.x - jewelR * 0.16, y: origin.y + jewelR * 0.26),
        startRadius: 0,
        endCenter: origin,
        endRadius: jewelR * 1.12,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Subtle internal bottom bounce caustic inside the emerald lens
    let causticGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.65, green: 1.0, blue: 0.86, alpha: 0.46),
            CGColor(red: 0.65, green: 1.0, blue: 0.86, alpha: 0.0)
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(
        causticGrad,
        startCenter: CGPoint(x: origin.x + jewelR * 0.12, y: origin.y - jewelR * 0.44),
        startRadius: 0,
        endCenter: CGPoint(x: origin.x, y: origin.y - jewelR * 0.34),
        endRadius: jewelR * 0.68,
        options: [.drawsBeforeStartLocation]
    )
    ctx.restoreGState()

    // 8. Graded Top-to-Bottom Machined Sapphire-Glass Rim Highlight (bright top bevel, dark bottom)
    ctx.saveGState()
    let rimInset = s * 0.004
    let rimRect = rect.insetBy(dx: rimInset, dy: rimInset)
    let rimPath = CGPath(roundedRect: rimRect, cornerWidth: corner - rimInset, cornerHeight: corner - rimInset, transform: nil)
    ctx.addPath(rimPath)
    ctx.setLineWidth(s * 0.007)
    ctx.replacePathWithStrokedPath()
    ctx.clip()

    let rimGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.42),
            CGColor(red: 0.65, green: 0.78, blue: 0.95, alpha: 0.14),
            CGColor(red: 0.42, green: 0.56, blue: 0.76, alpha: 0.07),
            CGColor(red: 0.62, green: 0.78, blue: 0.95, alpha: 0.18)
        ] as CFArray,
        locations: [0.0, 0.28, 0.72, 1.0]
    )!
    ctx.drawLinearGradient(
        rimGrad,
        start: CGPoint(x: s * 0.5, y: rimRect.maxY),
        end: CGPoint(x: s * 0.5, y: rimRect.minY),
        options: []
    )
    ctx.restoreGState()

    ctx.restoreGState() // end squircle clip
    return ctx.makeImage()
}

func writeResizedPNG(from master: CGImage, size: Int, to url: URL) throws {
    guard let ctx = makeBitmapContext(size: size) else { return }
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let resized = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: resized)
    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: url)
    }
}

guard let master = renderMaster1024() else {
    fputs("Failed to render master icon\n", stderr)
    exit(1)
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
    try writeResizedPNG(from: master, size: px, to: outDir.appendingPathComponent(name))
}
