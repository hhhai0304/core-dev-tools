import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift tools/make-icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(filename: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func makeIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "CoreDevToolsIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    context.imageInterpolation = .high
    let size = NSSize(width: pixels, height: pixels)
    let inset = CGFloat(pixels) * 0.045
    let bounds = NSRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    let radius = CGFloat(pixels) * 0.22
    let background = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)

    context.saveGraphicsState()
    background.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.14, green: 0.38, blue: 0.66, alpha: 1),
    ])!
    gradient.draw(in: bounds, angle: -42)

    let glow = NSBezierPath(ovalIn: NSRect(
        x: CGFloat(pixels) * 0.42,
        y: CGFloat(pixels) * 0.43,
        width: CGFloat(pixels) * 0.72,
        height: CGFloat(pixels) * 0.72
    ))
    NSColor(calibratedRed: 0.22, green: 0.83, blue: 0.95, alpha: 0.16).setFill()
    glow.fill()
    context.restoreGraphicsState()

    let text = "{ }"
    let font = NSFont.monospacedSystemFont(ofSize: CGFloat(pixels) * 0.38, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -CGFloat(pixels) * 0.025,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    let textRect = NSRect(
        x: (CGFloat(pixels) - textSize.width) / 2,
        y: (CGFloat(pixels) - textSize.height) / 2 + CGFloat(pixels) * 0.025,
        width: textSize.width,
        height: textSize.height
    )
    attributed.draw(in: textRect)

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CoreDevToolsIcon", code: 2)
    }
    return png
}

for variant in variants {
    let data = try makeIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.filename))
}

print("Rendered Core Dev Tools iconset")
