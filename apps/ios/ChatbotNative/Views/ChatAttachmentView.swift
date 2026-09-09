import SwiftUI
import UIKit

/// Tailles stables des vignettes chat — pas de `.frame(maxWidth: .infinity)`.
enum ChatAttachmentMetrics {
    static let spacing: CGFloat = 4
    static let maxVisibleImages = 9
    static let documentMaxWidth: CGFloat = 220
    static let documentIconSide: CGFloat = 32

    static func thumbSide(imageCount: Int) -> CGFloat {
        switch imageCount {
        case 0: return 0
        case 1: return 112
        case 2: return 88
        case 3, 4: return 72
        default: return 58
        }
    }

    static func columns(imageCount: Int) -> Int {
        switch imageCount {
        case 0, 1: return 1
        case 2: return 2
        case 3: return 3
        case 4: return 2
        default: return 3
        }
    }

    static func cornerRadius(imageCount: Int) -> CGFloat {
        imageCount <= 1 ? AppTheme.radiusMd : AppTheme.radiusSm
    }

    /// Downsample 2× pour écran Retina, sans charger l’original.
    static func maxPixelSize(imageCount: Int) -> CGFloat {
        min(240, thumbSide(imageCount: imageCount) * 2)
    }

    static func gridWidth(imageCount: Int) -> CGFloat {
        let visible = min(max(imageCount, 0), maxVisibleImages)
        guard visible > 0 else { return 0 }
        let cols = min(columns(imageCount: imageCount), visible)
        let side = thumbSide(imageCount: imageCount)
        return CGFloat(cols) * side + CGFloat(max(0, cols - 1)) * spacing
    }
}

