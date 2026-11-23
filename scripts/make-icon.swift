import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift make-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let iconsetPath = CommandLine.arguments[1]
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data? {
    let cgSize = CGFloat(size)
    let rep = NSBitmapImageRep(
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
    )!
    rep.size = NSSize(width: cgSize, height: cgSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    let inset = cgSize * 0.08
    let rect = CGRect(x: inset, y: inset, width: cgSize - inset * 2, height: cgSize - inset * 2)
    let radius = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Deep obsidian-slate glass gradient background
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let colors = [
        CGColor(red: 0.12, green: 0.15, blue: 0.23, alpha: 1.0),
        CGColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1.0)
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )

    // Soft ambient top glow
    let glowColors = [
        CGColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 0.28),
        CGColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 0.0)
    ] as CFArray
    let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1])!
    ctx.drawRadialGradient(
        radial,
        startCenter: CGPoint(x: rect.midX, y: rect.maxY * 0.88),
        startRadius: 0,
        endCenter: CGPoint(x: rect.midX, y: rect.maxY * 0.88),
        endRadius: rect.width * 0.65,
        options: []
    )

    // Minimalist bookshelf: 4 upright Whisper spines + 1 slim leaning spine on a frosted glass ledge
    let small = size < 64
    let shelfTopY = rect.minY + rect.height * 0.33
    let ledgeH = rect.height * (small ? 0.06 : 0.045)
    let floorY = shelfTopY - ledgeH * 0.35 // bottoms embed slightly into the ledge

    let spineW = rect.width * (small ? 0.125 : 0.085)
    let slimW = rect.width * (small ? 0.075 : 0.055)
    let gap = rect.width * (small ? 0.028 : 0.014)
    let leanGap = rect.width * 0.045

    let heights: [CGFloat] = [0.46, 0.36, 0.43, 0.32] // natural rhythm, tallest first
    let spineColors: [(CGFloat, CGFloat, CGFloat)] = [
        (0.22, 0.74, 0.97), // Sky
        (0.65, 0.55, 0.98), // Violet
        (0.20, 0.83, 0.60), // Emerald
        (0.98, 0.76, 0.30)  // Amber
    ]

    let groupW = spineW * 4 + gap * 3 + leanGap + slimW
    let startX = rect.midX - groupW / 2

    // Slim Rose spine leaning gently (~13 degrees) against the 4th book, drawn behind it
    let standRect = CGRect(
        x: startX + (spineW + gap) * 3 + spineW + leanGap,
        y: floorY,
        width: slimW,
        height: rect.height * 0.29
    )
    let pivot = CGPoint(x: standRect.maxX, y: floorY)
    var leanXform = CGAffineTransform(translationX: pivot.x, y: pivot.y)
    leanXform = leanXform.rotated(by: 13 * .pi / 180)
    leanXform = leanXform.translatedBy(x: -pivot.x, y: -pivot.y)
    drawSpine(ctx, rect: standRect, base: (0.97, 0.46, 0.62), radius: slimW * 0.30, transform: leanXform, small: small, size: cgSize)

    for (i, hFrac) in heights.enumerated() {
        let spineRect = CGRect(x: startX + (spineW + gap) * CGFloat(i), y: floorY, width: spineW, height: rect.height * hFrac)
        drawSpine(ctx, rect: spineRect, base: spineColors[i], radius: spineW * 0.26, transform: nil, small: small, size: cgSize)
    }

    // Frosted glass shelf ledge across the lower third, luminous white/blue with a top specular highlight
    let ledgeRect = CGRect(
        x: rect.minX + rect.width * 0.07,
        y: shelfTopY,
        width: rect.width * 0.86,
        height: ledgeH
    )
    let ledgePath = CGPath(roundedRect: ledgeRect, cornerWidth: ledgeH / 2, cornerHeight: ledgeH / 2, transform: nil)

    ctx.saveGState()
    ctx.addPath(ledgePath)
    ctx.clip()
    let ledgeColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.34),
        CGColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 0.10)
    ] as CFArray
    let ledgeGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: ledgeColors, locations: [0, 1])!
    ctx.drawLinearGradient(
        ledgeGrad,
        start: CGPoint(x: ledgeRect.midX, y: ledgeRect.maxY),
        end: CGPoint(x: ledgeRect.midX, y: ledgeRect.minY),
        options: []
    )

    let specH = ledgeH * (small ? 0.30 : 0.24)
    let specRect = CGRect(
        x: ledgeRect.minX + ledgeH * 0.7,
        y: ledgeRect.maxY - ledgeH * 0.66,
        width: ledgeRect.width - ledgeH * 1.4,
        height: specH
    )
    let specPath = CGPath(roundedRect: specRect, cornerWidth: specH / 2, cornerHeight: specH / 2, transform: nil)
    ctx.addPath(specPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: small ? 0.85 : 0.65))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(ledgePath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.38))
    ctx.setLineWidth(max(1, cgSize * 0.005))
    ctx.strokePath()

    ctx.restoreGState()

    // Crisp rim border
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(max(1, cgSize * 0.008))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

/// Draws one minimalist glass book spine: vertical light-to-deep gradient fill,
/// a slim inner sheen along the left edge, and a faint white rim (large sizes only).
func drawSpine(
    _ ctx: CGContext,
    rect: CGRect,
    base: (CGFloat, CGFloat, CGFloat),
    radius: CGFloat,
    transform: CGAffineTransform?,
    small: Bool,
    size: CGFloat
) {
    func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        if let transform {
            var t = transform
            return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: &t)
        }
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    let path = roundedPath(rect, radius)

    func tint(_ c: CGFloat, _ t: CGFloat) -> CGFloat { c + (1 - c) * t }
    let colors = [
        CGColor(red: tint(base.0, 0.32), green: tint(base.1, 0.32), blue: tint(base.2, 0.32), alpha: 0.97),
        CGColor(red: base.0 * 0.86, green: base.1 * 0.86, blue: base.2 * 0.86, alpha: 0.97)
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )

    if !small {
        // Inner glass sheen
        let sheenW = rect.width * 0.18
        let sheenRect = CGRect(
            x: rect.minX + rect.width * 0.17,
            y: rect.minY + rect.height * 0.16,
            width: sheenW,
            height: rect.height * 0.68
        )
        let sheenPath = roundedPath(sheenRect, sheenW / 2)
        ctx.addPath(sheenPath)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
        ctx.fillPath()
    }
    ctx.restoreGState()

    if !small {
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.20))
        ctx.setLineWidth(max(1, size * 0.0035))
        ctx.strokePath()
    }
}

let entries: [(String, Int)] = [
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

for (name, px) in entries {
    if let data = renderIcon(size: px) {
        try data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
    }
}
