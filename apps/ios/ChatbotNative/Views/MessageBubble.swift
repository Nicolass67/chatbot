import SwiftUI
import UIKit

struct MessageBubble: View {
    let message: MessageDTO
    let token: String?
    let baseURL: URL
    let isEditing: Bool
    var sources: [SearchSourceDTO] = []
    var mailHandoff: MailHandoffDTO? = nil
    var filesHandoff: FilesHandoffDTO? = nil
    var filesFound: [FilesFoundFileDTO] = []
    var savedMemories: [SavedMemoryChipDTO] = []
    var onOpenMemory: ((SavedMemoryChipDTO) -> Void)? = nil
    var onForgetMemory: ((SavedMemoryChipDTO) -> Void)? = nil
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onOpenImage: (LightboxItem) -> Void
    var onMailHandoff: (() -> Void)? = nil
    var onFilesHandoff: (() -> Void)? = nil
    var onOpenDocument: ((URL, String) -> Void)? = nil
    var onOpenFoundFile: ((FilesFoundFileDTO) -> Void)? = nil
    var onDownloadFoundFile: ((FilesFoundFileDTO) -> Void)? = nil
    var onRevealFoundFile: ((FilesFoundFileDTO) -> Void)? = nil
    var onSendFoundFileByMail: ((FilesFoundFileDTO) -> Void)? = nil
    /// True pendant le stream serveur (id stable) — évite le reparse Markdown à chaque token.
    var isLiveStreaming: Bool = false

    private var isUser: Bool { message.role == "user" }
    private var isStreaming: Bool {
        isLiveStreaming || message.id == "streaming" || message.id.hasPrefix("streaming")
    }

    private var hasUserText: Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var userAttachments: [MessageAttachmentDTO] {
        message.attachments ?? []
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: AppTheme.space8) {
            if isEditing {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.caption2.weight(.semibold))
                    Text("En édition")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(AppTheme.accent)
            }

            if isUser {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 48)
                    VStack(alignment: .trailing, spacing: AppTheme.space8) {
                        if hasUserText {
                            userContent
                        }
                        if !userAttachments.isEmpty {
                            AttachmentStrip(
                                attachments: userAttachments,
                                token: token,
                                baseURL: baseURL,
                                alignment: .trailing,
                                onOpen: onOpenImage,
                                onOpenDocument: onOpenDocument
                            )
                        }
                    }
                    .frame(maxWidth: 320, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                assistantCanvas

                if let attachments = message.attachments, !attachments.isEmpty {
                    AttachmentStrip(
                        attachments: attachments,
                        token: token,
                        baseURL: baseURL,
                        alignment: .leading,
                        onOpen: onOpenImage,
                        onOpenDocument: onOpenDocument
                    )
                }

                if !sources.isEmpty {
                    SourceChipsView(sources: sources)
                }

                if let mailHandoff {
                    HandoffBanner(
                        title: "Ouvrir dans Mail",
                        subtitle: mailHandoff.reason ?? mailHandoff.query ?? "Handoff mail",
                        systemImage: "envelope.open"
                    ) { onMailHandoff?() }
                }

                if let filesHandoff {
                    HandoffBanner(
                        title: "Ouvrir dans Files",
                        subtitle: filesHandoff.reason ?? filesHandoff.query ?? "Handoff fichiers",
                        systemImage: "folder"
                    ) { onFilesHandoff?() }
                }

                if !filesFound.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filesFound) { file in
                            FileResultCard(
                                file: file,
                                onOpen: { onOpenFoundFile?(file) },
                                onDownload: { onDownloadFoundFile?(file) },
                                onReveal: { onRevealFoundFile?(file) },
                                onSendByMail: onSendFoundFileByMail.map { cb in { cb(file) } }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var userContent: some View {
        Text(message.content)
            .font(.body)
            .foregroundStyle(AppTheme.foreground)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(AppTheme.userMessage)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppTheme.radiusXl,
                    bottomLeadingRadius: AppTheme.radiusXl,
                    bottomTrailingRadius: AppTheme.radiusSm,
                    topTrailingRadius: AppTheme.radiusXl,
                    style: .continuous
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppTheme.radiusXl,
                    bottomLeadingRadius: AppTheme.radiusXl,
                    bottomTrailingRadius: AppTheme.radiusSm,
                    topTrailingRadius: AppTheme.radiusXl,
                    style: .continuous
                )
                .stroke(
                    isEditing ? AppTheme.accent.opacity(0.55) : AppTheme.chromeStroke,
                    lineWidth: isEditing ? 1 : 0.5
                )
            )
            .contextMenu {
                Button("Copier", systemImage: "doc.on.doc", action: onCopy)
                Button("Modifier", systemImage: "pencil", action: onEdit)
            }
            .accessibilityHint("Appui long pour copier ou modifier")
    }

