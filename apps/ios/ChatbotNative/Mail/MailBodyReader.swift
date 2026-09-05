import SwiftUI
import WebKit
import UIKit

/// Lecteur mail P1b — HTML contrasté, plain fallback, résumé Markdown séparé (pas de conversion mail→MD).
struct MailBodyReader: View {
    let html: String?
    let text: String?
    let snippet: String?

    @State private var measuredHeight: CGFloat = 240
    /// nil = auto (HTML si dispo), true = forcer plain, false = forcer HTML
    @State private var forcePlain: Bool? = nil

    private var trimmedHtml: String {
        (html ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedText: String {
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return (snippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML prioritaire ; plain uniquement en fallback ou sur bascule manuelle.
    private var showingPlain: Bool {
        if let forcePlain { return forcePlain }
        if trimmedHtml.isEmpty { return !trimmedText.isEmpty }
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
                        forcePlain = false
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
                // Largeur = parent SwiftUI ; pas de GeometryReader (évite décalage / largeur 0).
                MailHtmlView(html: trimmedHtml, measuredHeight: $measuredHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: measuredHeight)
                    // Pas de .clipped() agressif : le scale JS évite le débordement ;
                    // clipped coupait encore les newsletters avant remeasure.
                    .contentShape(Rectangle())
                .accessibilityIdentifier(A11yID.Mail.bodyHtml)
                .accessibilityLabel("Version HTML")
                .accessibilityValue(htmlA11yPlain)

                if !trimmedText.isEmpty {
                    Button {
                        forcePlain = true
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

private struct MailAttachmentPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct MailAttachmentRow: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    let messageId: String
    let attachment: MailAttachmentDTO
    @State private var busy = false
    @State private var error: String?
    @State private var localURL: URL?
    @State private var previewItem: MailAttachmentPreviewItem?
    @State private var showFilesPicker = false
    @State private var savedDestination: FilesSaveDestination?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var displayName: String {
        attachment.filename ?? "Pièce jointe"
    }

    private var mimeType: String {
        attachment.mimeType ?? "application/octet-stream"
    }

    var body: some View {
        HStack(spacing: AppTheme.space10) {
            Image(systemName: iconName)
                .foregroundStyle(AppTheme.mailAccent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
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
            } else {
                HStack(spacing: 2) {
                    Button {
                        Task { await openPreview() }
                    } label: {
                        Text("Ouvrir")
                            .font(CNFont.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.mailAccent)
                            .padding(.horizontal, 8)
                            .frame(minHeight: AppTheme.touchMin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ouvrir \(displayName)")

                    Button {
                        showFilesPicker = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.mailAccent)
                            .frame(minWidth: AppTheme.touchMin, minHeight: AppTheme.touchMin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enregistrer \(displayName) dans Files")

                    Button {
                        Task { await downloadAndShare() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.mailAccent)
                            .frame(minWidth: AppTheme.touchMin, minHeight: AppTheme.touchMin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Partager \(displayName)")
                }
            }
        }
        .padding(AppTheme.space12)
        .background(AppTheme.surface.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .sheet(item: $previewItem) { item in
            NavigationStack {
                QuickLookPreview(url: item.url) {
                    previewItem = nil
                }
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { previewItem = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            previewItem = nil
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                showFilesPicker = true
                            }
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("Enregistrer dans Files")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            NativeShare.present(url: item.url, title: item.title)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Partager")
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFilesPicker) {
            FilesFolderPickerSheet(
                filename: displayName,
                mimeType: mimeType,
                loadData: {
                    let url = try await ensureLocalFile()
                    return try Data(contentsOf: url)
                },
                onFinished: { saved, destination in
                    showFilesPicker = false
                    if saved {
                        savedDestination = destination
                    }
                }
            )
            .environmentObject(session)
        }
        .alert("Pièce jointe", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .alert("Enregistré dans Files", isPresented: Binding(
            get: { savedDestination != nil },
            set: { if !$0 { savedDestination = nil } }
        )) {
            Button("OK", role: .cancel) { savedDestination = nil }
            Button("Ouvrir le dossier") {
                guard let dest = savedDestination else { return }
                let target = dest
                savedDestination = nil
                // Fermer preview / picker AVANT le switch d’onglet — sinon crash SwiftUI
                // (sheet Mail encore présentée + TabView Files).
                previewItem = nil
                showFilesPicker = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    nav.openFileFolder(
                        rootId: target.rootId,
                        folderPath: target.path,
                        title: target.path.split(separator: "/").last.map(String.init) ?? target.rootLabel
                    )
                }
            }
        } message: {
            Text(savedDestination.map { "Fichier enregistré dans\n\($0.displayPath)" } ?? "")
        }
    }

    private var iconName: String {
        let mime = (attachment.mimeType ?? "").lowercased()
        let name = (attachment.filename ?? "").lowercased()
        if mime.hasPrefix("image/") || name.hasSuffix(".png") || name.hasSuffix(".jpg")
            || name.hasSuffix(".jpeg") || name.hasSuffix(".heic") || name.hasSuffix(".webp") {
            return "photo"
        }
        if mime.contains("pdf") || name.hasSuffix(".pdf") { return "doc.richtext" }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") { return "doc.text" }
        if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") || name.hasSuffix(".csv") {
            return "tablecells"
        }
        return "paperclip"
    }

    private func openPreview() async {
        busy = true
        defer { busy = false }
        do {
            let url = try await ensureLocalFile()
            previewItem = MailAttachmentPreviewItem(url: url, title: displayName)
            AppHaptics.light()
        } catch {
            self.error = Self.userFacingError(error)
        }
    }

    private func downloadAndShare() async {
        busy = true
        defer { busy = false }
        do {
            let url = try await ensureLocalFile()
            NativeShare.present(url: url, title: displayName)
            AppHaptics.success()
        } catch {
            self.error = Self.userFacingError(error)
        }
    }

    private func ensureLocalFile() async throws -> URL {
        if let localURL, FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        let data = try await client.downloadMailAttachment(
            messageId: messageId,
            attachmentId: attachment.id
        )
        // Les IDs Gmail font souvent plusieurs centaines de caractères — invalides
        // comme nom de fichier iOS (limite ~255). On isole via un hash court.
        let folder = Self.shortStableId(attachment.id)
        let fileName = Self.safeFileName(attachment.filename)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mail-att", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        localURL = url
        return url
    }

    /// Hash déterministe court (16 hex) — stable entre lancements, sans CryptoKit.
    private static func shortStableId(_ id: String) -> String {
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }

    /// Nom affichable / partageable, sans caractères de chemin, tronqué sous la limite FS.
    private static func safeFileName(_ raw: String?) -> String {
        var name = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "attachment.bin" }
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        name = name.components(separatedBy: invalid).joined(separator: "_")
        let maxLen = 180
        guard name.count > maxLen else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        if ext.isEmpty { return String(name.prefix(maxLen)) }
        let budget = max(1, maxLen - ext.count - 1)
        return "\(String(stem.prefix(budget))).\(ext)"
    }

    private static func userFacingError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("file name")
            || raw.localizedCaseInsensitiveContains("couldn't be saved")
            || raw.localizedCaseInsensitiveContains("invalid") {
            return "Impossible d’enregistrer la pièce jointe (nom de fichier invalide)."
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Impossible d’ouvrir la pièce jointe. Réessaie."
        }
        return raw
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
