import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import ImageIO

enum LocalPreviewKind: Equatable, Sendable {
    case image
    case pdf
    case text
    case unsupported
}

enum LocalFileTypeDetector {
    static func kind(for url: URL, sniffing dataPrefix: Data? = nil) -> LocalPreviewKind {
        let ext = url.pathExtension.lowercased()
        if let uti = UTType(filenameExtension: ext) {
            if uti.conforms(to: .pdf) { return .pdf }
            if uti.conforms(to: .image) { return .image }
            if uti.conforms(to: .text) || uti.conforms(to: .sourceCode) || uti.conforms(to: .json) {
                return .text
            }
        }
        switch ext {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp":
            return .image
        case "txt", "md", "csv", "json", "xml", "log", "swift", "ts", "js", "html", "css", "yml", "yaml":
            return .text
        default:
            break
        }
        if let head = dataPrefix, head.count >= 5 {
            if head.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf } // %PDF
            if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .image }
            if head.count >= 3, head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return .image }
            if looksLikeUTF8Text(head) { return .text }
        }
        return .unsupported
    }

    static func mimeType(for url: URL) -> String {
        if let uti = UTType(filenameExtension: url.pathExtension),
           let mime = uti.preferredMIMEType {
            return mime
        }
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }

    private static func looksLikeUTF8Text(_ data: Data) -> Bool {
        if data.contains(0) { return false }
        return String(data: data, encoding: .utf8) != nil
    }
}

/// Viewer PDF natif (pages, zoom, scroll) — pas de dump binaire.
struct PDFKitPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

enum LocalImagePreviewLoader {
    /// Downsample unique — évite de garder le bitmap plein format en plus du viewer.
    static func load(url: URL, maxPixelSize: CGFloat = 2048) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
            return ImagePipeline.downsample(data: data, maxPixelSize: maxPixelSize)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    static func load(data: Data, maxPixelSize: CGFloat = 2048) -> UIImage? {
        ImagePipeline.downsample(data: data, maxPixelSize: maxPixelSize)
            ?? UIImage(data: data)
    }
}
