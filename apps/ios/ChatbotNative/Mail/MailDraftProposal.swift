import SwiftUI

struct EmailDraftAttachmentChip: Identifiable, Hashable {
    let id: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
}

struct MailRecipientSuggestion: Identifiable, Hashable {
    var id: String { email }
    let email: String
    let displayName: String?
}

/// Carte brouillon mail — PJ visibles, objet/destinataires éditables, suggestions live.
struct MailDraftProposal: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Binding var draftText: String
    @Binding var toText: String
    @Binding var subjectText: String

    var draftId: String?
    var statusLabel: String = "Brouillon"
    var isEditing: Bool
    var busy: Bool
    var isStreaming: Bool = false
    var isSent: Bool = false
    var attachments: [EmailDraftAttachmentChip] = []
    var recipientSuggestions: [MailRecipientSuggestion] = []
    var candidates: [String] = []

    var onSelectCandidate: ((String) -> Void)? = nil
    var onSelectSuggestion: ((MailRecipientSuggestion) -> Void)? = nil
    var onRecipientQueryChanged: ((String) -> Void)? = nil
    var onEditToggle: () -> Void
    var onRetry: () -> Void
    var onSend: () -> Void
    var onAttach: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil
    var onCommitHeaders: (() -> Void)? = nil

    private var sendDisabled: Bool {
        isSent || busy || isStreaming
            || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draftId == nil
    }

    private var statusTint: Color {
        isSent ? AppTheme.success : AppTheme.mailAccent
    }

    private var suggestionRows: [MailRecipientSuggestion] {
        if !recipientSuggestions.isEmpty { return recipientSuggestions }
        return candidates.map { MailRecipientSuggestion(email: $0, displayName: nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            headerRow

            if isEditing && !isSent {
                editableHeaders
            } else {
                readOnlyHeaders
            }

            if !attachments.isEmpty {
                attachmentsSection
            }

            bodySection

            if isSent {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.success)
                    Text("Message envoyé")
                        .font(CNFont.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                    Spacer(minLength: 0)
                }
            } else {
                actionRow
                sendButton
            }
        }
        .padding(AppTheme.space14)
        .background {
            let shape = RoundedRectangle(cornerRadius: AppTheme.radiusXl, style: .continuous)
            if reduceTransparency {
                shape.fill(AppTheme.surfaceElevated)
            } else {
                Color.clear
                    .glassEffect(
                        .regular.tint(
                            (isSent ? AppTheme.success : AppTheme.mailAccent).opacity(0.06)
                        ),
                        in: shape
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusXl, style: .continuous)
                .stroke(
                    isSent ? AppTheme.success.opacity(0.28) : AppTheme.glassBorder,
                    lineWidth: 1
                )
        )
        .accessibilityIdentifier(A11yID.Mail.draft)
    }

    private var headerRow: some View {
        HStack(spacing: AppTheme.space8) {
            Label(statusLabel, systemImage: isSent ? "checkmark.circle.fill" : "envelope")
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(statusTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusTint.opacity(0.14), in: Capsule())
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 0)
            if let onDiscard, !isSent {
                Button {
                    AppHaptics.warning()
                    onDiscard()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.danger)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.danger.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(busy || isStreaming)
                .accessibilityLabel("Supprimer le brouillon")
            }
            if busy || isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusTint)
            }
        }
    }

    private var readOnlyHeaders: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("À : \(toText)", systemImage: "person.fill")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
            if !subjectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Objet : \(subjectText)", systemImage: "text.alignleft")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
            if !suggestionRows.isEmpty && !isSent {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Destinataires suggérés")
                        .font(CNFont.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                    ForEach(suggestionRows.prefix(5)) { item in
                        Button {
                            applySuggestion(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                if let name = item.displayName, !name.isEmpty {
                                    Text(name).font(CNFont.caption.weight(.semibold))
                                }
                                Text(item.email).font(CNFont.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var editableHeaders: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("À")
                    .font(CNFont.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
                TextField("destinataire@email.com", text: $toText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .font(CNFont.callout)
                    .padding(10)
                    .background(AppTheme.surface.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    .onChange(of: toText) { _, newValue in
                        onRecipientQueryChanged?(recipientQuery(from: newValue))
                    }
                    .accessibilityLabel("Destinataires")
            }

            if !suggestionRows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestions")
                        .font(CNFont.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedForeground)
                    ForEach(suggestionRows.prefix(6)) { item in
                        Button {
                            applySuggestion(item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle")
                                    .foregroundStyle(AppTheme.mailAccent)
                                VStack(alignment: .leading, spacing: 1) {
                                    if let name = item.displayName, !name.isEmpty {
                                        Text(name)
                                            .font(CNFont.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.foreground)
                                    }
                                    Text(item.email)
                                        .font(CNFont.caption)
                                        .foregroundStyle(AppTheme.mutedForeground)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppTheme.mailAccent)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppTheme.surfaceElevated.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Objet")
                    .font(CNFont.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
                TextField("Objet du mail", text: $subjectText)
                    .font(CNFont.callout)
                    .padding(10)
                    .background(AppTheme.surface.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    .accessibilityLabel("Objet du mail")
            }
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pièces jointes (\(attachments.count))", systemImage: "paperclip")
                .font(CNFont.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.mutedForeground)
            ForEach(attachments) { att in
                HStack(spacing: 10) {
                    Image(systemName: attachmentIcon(att))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.mailAccent)
                        .frame(width: 28, height: 28)
                        .background(
                            AppTheme.mailAccent.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(att.filename)
                            .font(CNFont.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.foreground)
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(att.sizeBytes), countStyle: .file))
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.mutedForeground)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(AppTheme.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        if isEditing && !isSent {
            TextEditor(text: $draftText)
                .frame(minHeight: 160)
                .padding(AppTheme.space12)
                .scrollContentBackground(.hidden)
                .background(AppTheme.surface.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                        .stroke(AppTheme.glassBorder, lineWidth: 1)
                )
                .foregroundStyle(AppTheme.foreground)
                .accessibilityLabel("Éditeur de brouillon")
                .accessibilityIdentifier(A11yID.Mail.draftEditor)
        } else {
            Text(draftText.isEmpty && isStreaming ? "Rédaction en cours…" : draftText)
                .font(CNFont.body)
                .foregroundStyle(AppTheme.foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.space12)
                .background(isSent ? AppTheme.success.opacity(0.08) : AppTheme.surface.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                        .stroke(isSent ? AppTheme.success.opacity(0.35) : Color.clear, lineWidth: 1)
                )
        }
    }

    private var actionRow: some View {
        HStack(spacing: AppTheme.space8) {
            draftGlassChip(
                title: isEditing ? "OK" : "Modifier",
                systemImage: isEditing ? "checkmark" : "pencil",
                disabled: isStreaming
            ) {
                if isEditing {
                    onCommitHeaders?()
                }
                onEditToggle()
            }
            .accessibilityIdentifier(A11yID.Mail.draftEdit)

            if let onAttach {
                draftGlassChip(
                    title: "Joindre",
                    systemImage: "paperclip",
                    disabled: busy || isStreaming,
                    action: onAttach
                )
            }

            draftGlassChip(
                title: "Réécrire",
                systemImage: "arrow.triangle.2.circlepath",
                disabled: busy || isStreaming,
                action: onRetry
            )
            .accessibilityIdentifier(A11yID.Mail.draftRetry)
        }
    }

    private var sendButton: some View {
        Button {
            AppHaptics.medium()
            onSend()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Envoyer")
                    .font(CNFont.callout.weight(.semibold))
            }
            .foregroundStyle(sendDisabled ? AppTheme.muted : AppTheme.accentForeground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background {
                let shape = Capsule(style: .continuous)
                if reduceTransparency || sendDisabled {
                    shape.fill(AppTheme.mailAccent.opacity(sendDisabled ? 0.32 : 0.92))
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassEffect(
                            .regular.tint(AppTheme.mailAccent.opacity(0.65)),
                            in: shape
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(sendDisabled)
        .accessibilityIdentifier(A11yID.Mail.send)
    }

    private func applySuggestion(_ item: MailRecipientSuggestion) {
        let parts = toText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var next = parts
        if let last = parts.last, !last.contains("@") {
            next = Array(parts.dropLast())
        }
        if !next.contains(where: { $0.caseInsensitiveCompare(item.email) == .orderedSame }) {
            next.append(item.email)
        }
        toText = next.joined(separator: ", ")
        onSelectSuggestion?(item)
        onSelectCandidate?(item.email)
        onRecipientQueryChanged?("")
    }

    private func recipientQuery(from raw: String) -> String {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.last ?? ""
    }

    private func attachmentIcon(_ att: EmailDraftAttachmentChip) -> String {
        let mime = att.mimeType.lowercased()
        let name = att.filename.lowercased()
        if mime.hasPrefix("image/") || [".png", ".jpg", ".jpeg", ".heic", ".webp"].contains(where: { name.hasSuffix($0) }) {
            return "photo"
        }
        if mime.contains("pdf") || name.hasSuffix(".pdf") { return "doc.richtext" }
        return "paperclip"
    }

    private func draftGlassChip(
        title: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(CNFont.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(disabled ? AppTheme.muted : AppTheme.foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 40)
            .background {
                let shape = Capsule(style: .continuous)
                if reduceTransparency {
                    shape.fill(AppTheme.surface.opacity(0.9))
                } else {
                    Color.clear
                        .glassEffect(
                            .regular.tint(AppTheme.surface.opacity(0.28)),
                            in: shape
                        )
                }
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AppTheme.glassBorder, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}