enum ChatAttachmentPresentation {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "bmp", "tif", "tiff",
    ]

    private static let placeholderTexts: Set<String> = [
        "📎 Pièce jointe",
        "Analyse cette pièce jointe.",
        "Décris cette image précisément. Transcris tout le texte visible.",
    ]

    static func isImage(_ attachment: MessageAttachmentDTO) -> Bool {
        if (attachment.mimeType ?? "").lowercased().hasPrefix("image/") { return true }
        if (attachment.type ?? "").lowercased() == "image" { return true }
        return imageExtensions.contains(fileExtension(attachment.filename))
    }

    static func displayFilename(_ attachment: MessageAttachmentDTO) -> String {
        let raw = (attachment.filename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (raw as NSString).lastPathComponent
        if name.isEmpty || looksLikePathOrURL(name) {
            return isImage(attachment) ? "Image" : "Document"
        }
        return name
    }

    static func typeLabel(_ attachment: MessageAttachmentDTO) -> String {
        let mime = (attachment.mimeType ?? "").lowercased()
        if mime.contains("pdf") { return "PDF" }
        if mime.hasPrefix("image/") {
            if let sub = mime.split(separator: "/").last, sub.count <= 5 {
                return String(sub).uppercased()
            }
            return "Image"
        }
        if mime.contains("word") || mime.contains("msword") { return "DOC" }
        if mime.contains("spreadsheet") || mime.contains("excel") { return "XLS" }
        if mime.contains("presentation") || mime.contains("powerpoint") { return "PPT" }
        if mime.contains("zip") || mime.contains("compressed") { return "ZIP" }
        if mime.contains("text/plain") { return "TXT" }
        if mime.contains("json") { return "JSON" }
        if mime.contains("markdown") { return "MD" }
        let ext = fileExtension(attachment.filename)
        if !ext.isEmpty { return ext.uppercased() }
        return "Fichier"
    }

    static func sizeLabel(_ attachment: MessageAttachmentDTO) -> String? {
        guard let bytes = attachment.sizeBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func subtitle(_ attachment: MessageAttachmentDTO) -> String {
        let type = typeLabel(attachment)
        if let size = sizeLabel(attachment) {
            return "\(type) · \(size)"
        }
        return type
    }

    static func systemImageName(_ attachment: MessageAttachmentDTO) -> String {
        if isImage(attachment) { return "photo" }
        let type = typeLabel(attachment)
        if type == "PDF" { return "doc.richtext" }
        if ["ZIP", "GZ", "RAR"].contains(type) { return "doc.zipper" }
        if ["TXT", "MD", "JSON"].contains(type) { return "doc.plaintext" }
        return "doc.fill"
    }

    /// Texte visible dans la bulle : jamais d’URL, de chemin, ni d’extraction locale.
    static func visibleUserText(_ content: String, hasAttachments: Bool) -> String? {
        var text = content
        if let range = text.range(of: "\n\n--- Documents joints") {
            text = String(text[..<range.lowerBound])
        }
        if let range = text.range(of: "\n\n--- Fichier ouvert ---") {
            text = String(text[..<range.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if hasAttachments, placeholderTexts.contains(text) { return nil }
        return text
    }

    static func looksLikePathOrURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains("://") { return true }
        if lower.hasPrefix("file:") { return true }
        if value.hasPrefix("/") { return true }
        if value.contains("\\") { return true }
        return false
    }

    private static func fileExtension(_ filename: String?) -> String {
        let name = ((filename ?? "") as NSString).lastPathComponent
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }
}

/// Miniatures UI uniquement — ne touche pas aux octets utilisés par l’analyse.
@MainActor
enum ChatAttachmentPreviewStore {
    private static var images: [String: UIImage] = [:]
    private static var insertionOrder: [String] = []
    private static var files: [String: URL] = [:]
    private static let cap = 48

    static func remember(from pending: UploadedAttachment) {
        if let data = pending.previewData, let img = UIImage(data: data) {
            putImage(pending.id, img)
            let key = cacheKey(id: pending.id, pixelSize: 224)
            Task { await ImagePipeline.store(img, key: key) }
        }
        if let url = pending.localFileURL {
            files[pending.id] = url
            if pending.isImage, images[pending.id] == nil,
               let img = ImagePipeline.thumbnail(url: url, maxPixelSize: 224) {
                putImage(pending.id, img)
            }
        }
    }

    static func hydrate(from message: LocalMessage) {
        guard let attachments = message.attachments else { return }
        for att in attachments {
            guard let relative = att.localRelativePath, !relative.isEmpty else { continue }
            let name = (relative as NSString).lastPathComponent
            guard !name.isEmpty, !name.contains("..") else { continue }
            let url = LocalFilesStore.documentsDirectory
                .appendingPathComponent("LocalAttachments", isDirectory: true)
                .appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            files[att.id] = url
            let mime = (att.mimeType ?? "").lowercased()
            let isImg = mime.hasPrefix("image/") || (att.type ?? "") == "image"
            if isImg, images[att.id] == nil,
               let img = ImagePipeline.thumbnail(url: url, maxPixelSize: 224) {
                putImage(att.id, img)
            }
        }
    }

    static func image(id: String) -> UIImage? { images[id] }

    static func fileURL(id: String) -> URL? {
        guard let url = files[id], FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private static func putImage(_ id: String, _ image: UIImage) {
        if images[id] == nil {
            insertionOrder.append(id)
        }
        images[id] = image
        while insertionOrder.count > cap {
            let evict = insertionOrder.removeFirst()
            images.removeValue(forKey: evict)
        }
    }

    private static func cacheKey(id: String, pixelSize: CGFloat) -> String {
        "att-\(id)-w\(Int(pixelSize))"
    }
}

/// Composant commun Chat / Agent / local / PC.
struct ChatMessageAttachmentsView: View {
    let attachments: [MessageAttachmentDTO]
    let token: String?
    let baseURL: URL
    var alignment: HorizontalAlignment = .leading
    var embeddedInBubble: Bool = false
    let onOpenImage: (LightboxItem) -> Void
    var onOpenDocument: ((URL, String) -> Void)? = nil

    private var images: [MessageAttachmentDTO] {
        attachments.filter { ChatAttachmentPresentation.isImage($0) }
    }

    private var documents: [MessageAttachmentDTO] {
        attachments.filter { !ChatAttachmentPresentation.isImage($0) }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: AppTheme.space8) {
            if !images.isEmpty {
                ChatAttachmentImageGrid(
                    images: images,
                    token: token,
                    baseURL: baseURL,
                    alignment: alignment,
                    onOpenImage: onOpenImage
                )
            }
            if !documents.isEmpty {
                VStack(alignment: alignment, spacing: ChatAttachmentMetrics.spacing) {
                    ForEach(documents) { doc in
                        ChatAttachmentDocumentChip(
                            attachment: doc,
                            token: token,
                            baseURL: baseURL,
                            embeddedInBubble: embeddedInBubble,
                            onOpenDocument: onOpenDocument
                        )
                    }
                }
            }
        }
    }
}

private struct ChatAttachmentImageGrid: View {
    let images: [MessageAttachmentDTO]
    let token: String?
    let baseURL: URL
    var alignment: HorizontalAlignment
    let onOpenImage: (LightboxItem) -> Void

    private var side: CGFloat { ChatAttachmentMetrics.thumbSide(imageCount: images.count) }
    private var radius: CGFloat { ChatAttachmentMetrics.cornerRadius(imageCount: images.count) }
    private var pixelSize: CGFloat { ChatAttachmentMetrics.maxPixelSize(imageCount: images.count) }
    private var overflowCount: Int { max(0, images.count - ChatAttachmentMetrics.maxVisibleImages) }

    private var rows: [[MessageAttachmentDTO]] {
        let visible = Array(images.prefix(ChatAttachmentMetrics.maxVisibleImages))
        let cols = ChatAttachmentMetrics.columns(imageCount: images.count)
        stride(from: 0, to: visible.count, by: cols).map { start in
            Array(visible[start..<min(start + cols, visible.count)])
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: ChatAttachmentMetrics.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: ChatAttachmentMetrics.spacing) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { colIndex, att in
                        let isLastVisible = rowIndex == rows.count - 1 && colIndex == row.count - 1
                        ChatAttachmentImageThumb(
                            attachment: att,
                            side: side,
                            cornerRadius: radius,
                            pixelSize: pixelSize,
                            overflowLabel: isLastVisible && overflowCount > 0 ? "+\(overflowCount)" : nil,
                            token: token,
                            baseURL: baseURL,
                            onOpenImage: onOpenImage
                        )
                    }
                }
            }
        }
        .frame(
            width: ChatAttachmentMetrics.gridWidth(imageCount: images.count),
            alignment: Alignment(horizontal: alignment, vertical: .center)
        )
    }
}