    /// Canvas lecture assistant — pas de bulle web, actions uniquement via context menu.
    private var assistantCanvas: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            HStack(alignment: .center, spacing: 8) {
                Text(isStreaming ? "Assistant…" : "Assistant")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.mutedForeground)

                if let memory = savedMemories.first {
                    MemoryUpdatedChip(
                        memory: memory,
                        compact: true,
                        onOpen: { onOpenMemory?(memory) },
                        onForget: onForgetMemory.map { cb in { cb(memory) } }
                    )
                }
            }

            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if filesFound.isEmpty || !Self.looksLikeFileNarration(trimmed) {
                    // Markdown live pendant le stream (parse incrémental + cache inline).
                    MarkdownMessageView(
                        markdown: message.content,
                        isStreaming: isStreaming,
                        sources: sources
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, AppTheme.space12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.65), AppTheme.assistantBar.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .padding(.top, 18)
        }
        .contextMenu {
            Button("Copier", systemImage: "doc.on.doc", action: onCopy)
            if !isStreaming {
                Button("Régénérer", systemImage: "arrow.clockwise", action: onRegenerate)
                ShareLink(item: message.content) {
                    Label("Partager", systemImage: "square.and.arrow.up")
                }
            }
        }
        .accessibilityHint("Appui long pour copier, régénérer ou partager")
    }

    private static func looksLikeFileNarration(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "j'ai trouvé", "voici le fichier", "fichier trouvé", "files found",
            "voici le document", "j’ai trouvé", "trouvé le fichier",
        ]
        return needles.contains { lower.contains($0) } || (text.count < 120 && lower.contains("fichier"))
    }
}

struct HandoffBanner: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
            }
            .padding(12)
            .background(AppTheme.surface.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FileResultCard: View {
    let file: FilesFoundFileDTO
    var onOpen: () -> Void
    var onDownload: () -> Void
    var onReveal: () -> Void
    var onSendByMail: (() -> Void)? = nil

    private var sizeLabel: String? {
        guard let bytes = file.sizeBytes, bytes > 0 else { return nil }
        if bytes < 1024 { return "\(bytes) o" }
        if bytes < 1024 * 1024 { return String(format: "%.1f Ko", Double(bytes) / 1024) }
        return String(format: "%.1f Mo", Double(bytes) / (1024 * 1024))
    }

    private var typeLabel: String {
        if let ext = file.extensionHint, !ext.isEmpty { return ext.uppercased() }
        if let path = file.relativePath, let dot = path.lastIndex(of: ".") {
            return String(path[path.index(after: dot)...]).uppercased()
        }
        return "Fichier"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(typeLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.mutedForeground)
                        if let path = file.relativePath {
                            Text("·")
                                .foregroundStyle(AppTheme.mutedForeground)
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(1)
                        }
                        if let sizeLabel {
                            Text("· \(sizeLabel)")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.mutedForeground)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button("Ouvrir", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.small)
                Button("Télécharger", action: onDownload)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                if let onSendByMail {
                    Button("Envoyer par mail", action: onSendByMail)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Aller à la destination", action: onReveal)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.chromeStroke, lineWidth: 0.5)
        )
        .contextMenu {
            Button("Ouvrir", systemImage: "doc", action: onOpen)
            Button("Télécharger", systemImage: "square.and.arrow.down", action: onDownload)
            if let onSendByMail {
                Button("Envoyer par mail", systemImage: "envelope.badge", action: onSendByMail)
            }
            Button("Aller à la destination", systemImage: "folder", action: onReveal)
        }
    }
}

struct SourceChipsView: View {
    let sources: [SearchSourceDTO]
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
            AppHaptics.light()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption2.weight(.semibold))
                Text(sources.count == 1 ? "1 source" : "\(sources.count) sources")
                    .font(CNFont.caption.weight(.medium))
                if let first = sources.first {
                    Text("·")
                        .foregroundStyle(AppTheme.mutedForeground)
                    Text(first.domain ?? URL(string: first.url)?.host ?? "web")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
            }
            .foregroundStyle(AppTheme.accent)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voir \(sources.count) sources")
        .sheet(isPresented: $showSheet) {
            SourcesSheet(sources: sources)
                .presentationDetents([.medium, .large])
        }
    }
}

