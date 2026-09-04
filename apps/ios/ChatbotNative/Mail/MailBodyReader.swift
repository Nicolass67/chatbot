import SwiftUI
import WebKit
import UIKit

/// Lecteur mail P1b — HTML contrasté, plain fallback, résumé Markdown séparé (pas de conversion mail→MD).
struct MailBodyReader: View {
    let html: String?
    let text: String?
    let snippet: String?

    @State private var measuredHeight: CGFloat = 240
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
                // GeometryReader force une largeur réelle avant loadHTMLString (évite WKWebView blank).
                GeometryReader { geo in
                    MailHtmlView(html: trimmedHtml, measuredHeight: $measuredHeight)
                        .frame(width: max(geo.size.width, 1), height: measuredHeight)
                }
                .frame(height: measuredHeight)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(A11yID.Mail.bodyHtml)
                .accessibilityLabel("Version HTML")
                .accessibilityValue(htmlA11yPlain)

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

    /// Texte dépouillé pour a11y / XCUITest (WKWebView n’expose pas toujours le DOM).
    private var htmlA11yPlain: String {
        var s = trimmedHtml
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
        HStack(spacing: AppTheme.space10) {
            Image(systemName: iconName)
                .foregroundStyle(AppTheme.mailAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename ?? "Pièce jointe")
                    .font(CNFont.callout.weight(.medium))
                    .foregroundStyle(AppTheme.foreground)
                    .lineLimit(1)
                if let size = attachment.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            Spacer(minLength: 0)
            if busy {
                ProgressView().controlSize(.small).tint(AppTheme.mailAccent)
            } else if let shareURL {
                ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppTheme.mailAccent)
                        .frame(minWidth: AppTheme.touchMin, minHeight: AppTheme.touchMin)
                }
            } else {
                Button("Ouvrir") {
                    Task { await download() }
                }
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(AppTheme.mailAccent)
                .frame(minHeight: AppTheme.touchMin)
            }
        }
        .padding(AppTheme.space12)
        .background(AppTheme.surface.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
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

/// Résumé assistant — compact, repliable, sans carte « AI » générique.
struct MailSummaryBlock: View {
    let text: String
    @State private var expanded = true

    private var bodyMarkdown: String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(
            pattern: #"^#{1,6}\s*Résumé\s*\r?\n+"#,
            options: [.caseInsensitive]
        ) {
            t = regex.stringByReplacingMatches(
                in: t,
                range: NSRange(t.startIndex..., in: t),
                withTemplate: ""
            )
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: AppTheme.motionQuick, dampingFraction: 0.88)) {
                    expanded.toggle()
                }
                AppHaptics.light()
            } label: {
                HStack(spacing: AppTheme.space8) {
                    Image(systemName: "text.alignleft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mailAccent)
                    Text("Essentiel")
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mailAccent)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedForeground)
                }
                .padding(.horizontal, AppTheme.space14)
                .padding(.vertical, AppTheme.space12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                MarkdownMessageView(markdown: bodyMarkdown)
                    .foregroundStyle(AppTheme.foreground)
                    .padding(.horizontal, AppTheme.space14)
                    .padding(.bottom, AppTheme.space14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.mailAccent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.mailAccent.opacity(0.22), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            HStack {
                Text("Brouillon")
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mailAccent)
                Spacer()
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.mailAccent)
                }
            }

            if isEditing {
                TextEditor(text: $draftText)
                    .frame(minHeight: 160)
                    .padding(AppTheme.space12)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                            .stroke(AppTheme.borderSubtle, lineWidth: 1)
                    )
                    .foregroundStyle(AppTheme.foreground)
                    .accessibilityLabel("Éditeur de brouillon")
                    .accessibilityIdentifier(A11yID.Mail.draftEditor)
            } else {
                Text(draftText)
                    .font(CNFont.body)
                    .foregroundStyle(AppTheme.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.space12)
                    .background(AppTheme.surface.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
            }

            HStack(spacing: AppTheme.space8) {
                Button(isEditing ? "Terminé" : "Modifier") { onEditToggle() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(A11yID.Mail.draftEdit)
                Button("Réécrire") { onRetry() }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                    .accessibilityIdentifier(A11yID.Mail.draftRetry)
                Spacer(minLength: 0)
                Button {
                    AppHaptics.medium()
                    onSend()
                } label: {
                    Label("Envoyer", systemImage: "paperplane.fill")
                        .font(CNFont.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.mailAccent)
                .disabled(busy || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftId == nil)
                .accessibilityIdentifier(A11yID.Mail.send)
            }
        }
        .padding(AppTheme.space14)
        .background(AppTheme.surfaceElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .accessibilityIdentifier(A11yID.Mail.draft)
    }
}
