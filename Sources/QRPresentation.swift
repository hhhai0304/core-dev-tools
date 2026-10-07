import AppKit
import Foundation

enum QRImageConversion {
    static func cgImage(from data: Data) -> CGImage? {
        NSBitmapImageRep(data: data)?.cgImage
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        guard let tiff = image.tiffRepresentation else {
            return nil
        }
        return cgImage(from: tiff)
    }

    static func cgImageFromPasteboard() -> CGImage? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let image = cgImage(from: data) {
            return image
        }
        guard let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
              let image = images.first else {
            return nil
        }
        return cgImage(from: image)
    }

    static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func base64PNG(from image: CGImage) -> String? {
        pngData(from: image)?.base64EncodedString()
    }

    static func cgImage(fromBase64PNG value: String) -> CGImage? {
        guard let data = Data(base64Encoded: value) else {
            return nil
        }
        return cgImage(from: data)
    }
}

enum QRImageAnnotator {
    /// Draws the source image with a numbered outline around every detected
    /// QR code, matching the numbering of the decoded-results list.
    static func annotated(source: CGImage, matches: [QRCodeMatch]) -> NSImage {
        let size = NSSize(width: source.width, height: source.height)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: source, size: size).draw(in: NSRect(origin: .zero, size: size))

        let badgeDiameter = max(18, CGFloat(min(source.width, source.height)) / 14)
        let strokeWidth = max(2, badgeDiameter / 8)

        for (index, match) in matches.enumerated() {
            guard match.corners.count == 4 else {
                continue
            }

            let path = NSBezierPath()
            path.move(to: match.corners[0])
            for corner in match.corners.dropFirst() {
                path.line(to: corner)
            }
            path.close()
            path.lineWidth = strokeWidth
            path.lineJoinStyle = .round

            NSColor.systemGreen.withAlphaComponent(0.18).setFill()
            path.fill()
            NSColor.systemGreen.setStroke()
            path.stroke()

            drawBadge(index + 1, at: match.corners[3], diameter: badgeDiameter)
        }

        return image
    }

    private static func drawBadge(_ number: Int, at topLeft: CGPoint, diameter: CGFloat) {
        let center = CGPoint(x: topLeft.x, y: topLeft.y)
        let rect = NSRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let label = NSAttributedString(
            string: "\(number)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: diameter * 0.55, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        let labelSize = label.size()
        label.draw(at: NSPoint(
            x: rect.midX - labelSize.width / 2,
            y: rect.midY - labelSize.height / 2
        ))
    }
}
