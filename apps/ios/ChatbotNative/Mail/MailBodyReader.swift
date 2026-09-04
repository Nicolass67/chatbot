import SwiftUI
import WebKit
import UIKit

/// Lecteur mail P1b — HTML contrasté, plain fallback, résumé Markdown séparé (pas de conversion mail→MD).
struct MailBodyReader: View {
    let html: String?
    let text: String?
    let snippet: String?

    @State private var measuredHeight: CGFloat = 180
    @State private var showHTML = false

    private var trimmedHtml: String {
        (html ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedText: String {
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return (snippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Plain lisible prioritaire quand le texte est assez riche (évite HTML Gmail sombre-sur-sombre).
    /// Les mails HTML-only / quasi-HTML restent en WebView.
    private var preferPlain: Bool {
        trimmedText.count >= 40
    }

    private var showingPlain: Bool {
        if preferPlain && !showHTML { return true }
        if trimmedHtml.isEmpty && !trimmedText.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            if showingPlain {
                contentModeCaption("Version texte")
                Text(trimmedText)
                    .font(CNFont.body)
                    .lineSpacing(6)
                    .foregroundStyle(AppTheme.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(A11yID.Mail.bodyPlain)

                if !trimmedHtml.isEmpty {
                    Button {
                        showHTML = true
                    } label: {
                        Text("Afficher la version HTML")
                            .font(CNFont.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(minHeight: AppTheme.touchMin, alignment: .leading)
                    }
                    .accessibilityIdentifier(A11yID.Mail.bodyShowHtml)
                }
            } else if !trimmedHtml.isEmpty {
                contentModeCaption("Version HTML")
                MailHtmlView(html: trimmedHtml, measuredHeight: $measuredHeight)
                    .frame(height: measuredHeight)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(A11yID.Mail.bodyHtml)

                if preferPlain {
                    Button {
                        showHTML = false
                    } label: {
                        Text("Version texte")
                            .font(CNFont.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(minHeight: AppTheme.touchMin, alignment: .leading)
                    }
                    .accessibilityIdentifier(A11yID.Mail.bodyShowPlain)
                }
            } else if !trimmedText.isEmpty {
                contentModeCaption("Version texte")
                Text(trimmedText)
                    .font(CNFont.body)
                    .lineSpacing(6)
                    .foregroundStyle(AppTheme.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(A11yID.Mail.bodyPlain)
            } else {
                Text("Contenu non disponible")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    private func contentModeCaption(_ title: String) -> some View {
        Text(title)
            .font(CNFont.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.mutedForeground)
            .textCase(.uppercase)
            .tracking(0.4)
    }
}

struct MailAttachmentDTO: Identifiable, Codable, Hashable {
    let id: String
    let filename: String?
    let mimeType: String?
    let sizeBytes: Int?
}

struct MailAttachmentRow: View {
    @EnvironmentObject private var session: AppSessionStore
    let messageId: String
    let attachment: MailAttachmentDTO
    @State private var busy = false
    @State private var error: String?
    @State private var shareURL: URL?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename ?? "Pièce jointe")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.foreground)
                    .lineLimit(1)
                if let size = attachment.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                }
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if let shareURL {
                ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up")
                }
            } else {
                Button("Ouvrir") {
                    Task { await download() }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(10)
        .background(AppTheme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .alert("Pièce jointe", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var iconName: String {
        let mime = (attachment.mimeType ?? "").lowercased()
        let name = (attachment.filename ?? "").lowercased()
        if mime.hasPrefix("image/") || name.hasSuffix(".png") || name.hasSuffix(".jpg") { return "photo" }
        if mime.contains("pdf") || name.hasSuffix(".pdf") { return "doc.richtext" }
        return "paperclip"
    }

    private func download() async {
        busy = true
        defer { busy = false }
        do {
            let data = try await client.downloadMailAttachment(
                messageId: messageId,
                attachmentId: attachment.id
            )
            let name = attachment.filename ?? "attachment.bin"
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mail-att", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            shareURL = url
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Résumé assistant — MarkdownMessageView uniquement (jamais le corps mail brut).
struct MailSummaryBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            Text("Résumé")
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            MarkdownMessageView(markdown: text)
                .foregroundStyle(AppTheme.foreground)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceElevated.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Mail.summary)
    }
}

struct MailDraftProposal: View {
    @Binding var draftText: String
    var draftId: String?
    var isEditing: Bool
    var busy: Bool
    var onEditToggle: () -> Void
    var onRetry: () -> Void
    var onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Réponse proposée")
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)

            if isEditing {
                TextEditor(text: $draftText)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    .foregroundStyle(AppTheme.foreground)
                    .accessibilityIdentifier(A11yID.Mail.draftEditor)
            } else {
                Text(draftText)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button(isEditing ? "OK" : "Modifier") { onEditToggle() }
                    .buttonStyle(.bordered)
                Button("Réessayer") { onRetry() }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                Spacer()
                Button("Envoyer") { onSend() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(busy || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftId == nil)
                    .accessibilityIdentifier(A11yID.Mail.send)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier(A11yID.Mail.draft)
    }
}
