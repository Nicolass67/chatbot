import Foundation
import UIKit
import CoreGraphics

/// Marqueur média llama.cpp / libmtmd (défaut `mtmd_default_marker()`).
enum LocalVision {
    static let mediaMarker = "<__media__>"
    /// Plafond A15 / 6 Go : une image, 768 px (taille native Qwen-VL).
    static let maxImagesPerTurn = 1
    static let maxPixelDimension: CGFloat = 768
    static let imageMaxTokens: Int32 = 192
    static let imageMinTokens: Int32 = 64

    static func userContent(_ text: String, imageCount: Int) -> String {
        let n = min(max(0, imageCount), maxImagesPerTurn)
        guard n > 0 else { return text }
        let markers = Array(repeating: mediaMarker, count: n).joined(separator: "\n")
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = body.isEmpty
            ? "Décris cette image précisément. Transcris tout le texte visible."
            : body
        return "\(markers)\n\(prompt)"
    }

    struct RGBBitmap: Sendable {
        var width: Int
        var height: Int
        var rgb: Data
    }

    static func rgbBitmap(from jpegOrPng: Data, maxDimension: CGFloat = maxPixelDimension) -> RGBBitmap? {
        let image = ImagePipeline.downsample(data: jpegOrPng, maxPixelSize: maxDimension)
            ?? UIImage(data: jpegOrPng)
        guard let image, let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }

        var rgba = Data(count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let drawn = rgba.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var rgb = Data(count: width * height * 3)
        rgb.withUnsafeMutableBytes { dest in
            rgba.withUnsafeBytes { src in
                guard let d = dest.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return }
                var di = 0
                var si = 0
                let pixels = width * height
                for _ in 0..<pixels {
                    d[di] = s[si]
                    d[di + 1] = s[si + 1]
                    d[di + 2] = s[si + 2]
                    di += 3
                    si += 4
                }
            }
        }
        return RGBBitmap(width: width, height: height, rgb: rgb)
    }

    /// JPEG 64×64 unicolore pour le smoke test vision (pas de photothèque).
    static func solidColorJPEG(red: CGFloat, green: CGFloat, blue: CGFloat, size: Int = 64) -> Data? {
        let dim = max(16, size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim), format: format)
        let image = renderer.image { ctx in
            UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: dim, height: dim))
        }
        return image.jpegData(compressionQuality: 0.95)
    }

    /// Image de test avec texte lisible (vision + raisonnement).
    static func labeledJPEG(title: String, lines: [String], width: Int = 512, height: Int = 384) -> Data? {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.15, green: 0.22, blue: 0.38, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: 56))
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.white,
            ]
            (title as NSString).draw(in: CGRect(x: 16, y: 14, width: width - 32, height: 32), withAttributes: titleAttrs)
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18),
                .foregroundColor: UIColor(white: 0.12, alpha: 1),
            ]
            var y: CGFloat = 76
            for line in lines {
                (line as NSString).draw(
                    in: CGRect(x: 20, y: y, width: width - 40, height: 28),
                    withAttributes: bodyAttrs
                )
                y += 32
            }
        }
        return image.jpegData(compressionQuality: 0.92)
    }
}
