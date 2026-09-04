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
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onOpenImage: (LightboxItem) -> Void
    var onMailHandoff: (() -> Void)? = nil
    var onFilesHandoff: (() -> Void)? = nil
    var onOpenDocument: ((URL, String) -> Void)? = nil

    private var isUser: Bool { message.role == "user" }
    private var isStreaming: Bool {
        message.id == "streaming" || message.id.hasPrefix("streaming")
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: AppTheme.space8) {
            if isEditing {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.caption2.weight(.semibold))
                    Text("En édition")
                        .font(CNFont.caption2.weight(.semibold))
                }
                .foregroundStyle(AppTheme.accent)
            }

            if isUser {
                HStack(spacing: 0) {
                    Spacer(minLength: 56)
                    userContent
                }
            } else {
                assistantCanvas
            }

            if let attachments = message.attachments, !attachments.isEmpty {
                AttachmentStrip(
                    attachments: attachments,
                    token: token,
                    baseURL: baseURL,
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
                    systemImage: "envelope.open",
                    accessibilityId: A11yID.Assistant.handoffMail
                ) { onMailHandoff?() }
            }

            if let filesHandoff {
                HandoffBanner(
                    title: "Ouvrir dans Files",
                    subtitle: filesHandoff.reason ?? filesHandoff.query ?? "Handoff fichiers",
                    systemImage: "folder",
                    accessibilityId: A11yID.Assistant.handoffFiles
                ) { onFilesHandoff?() }
            }
        }
    }

    private var userContent: some View {
        Text(message.content)
            .font(CNFont.body)
            .foregroundStyle(AppTheme.foreground)
            .textSelection(.enabled)
            .padding(.horizontal, AppTheme.space16)
            .padding(.vertical, AppTheme.space12)
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
                    isEditing ? AppTheme.accent.opacity(0.55) : AppTheme.accent.opacity(0.18),
                    lineWidth: isEditing ? 1.5 : 1
                )
            )
            .contextMenu {
                Button("Copier", systemImage: "doc.on.doc", action: onCopy)
                Button("Modifier", systemImage: "pencil", action: onEdit)
            }
            .accessibilityHint("Appui long pour copier ou modifier")
    }

    /// Lecture éditoriale — pas de bulle chat générique.
    private var assistantCanvas: some View {
        VStack(alignment: .leading, spacing: AppTheme.space10) {
            Text(isStreaming ? "Assistant…" : "Assistant")
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .tracking(0.3)

            MarkdownMessageView(markdown: message.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, AppTheme.space14)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(AppTheme.accent.opacity(isStreaming ? 0.85 : 0.45))
                .frame(width: 2.5)
                .padding(.top, 4)
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
}

struct HandoffBanner: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var accessibilityId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.space12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CNFont.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                    Text(subtitle)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
            }
            .padding(AppTheme.space14)
            .background(AppTheme.surface.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
        .accessibilityLabel("\(title). \(subtitle)")
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
    let onOpen: (LightboxItem) -> Void
    var onOpenDocument: ((URL, String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.space12) {
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
        }
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
        return "\(kind) ┬À \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
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
                    .stroke(AppTheme.borderSubtle, lineWidth: 1)
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
