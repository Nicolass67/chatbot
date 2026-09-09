import Foundation
import PDFKit
import Vision
import UniformTypeIdentifiers
import UIKit
import zlib

/// Extraction déterministe (PDFKit / Vision OCR / texte) pour documents.
/// Les images passent par le mmproj llama.cpp quand il est installé ; sinon OCR système.
enum LocalDocumentExtractor {
    static func extract(
        url: URL,
        mimeType: String? = nil,
        maxChars: Int = 8_000
    ) -> String {
        let kind = LocalFileTypeDetector.kind(for: url, sniffing: peek(url, count: 16))
        let mime = mimeType ?? LocalFileTypeDetector.mimeType(for: url)
        switch kind {
        case .pdf:
            return extractPDF(url: url, maxChars: maxChars)
        case .image:
            return extractImageOCR(url: url, maxChars: maxChars)
        case .text:
            return extractTextFile(url: url, maxChars: maxChars)
        case .unsupported:
            if mime.contains("word") || url.pathExtension.lowercased() == "docx" {
                return extractDocx(url: url, maxChars: maxChars)
            }
            let name = url.lastPathComponent
            return "Fichier « \(name) » (\(mime)) — aucun texte extractible localement."
        }
    }

    static func extract(
        data: Data,
        filename: String,
        mimeType: String,
        maxChars: Int = 8_000
    ) -> String {
        let ext = (filename as NSString).pathExtension
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("extract-\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)")
        do {
            try data.write(to: tmp, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tmp) }
            return extract(url: tmp, mimeType: mimeType, maxChars: maxChars)
        } catch {
            return "Impossible de préparer « \(filename) » pour l’analyse locale."
        }
    }

    static func extract(fileId: String, maxChars: Int = 8_000) -> String? {
        guard fileId.hasPrefix("local:") else { return nil }
        return try? LocalFilesStore.withResolvedURL(fileId: fileId) { url in
            extract(url: url, maxChars: maxChars)
        }
    }

    // MARK: - PDF

    private static func extractPDF(url: URL, maxChars: Int) -> String {
        guard let doc = PDFDocument(url: url) else {
            return "PDF illisible : \(url.lastPathComponent)"
        }
        let pageCount = doc.pageCount
        var parts: [String] = []
        var used = 0
        var ocrPages = 0
        for i in 0..<pageCount {
            guard used < maxChars else { break }
            guard let page = doc.page(at: i) else { continue }
            var pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pageText.count < 40, ocrPages < 4, let image = rasterize(page, maxEdge: 1280) {
                pageText = recognizeText(in: image)
                ocrPages += 1
            }
            if pageText.isEmpty { continue }
            let budget = maxChars - used
            let clipped = String(pageText.prefix(budget))
            parts.append("— Page \(i + 1) —\n\(clipped)")
            used += clipped.count + 16
        }
        if parts.isEmpty {
            return "PDF « \(url.lastPathComponent) » : \(pageCount) page(s), aucun texte extractible (scan illisible)."
        }
        var out = parts.joined(separator: "\n\n")
        if out.count > maxChars { out = String(out.prefix(maxChars)) }
        return out
    }

    private static func rasterize(_ page: PDFPage, maxEdge: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale = min(maxEdge / max(bounds.width, bounds.height), 2)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return image.cgImage
    }

    // MARK: - Image OCR

    private static func extractImageOCR(url: URL, maxChars: Int) -> String {
        guard let image = LocalImagePreviewLoader.load(url: url, maxPixelSize: 1600),
              let cg = image.cgImage else {
            return "Image illisible : \(url.lastPathComponent)"
        }
        let text = recognizeText(in: cg)
        if text.isEmpty {
            return "Image « \(url.lastPathComponent) » : aucun texte détecté par l’OCR système."
        }
        return String(text.prefix(maxChars))
    }

    private static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["fr-FR", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Text / Office

    private static func extractTextFile(url: URL, maxChars: Int) -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            return String(text.prefix(maxChars))
        }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1), !text.isEmpty {
            return String(text.prefix(maxChars))
        }
        return "Fichier texte illisible : \(url.lastPathComponent)"
    }

    private static func extractDocx(url: URL, maxChars: Int) -> String {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let xml = LocalZipXML.utf8Contents(of: data, path: "word/document.xml")
        else {
            return "Document Office « \(url.lastPathComponent) » : extraction locale limitée."
        }
        let stripped = xml.replacingOccurrences(
            of: #"<w:tab[^/]*/>"#,
            with: "\t",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"</w:p>"#, with: "\n", options: .regularExpression)
        .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
        let cleaned = stripped
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "Document Office « \(url.lastPathComponent) » : aucun texte dans document.xml."
        }
        return String(cleaned.prefix(maxChars))
    }

    private static func peek(_ url: URL, count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }
}

/// Lecture minimale d’une entrée ZIP (store / deflate) — pour docx.
enum LocalZipXML {
    static func utf8Contents(of data: Data, path: String) -> String? {
        guard let raw = extract(data: data, path: path) else { return nil }
        return String(data: raw, encoding: .utf8)
    }

    static func extract(data: Data, path: String) -> Data? {
        var offset = 0
        let target = path.utf8
        while offset + 30 <= data.count {
            let sig = readUInt32(data, offset)
            if sig != 0x0403_4B50 { break }
            let method = Int(readUInt16(data, offset + 8))
            let compSize = Int(readUInt32(data, offset + 18))
            let nameLen = Int(readUInt16(data, offset + 26))
            let extraLen = Int(readUInt16(data, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd + extraLen + compSize <= data.count else { return nil }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            let name = String(data: nameData, encoding: .utf8) ?? ""
            let payloadStart = nameEnd + extraLen
            let payload = data.subdata(in: payloadStart..<(payloadStart + compSize))
            if name == path || name.hasSuffix("/" + path) {
                if method == 0 { return payload }
                if method == 8 { return inflateRaw(payload) }
                return nil
            }
            offset = payloadStart + compSize
        }
        return nil
    }

    private static func inflateRaw(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        var status = data.withUnsafeBytes { src -> Int32 in
            stream.next_in = UnsafeMutablePointer(mutating: src.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            return inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var output = Data()
        var buffer = [Bytef](repeating: 0, count: 16_384)
        repeat {
            status = buffer.withUnsafeMutableBytes { dest -> Int32 in
                stream.next_out = dest.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(buffer.count)
                return inflate(&stream, Z_NO_FLUSH)
            }
            let produced = buffer.count - Int(stream.avail_out)
            if produced > 0 {
                output.append(buffer, count: produced)
            }
        } while status == Z_OK
        return (status == Z_STREAM_END || status == Z_OK) ? output : nil
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