private struct ChatAttachmentImageThumb: View {
    let attachment: MessageAttachmentDTO
    let side: CGFloat
    let cornerRadius: CGFloat
    let pixelSize: CGFloat
    var overflowLabel: String? = nil
    let token: String?
    let baseURL: URL
    let onOpenImage: (LightboxItem) -> Void

    @State private var image: UIImage?
    @State private var loading = true
    @State private var failed = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        Button {
            guard let image else { return }
            onOpenImage(
                LightboxItem(
                    id: attachment.id,
                    image: image,
                    filename: ChatAttachmentPresentation.displayFilename(attachment)
                )
            )
        } label: {
            Color.clear
                .frame(width: side, height: side)
                .overlay {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: side, height: side)
                                .clipped()
                        } else if loading {
                            ZStack {
                                AppTheme.surfaceHover.opacity(0.55)
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppTheme.mutedForeground)
                            }
                        } else {
                            ZStack {
                                AppTheme.surfaceHover.opacity(0.55)
                                Image(systemName: failed ? "photo.badge.exclamationmark" : "photo")
                                    .font(.system(size: min(22, side * 0.28), weight: .medium))
                                    .foregroundStyle(AppTheme.mutedForeground)
                            }
                        }
                    }
                }
                .overlay {
                    if let overflowLabel {
                        ZStack {
                            Color.black.opacity(0.42)
                            Text(overflowLabel)
                                .font(.system(size: min(18, side * 0.32), weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .compositingGroup()
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .frame(width: side, height: side)
        .animation(.easeInOut(duration: AppTheme.motionQuick), value: image != nil)
        .disabled(image == nil)
        .accessibilityLabel(ChatAttachmentPresentation.displayFilename(attachment))
        .accessibilityHint(image == nil ? "" : "Afficher en grand")
        .task(id: attachment.id) {
            await load()
        }
    }

    private func load() async {
        loading = true
        failed = false
        if let stored = ChatAttachmentPreviewStore.image(id: attachment.id) {
            image = stored
            loading = false
            return
        }
        let cacheKey = "att-\(attachment.id)-w\(Int(pixelSize))"
        if let cached = await ImagePipeline.cached(cacheKey) {
            image = cached
            loading = false
            return
        }
        if attachment.id.hasPrefix("local-") {
            if let url = ChatAttachmentPreviewStore.fileURL(id: attachment.id),
               let img = ImagePipeline.thumbnail(url: url, maxPixelSize: pixelSize) {
                image = img
                loading = false
                await ImagePipeline.store(img, key: cacheKey)
                return
            }
            failed = true
            loading = false
            return
        }
        do {
            let client = APIClient(baseURL: baseURL, token: token)
            let img = try await client.loadAttachmentImage(id: attachment.id, maxPixelSize: pixelSize)
            image = img
            loading = false
        } catch {
            if let stored = ChatAttachmentPreviewStore.image(id: attachment.id) {
                image = stored
                loading = false
                return
            }
            failed = true
            loading = false
        }
    }
}

private struct ChatAttachmentDocumentChip: View {
    let attachment: MessageAttachmentDTO
    let token: String?
    let baseURL: URL
    var embeddedInBubble: Bool
    var onOpenDocument: ((URL, String) -> Void)?

    @State private var opening = false
    @State private var failed = false

    private var filename: String { ChatAttachmentPresentation.displayFilename(attachment) }

    var body: some View {
        Button {
            Task { await openDocument() }
        } label: {
            HStack(spacing: AppTheme.space8) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
                        .fill(AppTheme.secondary.opacity(embeddedInBubble ? 0.18 : 0.14))
                        .frame(
                            width: ChatAttachmentMetrics.documentIconSide,
                            height: ChatAttachmentMetrics.documentIconSide
                        )
                    if opening {
                        ProgressView().controlSize(.mini).tint(AppTheme.secondary)
                    } else {
                        Image(systemName: failed ? "exclamationmark.triangle.fill" : ChatAttachmentPresentation.systemImageName(attachment))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(failed ? AppTheme.danger : AppTheme.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(filename)
                        .font(CNFont.caption.weight(.medium))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(
                            maxWidth: ChatAttachmentMetrics.documentMaxWidth
                                - ChatAttachmentMetrics.documentIconSide
                                - 24,
                            alignment: .leading
                        )
                    Text(ChatAttachmentPresentation.subtitle(attachment))
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, AppTheme.space8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                    .fill(embeddedInBubble ? AppTheme.foreground.opacity(0.08) : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                    .stroke(embeddedInBubble ? Color.clear : AppTheme.chromeStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(opening)
        .accessibilityLabel("\(filename), \(ChatAttachmentPresentation.subtitle(attachment))")
        .accessibilityHint("Ouvrir le document")
    }

    private func openDocument() async {
        opening = true
        failed = false
        defer { opening = false }
        let name = filename
        if attachment.id.hasPrefix("local-"),
           let url = ChatAttachmentPreviewStore.fileURL(id: attachment.id) {
            onOpenDocument?(url, name)
            return
        }
        do {
            let url = try await AttachmentFileCache.localURL(
                attachmentId: attachment.id,
                filename: name,
                baseURL: baseURL,
                token: token
            )
            onOpenDocument?(url, name)
        } catch {
            failed = true
        }
    }
}
