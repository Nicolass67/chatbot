import SwiftUI
import UIKit

struct MailInboxView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    @State private var messages: [MailMessageSummary] = []
    @State private var loading = false
    @State private var error: String?
    @State private var path = NavigationPath()
    @State private var category: String = "primary"
    @State private var unreadOnly = false
    @State private var search = ""
    @State private var oauthEmails: [String] = []
    @State private var oauthConfigured = true
    @State private var trashTarget: MailMessageSummary?
    @State private var showAssistant = false
    @State private var assistantContext: MailAssistantContext = .global
    @State private var sheetContext: MailAssistantContext = .global

    private let categories: [(id: String, label: String)] = [
        ("primary", "Principal"),
        ("promotions", "Promotions"),
        ("social", "Réseaux"),
        ("updates", "Notifs"),
        ("sent", "Envoyés"),
        ("drafts", "Brouillons"),
    ]

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private func openMailAssistant(_ context: MailAssistantContext) {
        assistantContext = context
        sheetContext = context
        showAssistant = true
    }

    private func handleMailDeepLink(_ link: MailDeepLink?) {
        guard let link else { return }
        if let threadId = link.threadId {
            if let match = messages.first(where: { $0.threadId == threadId || $0.id == threadId }) {
                path.append(match)
            }
        } else if let q = link.query?.lowercased(), !q.isEmpty {
            if let match = messages.first(where: { msg in
                let subject = (msg.subject ?? "").lowercased()
                let snippet = (msg.snippet ?? "").lowercased()
                return subject.contains(q) || snippet.contains(q)
            }) {
                path.append(match)
            }
        }
        nav.mailDeepLink = nil
    }

    private func handleQaIntent(_ intent: QaNavIntent?) {
        guard let intent else { return }
        switch intent {
        case .mail:
            nav.qaIntent = nil
        case .mailDetail:
            if let first = messages.first {
                path.append(first)
            }
            nav.qaIntent = nil
        case .mailAssistant:
            openMailAssistant(.global)
            nav.qaIntent = nil
        default:
            break
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AmbientBackground()
                mailStack
                ContextualAssistantButton {
                    openMailAssistant(.global)
                }
            }
            .navigationTitle("Mail")
            .accessibilityIdentifier(A11yID.Mail.root)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        nav.openSettings()
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Réglages")
                    .accessibilityIdentifier(A11yID.Mail.settings)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $search, prompt: "Rechercher dans Gmail…")
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: search) { _, q in
                if q.isEmpty { Task { await load() } }
            }
            .refreshable { await load() }
            .task {
                await loadOAuth()
                await load()
            }
            .onChange(of: nav.mailDeepLink) { _, link in
                handleMailDeepLink(link)
            }
            .onChange(of: nav.presentMailAssistant) { _, present in
                if present {
                    openMailAssistant(nav.mailAssistantContext)
                    nav.presentMailAssistant = false
                }
            }
            .onChange(of: nav.qaIntent) { _, intent in
                handleQaIntent(intent)
            }
            .navigationDestination(for: MailMessageSummary.self) { msg in
                MailThreadView(summary: msg)
                    .accessibilityIdentifier(A11yID.Mail.detail)
            }
            .sheet(isPresented: $showAssistant) {
                ContextualAssistantSheet(
                    scope: .mail,
                    title: sheetContext.sheetTitle,
                    contextLabel: sheetContext.label,
                    contextRef: sheetContext.ref
                )
                .environmentObject(session)
                .environment(nav)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert(
                "Mettre à la corbeille ?",
                isPresented: Binding(
                    get: { trashTarget != nil },
                    set: { if !$0 { trashTarget = nil } }
                )
            ) {
                Button("Annuler", role: .cancel) { trashTarget = nil }
                Button("Corbeille", role: .destructive) {
                    if let target = trashTarget {
                        Task { await trashMessage(target) }
                    }
                    trashTarget = nil
                }
            } message: {
                Text(trashTarget?.subject ?? "Ce message sera proposé à la suppression (confirmation serveur).")
            }
        }
    }

    private var mailStack: some View {
        VStack(spacing: 0) {
            mailChrome
            content
        }
    }

    private var mailChrome: some View {
        VStack(spacing: 10) {
            if oauthEmails.isEmpty {
                HStack(alignment: .top, spacing: AppTheme.space12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.warning)
                    VStack(alignment: .leading, spacing: AppTheme.space4) {
                        Text(oauthConfigured
                             ? "Aucun compte Gmail connecté"
                             : "OAuth Google non configuré côté serveur")
                            .font(CNFont.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.foreground)
                        Text(oauthConfigured
                             ? "Connecte Gmail pour lire et agir depuis l’app."
                             : "Configure GOOGLE_CLIENT_* sur le serveur.")
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.muted)
                        if oauthConfigured {
                            Button("Connecter Gmail") {
                                Task { await connectGmail() }
                            }
                            .font(CNFont.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.space12)
                .background(AppTheme.warning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                .padding(.horizontal, AppTheme.space16)
            }

            HStack(spacing: 10) {
                Picker("Filtre", selection: $unreadOnly) {
                    Text("Boîte").tag(false)
                    Text("Non lus").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: unreadOnly) { _, _ in Task { await load() } }

                Menu {
                    Picker("Catégorie", selection: $category) {
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.label).tag(cat.id)
                        }
                    }
                } label: {
                    Label(
                        categories.first(where: { $0.id == category })?.label ?? "Filtrer",
                        systemImage: "line.3.horizontal.decrease"
                    )
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                }
                .onChange(of: category) { _, _ in Task { await load() } }
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
        .background(AppTheme.sidebar.opacity(0.7))
    }

    @ViewBuilder
    private var content: some View {
        if loading && messages.isEmpty {
            SoftLoadingBlock(label: "Chargement des mails…")
        } else if let error, messages.isEmpty {
            SoftEmptyState(
                systemImage: "envelope.badge.shield.half.filled",
                title: "Impossible de charger",
                message: error,
                actionTitle: "Réessayer"
            ) { Task { await load() } }
        } else if messages.isEmpty {
            SoftEmptyState(
                systemImage: "tray",
                title: "Boîte vide",
                message: "Aucun message dans ce filtre."
            )
        } else {
            List {
                ForEach(messages) { msg in
                    Button {
                        path.append(msg)
                    } label: {
                        MailRow(message: msg)
                            .frame(minHeight: 72, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11yID.Mail.message)
                    .listRowBackground(AppTheme.surface.opacity(0.55))
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            trashTarget = msg
                        } label: {
                            Label("Corbeille", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if msg.isUnread == true {
                            Button {
                                Task { await markRead(msg) }
                            } label: {
                                Label("Lu", systemImage: "envelope.open")
                            }
                            .tint(AppTheme.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func loadOAuth() async {
        if let res = try? await client.oauthAccounts() {
            oauthConfigured = res.configured
            oauthEmails = res.emails
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let cat = unreadOnly ? "unread" : category
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            messages = try await client.listMailMessages(
                category: cat,
                query: q.isEmpty ? nil : q
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
            if case APIClientError.unauthorized = error {
                await session.logout()
            }
        }
    }

    private func trashMessage(_ msg: MailMessageSummary) async {
        do {
            let proposal = try await client.proposeMailTrash(messageId: msg.id)
            try await client.confirmMailTrash(
                actionId: proposal.actionId,
                confirmationToken: proposal.confirmationToken
            )
            AppHaptics.warning()
            messages.removeAll { $0.id == msg.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func markRead(_ msg: MailMessageSummary) async {
        do {
            try await client.markMailRead(id: msg.id)
            AppHaptics.light()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func connectGmail() async {
        do {
            let url = try await client.gmailAuthorizationURL()
            await MainActor.run { UIApplication.shared.open(url) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MailRow: View {
    let message: MailMessageSummary

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.space12) {
            ZStack {
                Circle()
                    .fill(AppTheme.mailAccent.opacity(0.18))
                Text(initials)
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mailAccent)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.space4) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.space8) {
                    Text(message.from?.name ?? message.from?.email ?? "Inconnu")
                        .font(CNFont.callout.weight(message.isUnread == true ? .semibold : .regular))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = message.date {
                        Text(AppDates.short(date))
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.mutedForeground)
                            .monospacedDigit()
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if message.isUnread == true {
                        Circle()
                            .fill(AppTheme.mailAccent)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(message.subject?.isEmpty == false ? message.subject! : "(sans objet)")
                        .font(CNFont.callout.weight(message.isUnread == true ? .semibold : .regular))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(message.snippet ?? "")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                    if message.hasAttachments == true {
                        Image(systemName: "paperclip")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.mutedForeground)
                            .accessibilityLabel("Pièce jointe")
                    }
                }
            }
        }
        .padding(.vertical, AppTheme.space8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let from = message.from?.name ?? message.from?.email ?? "Inconnu"
        let subject = message.subject?.isEmpty == false ? message.subject! : "sans objet"
        let unread = message.isUnread == true ? "Non lu. " : ""
        let attach = message.hasAttachments == true ? " Avec pièce jointe." : ""
        return "\(unread)\(from). \(subject).\(attach)"
    }

    private var initials: String {
        let raw = message.from?.name ?? message.from?.email ?? "?"
        let parts = raw.split(whereSeparator: { $0.isWhitespace || $0 == "@" })
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return (letters.isEmpty ? "?" : letters.joined()).uppercased()
    }
}

struct MailThreadView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss
    let summary: MailMessageSummary
    @State private var thread: MailThreadDTO?
    @State private var error: String?
    @State private var loading = true
    @State private var summaryText: String?
    @State private var replyDraft: String?
    @State private var replyDraftId: String?
    @State private var editingDraft = false
    @State private var aiBusy = false
    @State private var aiStatus: String?
    @State private var draftStreaming = false
    @State private var trashing = false
    @State private var showAssistant = false
    @State private var confirmSend = false
    @State private var sendStatus: String?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var threadId: String {
        summary.threadId ?? summary.id
    }

    private var assistantContext: MailAssistantContext {
        .thread(
            threadId: threadId,
            subject: summary.subject ?? "",
            from: summary.from?.name ?? summary.from?.email
        )
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            Group {
                if loading {
                    SoftLoadingBlock(label: "Chargement du fil…")
                } else if let error, thread == nil {
                    SoftEmptyState(
                        systemImage: "envelope.badge.shield.half.filled",
                        title: "Impossible de charger",
                        message: error,
                        actionTitle: "Réessayer",
                        action: { Task { await load() } }
                    )
                } else if let thread {
                    threadContent(thread)
                }
            }
            ContextualAssistantButton {
                showAssistant = true
            }
        }
        .navigationTitle(summary.subject ?? "Fil")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.Mail.detail)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                mailOverflowMenu
            }
        }
        .sheet(isPresented: $showAssistant) {
            ContextualAssistantSheet(
                scope: .mail,
                title: assistantContext.sheetTitle,
                contextLabel: assistantContext.label,
                contextRef: assistantContext.ref
            )
            .environmentObject(session)
            .environment(nav)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Envoyer cette réponse à \(summary.from?.email ?? "destinataire") ?",
            isPresented: $confirmSend
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Envoyer") { Task { await sendDraft() } }
        } message: {
            Text("Une confirmation serveur sera demandée. L’envoi n’est jamais automatique.")
        }
        .task { await load() }
    }

    @ViewBuilder
    private func threadContent(_ thread: MailThreadDTO) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let aiStatus {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(AppTheme.mailAccent)
                        Text(aiStatus)
                            .font(CNFont.caption.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.vertical, 4)
                }
                if let summaryText {
                    MailSummaryBlock(text: summaryText)
                }
                if replyDraft != nil || draftStreaming {
                    MailDraftProposal(
                        draftText: replyDraftBinding,
                        draftId: replyDraftId,
                        toLabel: summary.from?.email.map { "À : \($0)" } ?? "",
                        subjectLabel: summary.subject.map { "Objet : Re: \($0)" } ?? "",
                        statusLabel: draftStreaming ? "Rédaction…" : "Brouillon",
                        isEditing: editingDraft,
                        busy: aiBusy,
                        isStreaming: draftStreaming,
                        onEditToggle: { editingDraft.toggle() },
                        onRetry: { Task { await runSuggest() } },
                        onSend: { confirmSend = true }
                    )
                }
                if let sendStatus {
                    Text(sendStatus)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.success)
                }
                ForEach(thread.messages ?? []) { msg in
                    MailThreadMessageCard(message: msg)
                }
            }
            .padding(14)
            .padding(.bottom, 88)
        }
    }

    private var replyDraftBinding: Binding<String> {
        Binding(
            get: { replyDraft ?? "" },
            set: { replyDraft = $0 }
        )
    }

    private var mailOverflowMenu: some View {
        Menu {
            Button {
                Task { await runSummarize() }
            } label: {
                Label("Résumer", systemImage: "text.alignleft")
            }
            .disabled(aiBusy)
            .accessibilityIdentifier(A11yID.Mail.summaryAction)
            Button {
                Task { await runSuggest() }
            } label: {
                Label("Préparer une réponse", systemImage: "arrowshape.turn.up.left")
            }
            .disabled(aiBusy)
            .accessibilityIdentifier(A11yID.Mail.reply)
            Button {
                showAssistant = true
            } label: {
                Label("Assistant", systemImage: "sparkles")
            }
            .accessibilityIdentifier("mail.menu.assistant")
            Divider()
            Button(role: .destructive) {
                Task { await trashFromThread() }
            } label: {
                Label("Corbeille", systemImage: "trash")
            }
            .disabled(aiBusy || trashing)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Actions du mail")
        .accessibilityIdentifier(A11yID.Mail.overflow)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            thread = try await client.fetchMailThread(id: threadId)
            error = nil
            try? await client.markMailRead(id: summary.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runSummarize() async {
        aiBusy = true
        aiStatus = "Analyse du message…"
        summaryText = summaryText ?? ""
        defer {
            aiBusy = false
            aiStatus = nil
        }
        do {
            var collected = ""
            try await client.streamSummarizeMail(threadId: threadId) { token in
                Task { @MainActor in
                    collected += token
                    self.aiStatus = nil
                    self.summaryText = collected
                }
            }
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runSuggest() async {
        aiBusy = true
        aiStatus = "Préparation de la réponse…"
        draftStreaming = true
        replyDraft = replyDraft ?? ""
        editingDraft = false
        defer {
            aiBusy = false
            aiStatus = nil
            draftStreaming = false
        }
        do {
            let result = try await client.streamSuggestMailReply(threadId: threadId) { token in
                Task { @MainActor in
                    self.aiStatus = nil
                    self.replyDraft = (self.replyDraft ?? "") + token
                }
            }
            replyDraft = result.bodyText
            replyDraftId = result.draftId
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendDraft() async {
        guard let draftId = replyDraftId, var body = replyDraft else { return }
        aiBusy = true
        defer { aiBusy = false }
        do {
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            try await client.updateEmailDraft(id: draftId, bodyText: body)
            try await client.validateEmailDraft(id: draftId)
            let proposal = try await client.proposeEmailSend(draftId: draftId)
            // Workspace conversation for confirm API
            let conv = try await client.createConversation(
                scope: .mail,
                contextKey: threadId,
                contextLabel: summary.subject,
                title: "Envoi · \(summary.subject ?? "mail")"
            )
            try await client.confirmEmailSend(
                actionId: proposal.actionId,
                confirmationToken: proposal.confirmationToken,
                conversationId: conv.id
            )
            sendStatus = "Message envoyé."
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
            AppHaptics.warning()
        }
    }

    private func trashFromThread() async {
        trashing = true
        defer { trashing = false }
        do {
            let proposal = try await client.proposeMailTrash(messageId: summary.id)
            try await client.confirmMailTrash(
                actionId: proposal.actionId,
                confirmationToken: proposal.confirmationToken
            )
            AppHaptics.warning()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct MailThreadMessageCard: View {
    @EnvironmentObject private var session: AppSessionStore
    let message: MailThreadMessage

    private var initials: String {
        let raw = message.from?.name ?? message.from?.email ?? "?"
        let parts = raw.split(whereSeparator: { $0.isWhitespace || $0 == "@" })
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return (letters.isEmpty ? "?" : letters.joined()).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            HStack(alignment: .center, spacing: AppTheme.space12) {
                ZStack {
                    Circle().fill(AppTheme.mailAccent.opacity(0.18))
                    Text(initials)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mailAccent)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.from?.name ?? message.from?.email ?? "")
                        .font(CNFont.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(1)
                    if let email = message.from?.email,
                       message.from?.name?.isEmpty == false {
                        Text(email)
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let date = message.date {
                    Text(AppDates.short(date))
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                        .monospacedDigit()
                }
            }

            if let subject = message.subject, !subject.isEmpty {
                Text(subject)
                    .font(CNFont.headline)
                    .foregroundStyle(AppTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MailBodyReader(
                html: message.bodyHtml,
                text: message.bodyText,
                snippet: message.snippet
            )

            if let attachments = message.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    Text("Pièces jointes")
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    ForEach(attachments) { att in
                        MailAttachmentRow(messageId: message.id, attachment: att)
                            .environmentObject(session)
                    }
                }
            }
        }
        .padding(.vertical, AppTheme.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
