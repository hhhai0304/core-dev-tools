import CoreGraphics
import CoreImage
import Foundation

enum QRCodeLevel: String, CaseIterable, Identifiable {
    case low = "L"
    case medium = "M"
    case quartile = "Q"
    case high = "H"

    var id: String { rawValue }
}

enum QRCodeGenerator {
    /// Renders `message` as a QR code composited over a white quiet-zone
    /// background, so the result stays scannable on dark surfaces.
    static func image(
        message: String,
        correctionLevel: QRCodeLevel = .medium,
        pixels: Int = 1024
    ) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        filter.setValue(correctionLevel.rawValue, forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else {
            return nil
        }

        let scale = CGFloat(pixels) / code.extent.width
        let scaled = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let quietZone = scaled.extent.insetBy(dx: -CGFloat(pixels) / 8, dy: -CGFloat(pixels) / 8)
        let background = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: quietZone)
        let composited = scaled.composited(over: background)
        return CIContext().createCGImage(composited, from: quietZone)
    }
}

struct QRCodeMatch: Codable, Equatable {
    let message: String
    /// Corner points in image pixel space with a bottom-left origin:
    /// bottom-left, bottom-right, top-right, top-left.
    let corners: [CGPoint]
}

enum QRCodeReader {
    /// Detects every QR code in `image`; a single image may contain many.
    static func decode(_ image: CGImage) -> [QRCodeMatch] {
        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            return []
        }

        return detector.features(in: CIImage(cgImage: image)).compactMap { feature in
            guard let code = feature as? CIQRCodeFeature,
                  let message = code.messageString else {
                return nil
            }
            return QRCodeMatch(
                message: message,
                corners: [code.bottomLeft, code.bottomRight, code.topRight, code.topLeft]
            )
        }
    }
}
