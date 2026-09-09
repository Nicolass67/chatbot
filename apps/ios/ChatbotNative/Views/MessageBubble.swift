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
    /// Panel agent live : overlay au-dessus du texte streamé, sous le label Assistant.
    var liveAgentOverlay: AgentActivityState? = nil
    /// Snapshot agent terminé : dans le flux, sous le label, sans recouvrir la réponse.
    var completedAgentRun: AgentActivityState? = nil

    private var isUser: Bool { message.role == "user" }
    private var isStreaming: Bool {
        isLiveStreaming || message.id == "streaming" || message.id.hasPrefix("streaming")
    }

    private var userAttachments: [MessageAttachmentDTO] {
        message.attachments ?? []
    }

    private var visibleUserText: String? {
        ChatAttachmentPresentation.visibleUserText(
            message.content,
            hasAttachments: !userAttachments.isEmpty
        )
    }

    private var userBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: AppTheme.radiusXl,
            bottomLeadingRadius: AppTheme.radiusXl,
            bottomTrailingRadius: AppTheme.radiusSm,
            topTrailingRadius: AppTheme.radiusXl,
            style: .continuous
        )
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
                if visibleUserText != nil || !userAttachments.isEmpty {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: 48)
                        userBubble
                            .frame(maxWidth: 320, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                assistantCanvas

                if let attachments = message.attachments, !attachments.isEmpty {
                    ChatMessageAttachmentsView(
                        attachments: attachments,
                        token: token,
                        baseURL: baseURL,
                        alignment: .leading,
                        embeddedInBubble: false,
                        onOpenImage: onOpenImage,
                        onOpenDocument: onOpenDocument
                    )
                }

                if !sources.isEmpty {
                    SourceChipsView(sources: sources)
                }

                if let mailHandoff {
                    HandoffBanner(
                        title: mailHandoff.bannerTitle,
                        subtitle: mailHandoff.bannerSubtitle,
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
                    FilesFoundResultsView(
                        files: filesFound,
                        onOpen: { onOpenFoundFile?($0) },
                        onDownload: { onDownloadFoundFile?($0) },
                        onReveal: { onRevealFoundFile?($0) },
                        onSendByMail: onSendFoundFileByMail
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var userBubble: some View {
        let text = visibleUserText
        let hasAttachments = !userAttachments.isEmpty
        return VStack(alignment: .leading, spacing: AppTheme.space8) {
            if let text {
                Text(text)
                    .font(.body)
                    .foregroundStyle(AppTheme.foreground)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.top, 11)
                    .padding(.bottom, hasAttachments ? 0 : 11)
            }
            if hasAttachments {
                ChatMessageAttachmentsView(
                    attachments: userAttachments,
                    token: token,
                    baseURL: baseURL,
                    alignment: .leading,
                    embeddedInBubble: true,
                    onOpenImage: onOpenImage,
                    onOpenDocument: onOpenDocument
                )
                .padding(.horizontal, 14)
                .padding(.top, text == nil ? 12 : 0)
                .padding(.bottom, 12)
            }
        }
        .background(AppTheme.userMessage)
        .clipShape(userBubbleShape)
        .overlay(
            userBubbleShape
                .stroke(
                    isEditing ? AppTheme.accent.opacity(0.55) : Color.clear,
                    lineWidth: isEditing ? 1 : 0
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
        VStack(alignment: .leading, spacing: 8) {
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

            // Label au-dessus ; le stream garde sa place ; le panneau Agent se superpose.
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    if let completed = completedAgentRun, liveAgentOverlay == nil {
                        AgentActivityView(state: completed)
                    }
                    assistantBodyMarkdown
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .zIndex(0)

                if let live = liveAgentOverlay {
                    AgentActivityView(state: live)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .compositingGroup()
                        .zIndex(10)
                        .allowsHitTesting(true)
                }
            }
        }
        .padding(.leading, AppTheme.space12)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.70), AppTheme.secondary.opacity(0.55)],
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

    @ViewBuilder
    private var assistantBodyMarkdown: some View {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if filesFound.isEmpty || !Self.looksLikeFileNarration(trimmed) {
                MarkdownMessageView(
                    markdown: message.content,
                    isStreaming: isStreaming,
                    sources: sources
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func looksLikeFileNarration(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "j'ai trouvé", "voici le fichier", "fichier trouvé", "files found",
            "voici le document", "j’ai trouvé", "trouvé le fichier",
            "id du fichier", "nom du fichier", "file id", "filename",
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
                    .foregroundStyle(AppTheme.secondary)
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
                    .stroke(AppTheme.secondary.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Résultats fichiers : liste compacte (1 surface) au lieu de N cartes × 4 boutons.
struct FilesFoundResultsView: View {
    let files: [FilesFoundFileDTO]
    var onOpen: (FilesFoundFileDTO) -> Void
    var onDownload: (FilesFoundFileDTO) -> Void
    var onReveal: (FilesFoundFileDTO) -> Void
    var onSendByMail: ((FilesFoundFileDTO) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondary)
                Text(files.count == 1 ? "1 fichier" : "\(files.count) fichiers")
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                if index > 0 {
                    Divider()
                        .opacity(0.35)
                        .padding(.leading, 52)
                }
                FileResultRow(
                    file: file,
                    isPrimary: index == 0 && files.count > 1,
                    onOpen: { onOpen(file) },
                    onDownload: { onDownload(file) },
                    onReveal: { onReveal(file) },
                    onSendByMail: onSendByMail.map { cb in { cb(file) } }
                )
            }
        }
        .background(AppTheme.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusXl, style: .continuous))
    }
}

struct FileResultRow: View {
    let file: FilesFoundFileDTO
    var isPrimary: Bool = false
    var onOpen: () -> Void
    var onDownload: () -> Void
    var onReveal: () -> Void
    var onSendByMail: (() -> Void)? = nil

    private var typeLabel: String {
        if let ext = file.extensionHint, !ext.isEmpty { return ext.uppercased() }
        if let path = file.relativePath, let dot = path.lastIndex(of: ".") {
            return String(path[path.index(after: dot)...]).uppercased()
        }
        return "Fichier"
    }

    private var folderLabel: String? {
        guard let path = file.relativePath else { return nil }
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return path }
        return parts.dropLast().suffix(2).joined(separator: "/")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.secondary.opacity(isPrimary ? 0.22 : 0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: fileIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.filename)
                            .font(.subheadline.weight(isPrimary ? .semibold : .medium))
                            .foregroundStyle(AppTheme.foreground)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if isPrimary {
                                Text("Meilleur")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                            Text(typeLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.mutedForeground)
                            if let folderLabel {
                                Text("·")
                                    .foregroundStyle(AppTheme.mutedForeground)
                                Text(folderLabel)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Ouvrir", systemImage: "doc", action: onOpen)
                Button("Télécharger", systemImage: "square.and.arrow.down", action: onDownload)
                if let onSendByMail {
                    Button("Envoyer par mail", systemImage: "envelope", action: onSendByMail)
                }
                Button("Aller à la destination", systemImage: "folder", action: onReveal)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contextMenu {
            Button("Ouvrir", systemImage: "doc", action: onOpen)
            Button("Télécharger", systemImage: "square.and.arrow.down", action: onDownload)
            if let onSendByMail {
                Button("Envoyer par mail", systemImage: "envelope", action: onSendByMail)
            }
            Button("Aller à la destination", systemImage: "folder", action: onReveal)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(file.filename)
    }

    private var fileIcon: String {
        let ext = (file.extensionHint ?? "").lowercased()
        if ["png", "jpg", "jpeg", "heic", "webp", "gif"].contains(ext) {
            return "photo"
        }
        if ext == "pdf" { return "doc.richtext" }
        if ["json", "txt", "md"].contains(ext) { return "doc.plaintext" }
        return "doc.fill"
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
                    .foregroundStyle(AppTheme.secondary)
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
            .foregroundStyle(AppTheme.secondary)
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
                            .foregroundStyle(AppTheme.secondary)
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

