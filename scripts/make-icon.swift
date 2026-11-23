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

    // Draw 3 minimalist Whisper shelf rows + accent dots inside
    let rowW = rect.width * 0.60
    let rowH = rect.height * 0.135
    let startX = rect.midX - rowW / 2
    let dotColors: [CGColor] = [
        CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0),
        CGColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1.0),
        CGColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1.0)
    ]

    for i in 0..<3 {
        let offsetY = rect.midY + CGFloat(1 - i) * (rowH + rect.height * 0.055) - rowH / 2
        let pillRect = CGRect(x: startX, y: offsetY, width: rowW, height: rowH)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: rowH * 0.38, cornerHeight: rowH * 0.38, transform: nil)

        ctx.addPath(pillPath)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: i == 0 ? 0.16 : 0.09))
        ctx.fillPath()

        ctx.addPath(pillPath)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: i == 0 ? 0.25 : 0.12))
        ctx.setLineWidth(max(1, cgSize * 0.004))
        ctx.strokePath()

        // Whisper dot
        let dotR = rowH * 0.24
        let dotRect = CGRect(
            x: pillRect.minX + rowH * 0.38,
            y: pillRect.midY - dotR,
            width: dotR * 2,
            height: dotR * 2
        )
        ctx.setFillColor(dotColors[i])
        ctx.fillEllipse(in: dotRect)

        // Subtle label bar
        let barW = rowW * (i == 0 ? 0.48 : (i == 1 ? 0.38 : 0.44))
        let barH = rowH * 0.22
        let barRect = CGRect(
            x: dotRect.maxX + rowH * 0.30,
            y: pillRect.midY - barH / 2,
            width: barW,
            height: barH
        )
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil)
        ctx.addPath(barPath)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: i == 0 ? 0.85 : 0.55))
        ctx.fillPath()
    }

    ctx.restoreGState()

    // Crisp rim border
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(max(1, cgSize * 0.008))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
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
