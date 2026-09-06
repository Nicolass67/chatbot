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

/// Carte brouillon mail — PJ visibles, objet/destinataires (puces façon Gmail), suggestions live.
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
    /// @deprecated — ne plus afficher de liste « de base » hors frappe.
    var candidates: [String] = []

    var onSelectCandidate: ((String) -> Void)? = nil
    var onSelectSuggestion: ((MailRecipientSuggestion) -> Void)? = nil
    var onRecipientQueryChanged: ((String) -> Void)? = nil
    var onEditToggle: () -> Void
    /// Améliorer : le parent active le composer pour un conseil (pas une réécriture auto).
    var onRetry: () -> Void
    var onSend: () -> Void
    var onAttach: (() -> Void)? = nil
    /// Croix : replie la carte (brouillon conservé, récupérable).
    var onCollapse: (() -> Void)? = nil
    var onExpand: (() -> Void)? = nil
    var isCollapsed: Bool = false
    var onCommitHeaders: (() -> Void)? = nil

    /// Fragment en cours de saisie (pas encore confirmé en puce).
    @State private var typingQuery = ""
    @FocusState private var toFieldFocused: Bool

    private var sendDisabled: Bool {
        isSent || busy || isStreaming
            || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || confirmedRecipients.isEmpty
            || draftId == nil
    }

    private var statusTint: Color {
        isSent ? AppTheme.success : AppTheme.mailAccent
    }

    private var confirmedRecipients: [String] {
        Self.parseRecipients(toText)
    }

    /// Suggestions API uniquement pendant la frappe — jamais les candidates « de base ».
    private var filteredSuggestions: [MailRecipientSuggestion] {
        let q = typingQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return [] }
        let confirmed = Set(confirmedRecipients.map { $0.lowercased() })
        return recipientSuggestions
            .filter { !confirmed.contains($0.email.lowercased()) }
            .filter { row in
                let email = row.email.lowercased()
                let name = (row.displayName ?? "").lowercased()
                return email.contains(q) || name.contains(q)
            }
            .prefix(6)
            .map { $0 }
    }

    private var collapsedSubtitle: String {
        let subject = subjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty { return subject }
        let preview = draftText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if !preview.isEmpty {
            return preview.count > 72 ? String(preview.prefix(70)) + "…" : preview
        }
        if !confirmedRecipients.isEmpty {
            return confirmedRecipients.joined(separator: ", ")
        }
        return "Appuyer pour rouvrir"
    }

    var body: some View {
        Group {
            if isCollapsed && !isSent {
                collapsedBar
            } else {
                expandedCard
            }
        }
        .accessibilityIdentifier(A11yID.Mail.draft)
    }

    private var collapsedBar: some View {
        Button {
            AppHaptics.light()
            onExpand?()
        } label: {
            HStack(spacing: AppTheme.space10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.mailAccent)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.mailAccent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Brouillon replié")
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                    Text(collapsedSubtitle)
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Rouvrir")
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mailAccent)
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.mailAccent)
            }
            .padding(.horizontal, AppTheme.space14)
            .padding(.vertical, 12)
            .background {
                let shape = RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                if reduceTransparency {
                    shape.fill(AppTheme.surfaceElevated)
                } else {
                    Color.clear
                        .glassEffect(
                            .regular.tint(AppTheme.mailAccent.opacity(0.08)),
                            in: shape
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                    .stroke(AppTheme.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rouvrir le brouillon")
        .accessibilityHint(collapsedSubtitle)
    }

    private var expandedCard: some View {
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
        .onChange(of: isEditing) { _, editing in
            if editing {
                typingQuery = ""
                toFieldFocused = true
                onRecipientQueryChanged?("")
            } else {
                commitTypingQueryIfEmail()
                typingQuery = ""
                onRecipientQueryChanged?("")
            }
        }
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
            if let onCollapse, !isSent {
                Button {
                    AppHaptics.light()
                    onCollapse()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.mutedForeground)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.surface.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(busy || isStreaming)
                .accessibilityLabel("Replier le brouillon")
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
            if !confirmedRecipients.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.top, 6)
                    FlowRecipientChips(
                        emails: confirmedRecipients,
                        removable: false,
                        onRemove: { _ in }
                    )
                }
            }
            if !subjectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Objet : \(subjectText)", systemImage: "text.alignleft")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
        }
    }

    private var editableHeaders: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("À")
                    .font(CNFont.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedForeground)

                // Zone type Gmail : puces confirmées + champ de frappe.
                VStack(alignment: .leading, spacing: 8) {
                    FlowRecipientChips(
                        emails: confirmedRecipients,
                        removable: true,
                        onRemove: { email in
                            removeRecipient(email)
                        }
                    )

                    TextField("Ajouter un destinataire", text: $typingQuery)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .font(CNFont.callout)
                        .focused($toFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            commitTypingQueryIfEmail()
                        }
                        .onChange(of: typingQuery) { _, newValue in
                            handleTypingChange(newValue)
                        }
                        .accessibilityLabel("Ajouter un destinataire")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(
                            toFieldFocused ? AppTheme.mailAccent.opacity(0.45) : AppTheme.glassBorder,
                            lineWidth: toFieldFocused ? 1.2 : 0.8
                        )
                )
            }

            if !filteredSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestions")
                        .font(CNFont.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedForeground)
                    ForEach(filteredSuggestions) { item in
                        Button {
                            addRecipient(item.email)
                            onSelectSuggestion?(item)
                            onSelectCandidate?(item.email)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.mailAccent.opacity(0.16))
                                        .frame(width: 32, height: 32)
                                    Text(avatarLetter(for: item))
                                        .font(CNFont.caption.weight(.bold))
                                        .foregroundStyle(AppTheme.mailAccent)
                                }
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
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppTheme.mailAccent)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppTheme.surfaceElevated.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ajouter \(item.displayName ?? item.email)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                    commitTypingQueryIfEmail()
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
                title: "Améliorer",
                systemImage: "sparkles",
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

    // MARK: - Recipients

    private func handleTypingChange(_ raw: String) {
        // Virgule / point-virgule → confirmer le fragment précédent.
        if raw.contains(",") || raw.contains(";") {
            let separators = CharacterSet(charactersIn: ",;")
            let parts = raw.components(separatedBy: separators)
            let head = parts.dropLast().joined()
            let tail = parts.last ?? ""
            let candidate = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeEmail(candidate) {
                addRecipient(candidate)
            }
            typingQuery = tail.trimmingCharacters(in: .whitespaces)
            onRecipientQueryChanged?(typingQuery)
            return
        }
        onRecipientQueryChanged?(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func commitTypingQueryIfEmail() {
        let q = typingQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeEmail(q) else { return }
        addRecipient(q)
    }

    private func addRecipient(_ email: String) {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var next = confirmedRecipients
        if !next.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            next.append(normalized)
            toText = next.joined(separator: ", ")
            AppHaptics.selection()
        }
        typingQuery = ""
        onRecipientQueryChanged?("")
    }

    private func removeRecipient(_ email: String) {
        let next = confirmedRecipients.filter {
            $0.caseInsensitiveCompare(email) != .orderedSame
        }
        toText = next.joined(separator: ", ")
        AppHaptics.light()
    }

    private func looksLikeEmail(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard v.count >= 5, v.contains("@") else { return false }
        let parts = v.split(separator: "@")
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else { return false }
        return true
    }

    private static func parseRecipients(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains("@") }
    }

    private func avatarLetter(for item: MailRecipientSuggestion) -> String {
        let source = (item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? item.email
        return String(source.prefix(1)).uppercased()
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

// MARK: - Flow chips (destinataires)

private struct FlowRecipientChips: View {
    let emails: [String]
    var removable: Bool
    var onRemove: (String) -> Void

    var body: some View {
        // Wrapping simple via LazyVGrid flexible — lisible et tactile.
        FlexibleChipWrap(spacing: 6) {
            ForEach(emails, id: \.self) { email in
                HStack(spacing: 4) {
                    Text(shortLabel(for: email))
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(1)
                    if removable {
                        Button {
                            onRemove(email)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.mutedForeground)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retirer \(email)")
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, removable ? 4 : 10)
                .padding(.vertical, 6)
                .background(AppTheme.mailAccent.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(AppTheme.mailAccent.opacity(0.28), lineWidth: 0.8))
                .accessibilityLabel(email)
            }
        }
    }

    private func shortLabel(for email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        return local.count > 18 ? String(local.prefix(16)) + "…" : local
    }
}

/// Wrap horizontal qui passe à la ligne (esprit Gmail, sans layout engine lourd).
private struct FlexibleChipWrap<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        // iOS 16+ : Layout That Fits via ViewThatFits is awkward for chips;
        // use a simple wrapping layout.
        ChipFlowLayout(spacing: spacing) {
            content()
        }
    }
}

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