struct SourcesSheet: View {
    let sources: [SearchSourceDTO]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(sources) { src in
                Link(destination: URL(string: src.url) ?? URL(string: "https://example.com")!) {
                    VStack(alignment: .leading, spacing: AppTheme.space4) {
                        Text(src.title)
                            .font(CNFont.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.foreground)
                        if let snippet = src.snippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(3)
                        }
                        Text(src.url)
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.accent)
                            .lineLimit(1)
                    }
                    .padding(.vertical, AppTheme.space4)
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

struct AttachmentStrip: View {
    let attachments: [MessageAttachmentDTO]
    let token: String?
    let baseURL: URL
    var alignment: HorizontalAlignment = .leading
    let onOpen: (LightboxItem) -> Void
    var onOpenDocument: ((URL, String) -> Void)? = nil

    var body: some View {
        let cards = HStack(spacing: AppTheme.space12) {
            ForEach(attachments) { att in
                RemoteAttachmentCard(
                    attachment: att,
                    token: token,
                    baseURL: baseURL,
                    onOpen: onOpen,
                    onOpenDocument: onOpenDocument
                )
            }
        }

        Group {
            if attachments.count <= 2 {
                cards
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    cards
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

struct RemoteAttachmentCard: View {
    let attachment: MessageAttachmentDTO
    let token: String?
    let baseURL: URL
    let onOpen: (LightboxItem) -> Void
    var onOpenDocument: ((URL, String) -> Void)? = nil

    @State private var image: UIImage?
    @State private var loading = true
    @State private var failed = false
    @State private var openingDoc = false

    private var isImage: Bool {
        (attachment.mimeType ?? "").hasPrefix("image/") || attachment.type == "image"
    }

    private var sizeLabel: String {
        guard let bytes = attachment.sizeBytes else { return isImage ? "Image" : "Document" }
        let kind = isImage ? "Image" : "Document"
        return "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }

    var body: some View {
        Button {
            if isImage, let image {
                onOpen(LightboxItem(id: attachment.id, image: image, filename: attachment.filename))
            } else if !isImage {
                Task { await openDocument() }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .fill(AppTheme.surfaceHover.opacity(0.7))
                        .frame(height: 72)

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 72)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    } else if (loading && isImage) || openingDoc {
                        ProgressView().tint(AppTheme.accent)
                    } else {
                        Image(systemName: failed ? "exclamationmark.triangle" : (isImage ? "photo" : "doc.fill"))
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent.opacity(0.85))
                    }
                }

                Text(attachment.filename ?? "Fichier")
                    .font(CNFont.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.foreground)
                    .lineLimit(1)
                Text(sizeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(width: 124, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                    .stroke(AppTheme.chromeStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isImage && image == nil)
        .accessibilityLabel(attachment.filename ?? (isImage ? "Image" : "Document"))
        .task(id: attachment.id) {
            await load()
        }
    }

    private func load() async {
        guard isImage else {
            loading = false
            return
        }
        loading = true
        failed = false
        let client = APIClient(baseURL: baseURL, token: token)
        do {
            let img = try await client.loadAttachmentImage(id: attachment.id, maxPixelSize: 360)
            await MainActor.run {
                image = img
                loading = false
            }
        } catch {
            await MainActor.run {
                failed = true
                loading = false
            }
        }
    }

    private func openDocument() async {
        openingDoc = true
        defer { openingDoc = false }
        do {
            let url = try await AttachmentFileCache.localURL(
                attachmentId: attachment.id,
                filename: attachment.filename ?? "document",
                baseURL: baseURL,
                token: token
            )
            onOpenDocument?(url, attachment.filename ?? "document")
        } catch {
            failed = true
        }
    }
}
