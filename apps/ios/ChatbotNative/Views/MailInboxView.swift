import SwiftUI
import UIKit

enum MailSortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case from

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Plus récents"
        case .oldest: return "Plus anciens"
        case .from: return "Expéditeur"
        }
    }
}

struct MailInboxView: View {
    @Environment(\.themeRevision) private var themeRevision
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var infra: InfrastructureStore
    @Environment(AppNavigation.self) private var nav
    @ObservedObject private var gmailOAuth = GmailOAuthSession.shared
    @ObservedObject private var executionMode = ExecutionModeStore.shared
    @State private var messages: [MailMessageSummary] = []
    @State private var loading = false
    /// Barre inline (liste déjà peuplée).
    @State private var showInlineProgress = false
    @State private var loadGeneration = 0
    @State private var loadTask: Task<Void, Never>?
    @State private var error: String?
    @State private var path = NavigationPath()
    @State private var category: String = "inbox"
    @State private var unreadOnly = false
    @State private var sort: MailSortOption = .newest
    @State private var search = ""
    @State private var oauthEmails: [String] = []
    @State private var oauthConfigured = true
    /// Évite le flash « Connecter Gmail » avant la fin du check OAuth.
    @State private var oauthCheckCompleted = false
    @State private var trashTarget: MailMessageSummary?
    @State private var showAssistant = false
    @State private var assistantContext: MailAssistantContext = .global
    @State private var sheetContext: MailAssistantContext = .global
    @State private var assistantDetent: PresentationDetent = .large
    @State private var pendingMailDeepLink: MailDeepLink?
    @State private var mailDeepLinkError: String?
    @State private var mutationError: String?
    @State private var locallyReadIds: Set<String> = []
    @State private var locallyDeletedIds: Set<String> = []

    /// Pagination Gmail (tri « plus récents »).
    @State private var nextPageToken: String?
    @State private var pageTokenStack: [String?] = [nil]
    @State private var resultSizeEstimate: Int?
    /// Fenêtre triée localement (oldest / from) — tri avant pagination.
    @State private var sortedWindow: [MailMessageSummary] = []
    @State private var localPageIndex = 0
    @State private var windowExhausted = false

    private let pageSize = 25
    /// Fenêtre max pour tris locaux — petite pour protéger le quota Gmail.
    private let sortWindowMax = 50

    private let categories: [(id: String, label: String)] = [
        ("inbox", "Boîte"),
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

    /// Gmail direct dès qu’une session OAuth locale existe ; sinon PC / offline.
    private var useDirectGmail: Bool {
        MailDataSource.prefersDirect(session: session, execution: executionMode, infra: infra)
    }

    private var rangeLabel: String {
        let count = messages.count
        guard count > 0 else { return "Aucun mail" }
        if sort == .newest {
            let start = max(1, (pageTokenStack.count - 1) * pageSize + 1)
            let end = start + count - 1
            let estimate = resultSizeEstimate ?? 0
            // Gmail `resultSizeEstimate` est approximatif et souvent trop bas :
            // ne jamais afficher « 251–275 sur ~201 ».
            if nextPageToken != nil {
                if estimate > end {
                    return "\(start)–\(end) sur ~\(estimate)"
                }
                return "\(start)–\(end)+"
            }
            if estimate > end {
                return "\(start)–\(end) sur ~\(estimate)"
            }
            return "\(start)–\(end)"
        }
        let start = localPageIndex * pageSize + 1
        let end = start + count - 1
        let total = sortedWindow.count
        if let estimate = resultSizeEstimate, estimate > total, !windowExhausted {
            return "\(start)–\(end) sur \(total)+"
        }
        return "\(start)–\(end) sur \(total)"
    }

    private var canGoPrevious: Bool {
        sort == .newest ? pageTokenStack.count > 1 : localPageIndex > 0
    }

    private var canGoNext: Bool {
        if sort == .newest { return nextPageToken != nil }
        return (localPageIndex + 1) * pageSize < sortedWindow.count
    }

    private func openMailAssistant(_ context: MailAssistantContext) {
        assistantContext = context
        sheetContext = context
        assistantDetent = .large
        showAssistant = true
    }

    private func handleMailDeepLink(_ link: MailDeepLink?) {
        guard let link else { return }
        if messages.isEmpty && loading {
            pendingMailDeepLink = link
            return
        }
        Task { await openMailReference(link) }
    }

    private func gmailGetMessage(id: String) async throws -> DirectMailMessage {
        if useDirectGmail {
            return try await DirectGmailProvider().getMessage(id: id)
        }
        return try await RemoteGmailProvider(client: client).getMessage(id: id)
    }

    private func gmailGetThread(id: String) async throws -> DirectMailThread {
        if useDirectGmail {
            return try await DirectGmailProvider().getThread(id: id)
        }
        return try await RemoteGmailProvider(client: client).getThread(id: id)
    }

    private func gmailMarkRead(messageId: String, threadId: String?) async throws {
        if useDirectGmail {
            try await DirectGmailProvider().markRead(messageId: messageId, threadId: threadId)
            return
        }
        try await RemoteGmailProvider(client: client).markRead(messageId: messageId, threadId: threadId)
    }

    private func gmailTrashMessage(messageId: String) async throws {
        if useDirectGmail {
            try await DirectGmailProvider().trashMessage(messageId: messageId)
            return
        }
        try await RemoteGmailProvider(client: client).trashMessage(messageId: messageId)
    }

    private func openMailReference(_ link: MailDeepLink) async {
        defer {
            nav.mailDeepLink = nil
            pendingMailDeepLink = nil
        }
        if let messageId = link.messageId, !messageId.isEmpty {
            if let match = messages.first(where: { $0.id == messageId || $0.threadId == messageId }) {
                path.append(match)
                return
            }
            do {
                let msg = try await gmailGetMessage(id: messageId)
                path.append(Self.mapDirectMessage(msg))
                return
            } catch {
                if let threadId = link.threadId, !threadId.isEmpty {
                    await openThreadReference(threadId, fallbackError: error)
                    return
                }
                mailDeepLinkError = friendlyMissingMailError(error)
                return
            }
        }
        if let threadId = link.threadId, !threadId.isEmpty {
            if let match = messages.first(where: { $0.threadId == threadId || $0.id == threadId }) {
                path.append(match)
                return
            }
            await openThreadReference(threadId, fallbackError: nil)
            return
        }
        if let q = link.query?.lowercased(), !q.isEmpty {
            if let match = messages.first(where: { msg in
                let subject = (msg.subject ?? "").lowercased()
                let snippet = (msg.snippet ?? "").lowercased()
                return subject.contains(q) || snippet.contains(q)
            }) {
                path.append(match)
                return
            }
            mailDeepLinkError = "Ce mail n'est plus disponible"
        }
    }

    private func openThreadReference(_ threadId: String, fallbackError: Error?) async {
        do {
            let thread = try await gmailGetThread(id: threadId)
            let last = thread.messages.last ?? DirectMailMessage(
                id: thread.id,
                threadId: thread.threadId ?? thread.id,
                subject: thread.subject,
                from: thread.from,
                snippet: thread.snippet,
                date: thread.date,
                bodyPlain: thread.bodyPlain,
                bodyHtml: nil,
                labelIds: thread.labelIds
            )
            path.append(Self.mapDirectMessage(last))
        } catch {
            mailDeepLinkError = friendlyMissingMailError(fallbackError ?? error)
        }
    }

    private func friendlyMissingMailError(_ error: Error) -> String {
        if case DirectGmailError.http(let code, _) = error, code == 404 {
            return "Ce mail n'est plus disponible"
        }
        if case APIClientError.http(let code, _) = error, code == 404 {
            return "Ce mail n'est plus disponible"
        }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("404") || desc.contains("not found") || desc.contains("n’existe") {
            return "Ce mail n'est plus disponible"
        }
        return error.localizedDescription
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

    /// Lance un chargement (latest-wins) — annule la requête précédente.
    private func scheduleLoad(resetPagination: Bool = true) {
        loadTask?.cancel()
        if resetPagination {
            pageTokenStack = [nil]
            nextPageToken = nil
            localPageIndex = 0
            sortedWindow = []
            windowExhausted = false
            resultSizeEstimate = nil
            // Keep previous messages until new data arrives (avoid empty flash / wrong wipe).
        }
        loadTask = Task { await load(pageToken: nil) }
    }

    private func restoreMailCacheIfNeeded() {
        guard messages.isEmpty, let snap = TabMemoryCache.mail else { return }
        messages = snap.messages
        category = snap.category
        unreadOnly = snap.unreadOnly
        if let s = MailSortOption(rawValue: snap.sortRaw) { sort = s }
        search = snap.search
        nextPageToken = snap.nextPageToken
        pageTokenStack = snap.pageTokenStack.isEmpty ? [nil] : snap.pageTokenStack
        resultSizeEstimate = snap.resultSizeEstimate
        sortedWindow = snap.sortedWindow
        localPageIndex = snap.localPageIndex
        windowExhausted = snap.windowExhausted
    }

    private func persistMailCache() {
        guard !messages.isEmpty || !(TabMemoryCache.mail?.messages.isEmpty ?? true) else { return }
        TabMemoryCache.mail = .init(
            messages: messages,
            category: category,
            unreadOnly: unreadOnly,
            sortRaw: sort.rawValue,
            search: search,
            nextPageToken: nextPageToken,
            pageTokenStack: pageTokenStack,
            resultSizeEstimate: resultSizeEstimate,
            sortedWindow: sortedWindow,
            localPageIndex: localPageIndex,
            windowExhausted: windowExhausted
        )
    }

    /// Overlay local après mutation Gmail — un `load()` en vol ne doit pas réafficher « non lu ».
    private func applyOptimisticMutations(_ items: [MailMessageSummary]) -> [MailMessageSummary] {
        items
            .filter { !locallyDeletedIds.contains($0.id) }
            .map { msg in
                if locallyReadIds.contains(msg.id) {
                    return msg.withUnread(false)
                }
                if let threadId = msg.threadId, locallyReadIds.contains(threadId) {
                    return msg.withUnread(false)
                }
                return msg
            }
    }

    /// Enforce unread filter client-side (API can lag / mis-estimate).
    private func applyUnreadFilter(_ items: [MailMessageSummary]) -> [MailMessageSummary] {
        guard unreadOnly else { return items }
        return items.filter { $0.isUnread == true }
    }

    /// Combine catégorie (Envoyés, etc.) + Non lus + recherche — sans écraser la catégorie.
    private func mailListQuery(searchText: String) -> String? {
        var parts: [String] = []
        if unreadOnly {
            parts.append("is:unread")
            // Catégorie inbox = label INBOX sans query : garder le scope boîte.
            if category == "inbox" {
                parts.append("in:inbox")
            }
        }
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty {
            parts.append(s)
        }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private func goPreviousPage() {
        loadTask?.cancel()
        loadTask = Task {
            if sort == .newest {
                guard pageTokenStack.count > 1 else { return }
                let previous = Array(pageTokenStack.dropLast())
                await load(pageToken: previous.last ?? nil)
                if !Task.isCancelled {
                    pageTokenStack = previous
                }
            } else {
                guard localPageIndex > 0 else { return }
                localPageIndex -= 1
                applyLocalPage()
            }
        }
    }

    private func goNextPage() {
        loadTask?.cancel()
        loadTask = Task {
            if sort == .newest {
                guard let token = nextPageToken else { return }
                await load(pageToken: token)
                if !Task.isCancelled, error == nil {
                    pageTokenStack.append(token)
                }
            } else {
                let next = localPageIndex + 1
                guard next * pageSize < sortedWindow.count else { return }
                localPageIndex = next
                applyLocalPage()
            }
        }
    }

    var body: some View {
        let _ = themeRevision
        NavigationStack(path: $path) {
            mailPrimaryChrome
                .onSubmit(of: .search) { scheduleLoad() }
                .onChange(of: search) { _, q in
                    if q.isEmpty { scheduleLoad() }
                }
                .onChange(of: unreadOnly) { _, _ in
                    AppHaptics.selection()
                    scheduleLoad()
                }
                .onChange(of: category) { _, _ in
                    AppHaptics.selection()
                    scheduleLoad()
                }
                .onChange(of: sort) { _, _ in
                    AppHaptics.selection()
                    scheduleLoad()
                }
                .refreshable { scheduleLoad() }
                .task { await bootMailInbox() }
                .onChange(of: messages) { _, _ in
                    persistMailCache()
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
                .onAppear {
                    if nav.presentMailAssistant {
                        openMailAssistant(nav.mailAssistantContext)
                        nav.presentMailAssistant = false
                    }
                }
                .onChange(of: gmailOAuth.isConnected) { _, connected in
                    handleDirectGmailConnectionChange(connected)
                }
                .onChange(of: nav.qaIntent) { _, intent in
                    handleQaIntent(intent)
                }
                .navigationDestination(for: MailMessageSummary.self) { msg in
                    MailThreadView(summary: msg) {
                        locallyReadIds.insert(msg.id)
                        if let threadId = msg.threadId {
                            locallyReadIds.insert(threadId)
                        }
                        applyLocalRead(msg.id)
                    }
                    .accessibilityIdentifier(A11yID.Mail.detail)
                }
                .sheet(isPresented: $showAssistant) {
                    ContextualAssistantSheet(
                        scope: .mail,
                        title: sheetContext.sheetTitle,
                        contextLabel: sheetContext.label,
                        contextRef: sheetContext.ref,
                        persistenceKey: sheetContext.persistenceKey
                    )
                    .environmentObject(session)
                    .environment(nav)
                    .presentationDetents([.medium, .large], selection: $assistantDetent)
                    .presentationDragIndicator(.visible)
                    .onAppear { assistantDetent = .large }
                }
                .onChange(of: showAssistant) { _, presented in
                    if presented { assistantDetent = .large }
                }
                .onChange(of: nav.assistantDismissToken) { _, _ in
                    guard !nav.presentMailAssistant else { return }
                    showAssistant = false
                }
                .alert(
                    "Supprimer ce mail ?",
                    isPresented: Binding(
                        get: { trashTarget != nil },
                        set: { if !$0 { trashTarget = nil } }
                    )
                ) {
                    Button("Annuler", role: .cancel) { trashTarget = nil }
                    Button("Supprimer", role: .destructive) {
                        if let target = trashTarget {
                            Task { await trashMessage(target) }
                        }
                        trashTarget = nil
                    }
                } message: {
                    Text(trashTarget?.subject ?? "Le message sera mis à la corbeille.")
                }
                .alert(
                    "Mail introuvable",
                    isPresented: Binding(
                        get: { mailDeepLinkError != nil },
                        set: { if !$0 { mailDeepLinkError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { mailDeepLinkError = nil }
                } message: {
                    Text(mailDeepLinkError ?? "Ce mail n'est plus disponible")
                }
        }
    }

    /// Chrome de base — séparé pour alléger le type-check SwiftUI.
    private var mailPrimaryChrome: some View {
        ZStack {
            AmbientBackground()
            mailStack
        }
        .overlay(alignment: .bottomTrailing) {
            ContextualAssistantButton {
                openMailAssistant(.global)
            }
        }
        .navigationTitle("Mail")
        .tabRootNavigationChrome()
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
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Rechercher dans Gmail…"
        )
    }

    private func bootMailInbox() async {
        restoreMailCacheIfNeeded()
        await loadOAuth()
        if let link = nav.mailDeepLink {
            handleMailDeepLink(link)
        }
        if messages.isEmpty {
            scheduleLoad()
        }
        await refreshWidgetUnreadEstimate()
    }

    private func handleDirectGmailConnectionChange(_ connected: Bool) {
        Task {
            await loadOAuth()
            if connected {
                scheduleLoad(resetPagination: true)
            }
        }
    }

    private var mailStack: some View {
        VStack(spacing: 0) {
            if !useDirectGmail, let banner = ServiceStatusBanner.backendContext(
                infra: infra,
                surface: "Mail",
                onRepair: { id in Task { await infra.repairService(id: id) } },
                onWake: { Task { await infra.wake() } }
            ) {
                banner
                    .padding(.horizontal, AppTheme.space12)
                    .padding(.top, AppTheme.space8)
                    .padding(.bottom, AppTheme.space4)
            }
            mailChrome
            MailListLoadingIndicator(isActive: showInlineProgress)
            content
        }
    }

    private var mailChrome: some View {
        VStack(spacing: 10) {
            if let mutationError, !mutationError.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.danger)
                    Text(mutationError)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.foreground)
                    Spacer(minLength: 0)
                    Button("OK") { self.mutationError = nil }
                        .font(CNFont.caption.weight(.semibold))
                }
                .padding(AppTheme.space12)
                .background(AppTheme.danger.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                .padding(.horizontal, AppTheme.space12)
            }
            if oauthCheckCompleted && oauthEmails.isEmpty {
                HStack(alignment: .top, spacing: AppTheme.space12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.muted)
                    VStack(alignment: .leading, spacing: AppTheme.space4) {
                        Text(useDirectGmail
                             ? "Aucun compte Gmail (direct) connecté"
                             : (oauthConfigured
                                ? "Aucun compte Gmail connecté"
                                : "OAuth Google non configuré côté serveur"))
                            .font(CNFont.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.foreground)
                        Text(useDirectGmail
                             ? "Connecte Gmail sur cet iPhone (indépendant du PC)."
                             : (oauthConfigured
                                ? "Connecte Gmail pour lire et agir depuis l’app."
                                : "Configure GOOGLE_CLIENT_* sur le serveur."))
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.muted)
                        if useDirectGmail || oauthConfigured {
                            Button(useDirectGmail ? "Connecter Gmail (direct)" : "Connecter Gmail") {
                                Task { await connectGmail() }
                            }
                            .font(CNFont.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.top, 4)
                            .disabled(useDirectGmail && gmailOAuth.isBusy)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.space12)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.chromeStroke, lineWidth: 0.5)
                )
                .padding(.horizontal, AppTheme.space16)
            }

            HStack(spacing: 10) {
                Picker("Filtre", selection: $unreadOnly) {
                    Text("Tous").tag(false)
                    Text("Non lus").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Tous les mails ou non lus seulement")

                Menu {
                    Section("Catégorie") {
                        ForEach(categories, id: \.id) { cat in
                            Button {
                                category = cat.id
                            } label: {
                                if category == cat.id {
                                    Label(cat.label, systemImage: "checkmark")
                                } else {
                                    Text(cat.label)
                                }
                            }
                        }
                    }
                    Section("Tri") {
                        ForEach(MailSortOption.allCases) { option in
                            Button {
                                sort = option
                            } label: {
                                if sort == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    }
                } label: {
                    Label(
                        "\(categories.first(where: { $0.id == category })?.label ?? "Filtrer") · \(sort.title)",
                        systemImage: "line.3.horizontal.decrease"
                    )
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                }
                .accessibilityLabel("Catégorie et tri")
            }
            .padding(.horizontal, 14)

            if !messages.isEmpty || (resultSizeEstimate ?? 0) > 0 || error != nil {
                mailPaginationBar
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(AppTheme.sidebar.opacity(0.7))
    }

    private var mailPaginationBar: some View {
        HStack(spacing: AppTheme.space8) {
            Button {
                goPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .disabled(!canGoPrevious || loading)
            .accessibilityLabel("Page précédente")

            Text(rangeLabel)
                .font(CNFont.caption2.weight(.medium))
                .foregroundStyle(AppTheme.muted)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(rangeLabel)

            Button {
                goNextPage()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .disabled(!canGoNext || loading)
            .accessibilityLabel("Page suivante")
        }
        .padding(.horizontal, 10)
        .foregroundStyle(AppTheme.foreground)
    }

    @ViewBuilder
    private var content: some View {
        if loading && messages.isEmpty && !showInlineProgress {
            SoftLoadingBlock(label: "Chargement des mails…")
        } else if let error, messages.isEmpty {
            SoftEmptyState(
                systemImage: "envelope.badge.shield.half.filled",
                title: "Impossible de charger",
                message: error,
                actionTitle: "Réessayer"
            ) { scheduleLoad() }
        } else if messages.isEmpty {
            SoftEmptyState(
                systemImage: "tray",
                title: "Boîte vide",
                message: "Aucun message dans ce filtre."
            )
        } else {
            List {
                ForEach(messages) { msg in
                    NavigationLink(value: msg) {
                        MailRow(message: msg)
                            .frame(minHeight: 72, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .accessibilityIdentifier(A11yID.Mail.message)
                    .listRowBackground(AppTheme.surface.opacity(0.55))
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Pas de role .destructive ici : sinon la List retire la ligne
                        // dès le tap (avant la confirmation) puis la fait réapparaître.
                        Button {
                            trashTarget = msg
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        .tint(AppTheme.danger)
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
        defer { oauthCheckCompleted = true }
        gmailOAuth.restoreFromKeychain()
        // Session Gmail directe (Settings) prime sur l’OAuth serveur PC.
        if gmailOAuth.isConnected {
            oauthConfigured = true
            if let email = gmailOAuth.email, !email.isEmpty {
                oauthEmails = [email]
            } else {
                oauthEmails = ["Gmail connecté"]
            }
            return
        }
        if useDirectGmail {
            oauthConfigured = GmailOAuthConfig.isConfigured
            oauthEmails = []
            return
        }
        if let res = try? await client.oauthAccounts() {
            oauthConfigured = res.configured
            oauthEmails = res.emails
        }
    }

    private func parseMailDate(_ iso: String?) -> Date {
        guard let iso, !iso.isEmpty else { return .distantPast }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso) ?? .distantPast
    }

    private func sortedMessages(_ items: [MailMessageSummary], by option: MailSortOption) -> [MailMessageSummary] {
        switch option {
        case .newest:
            return items.sorted { parseMailDate($0.date) > parseMailDate($1.date) }
        case .oldest:
            return items.sorted { parseMailDate($0.date) < parseMailDate($1.date) }
        case .from:
            return items.sorted {
                let a = ($0.from?.name ?? $0.from?.email ?? "").localizedCaseInsensitiveCompare(
                    $1.from?.name ?? $1.from?.email ?? ""
                )
                if a != .orderedSame { return a == .orderedAscending }
                return parseMailDate($0.date) > parseMailDate($1.date)
            }
        }
    }

    private func applyLocalPage() {
        let start = localPageIndex * pageSize
        guard start < sortedWindow.count else {
            messages = []
            return
        }
        let end = min(start + pageSize, sortedWindow.count)
        messages = applyOptimisticMutations(Array(sortedWindow[start..<end]))
    }

    private func load(pageToken: String?) async {
        loadGeneration += 1
        let gen = loadGeneration
        let activeSort = sort
        loading = true
        error = nil
        if !messages.isEmpty {
            showInlineProgress = true
        }

        defer {
            if gen == loadGeneration {
                loading = false
                showInlineProgress = false
            }
        }

        let cat = category
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let listQuery = mailListQuery(searchText: q)

        do {
            if activeSort == .newest {
                let page = try await listMailWithRetry(
                    category: cat,
                    query: listQuery,
                    pageToken: pageToken
                )
                guard gen == loadGeneration, !Task.isCancelled else { return }
                let filtered = applyOptimisticMutations(applyUnreadFilter(page.messages))
                messages = sortedMessages(filtered, by: activeSort)
                nextPageToken = page.nextPageToken
                let est = page.resultSizeEstimate ?? 0
                let pageEnd = max(1, (pageTokenStack.count - 1) * pageSize) + max(filtered.count, 1) - 1
                // Garde un plancher cohérent avec la page affichée (estimate Gmail flaky).
                if est > 0 {
                    resultSizeEstimate = max(est, pageEnd, resultSizeEstimate ?? 0)
                } else if let prev = resultSizeEstimate {
                    resultSizeEstimate = max(prev, pageEnd)
                } else {
                    resultSizeEstimate = nil
                }
                sortedWindow = []
                error = nil
                publishMailUnreadFromInbox(estimate: resultSizeEstimate, page: filtered)
            } else {
                var collected: [MailMessageSummary] = []
                var token: String? = nil
                var estimate: Int?
                var exhausted = true
                while collected.count < sortWindowMax {
                    let page = try await listMailWithRetry(
                        category: cat,
                        query: listQuery,
                        pageToken: token
                    )
                    guard gen == loadGeneration, !Task.isCancelled else { return }
                    if let est = page.resultSizeEstimate, est > 0 { estimate = est }
                    if page.messages.isEmpty { break }
                    collected.append(contentsOf: applyOptimisticMutations(applyUnreadFilter(page.messages)))
                    if let next = page.nextPageToken, !next.isEmpty {
                        token = next
                        exhausted = false
                        if collected.count >= sortWindowMax { break }
                    } else {
                        exhausted = true
                        break
                    }
                }
                guard gen == loadGeneration, !Task.isCancelled else { return }
                var seen = Set<String>()
                let unique = collected.filter { seen.insert($0.id).inserted }
                sortedWindow = sortedMessages(unique, by: activeSort)
                windowExhausted = exhausted
                resultSizeEstimate = estimate
                nextPageToken = nil
                localPageIndex = 0
                applyLocalPage()
                error = nil
                publishMailUnreadFromInbox(estimate: estimate, page: unique)
            }
            if let pending = pendingMailDeepLink ?? nav.mailDeepLink {
                await openMailReference(pending)
            }
        } catch is CancellationError {
            return
        } catch {
            guard gen == loadGeneration, !Task.isCancelled else { return }
            // Ne jamais vider la boîte sur quota / 5xx — garde ce qui était affiché.
            if messages.isEmpty && !isTransientMailError(error) {
                messages = []
            }
            self.error = friendlyMailError(error)
            if case APIClientError.unauthorized = error, !useDirectGmail, !session.localOnlyMode {
                await session.logout()
            }
        }
    }

    private func listMailWithRetry(
        category: String,
        query: String?,
        pageToken: String?
    ) async throws -> MailMessagesPage {
        if useDirectGmail {
            let provider = DirectGmailProvider()
            let combined = Self.directGmailQuery(category: category, extra: query)
            let page = try await provider.listMessages(
                query: combined,
                pageToken: pageToken,
                maxResults: pageSize
            )
            return MailMessagesPage(
                messages: page.messages.map { Self.mapDirectMessage($0) },
                nextPageToken: page.nextPageToken,
                resultSizeEstimate: page.resultSizeEstimate
            )
        }
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await client.listMailMessages(
                    maxResults: pageSize,
                    category: category,
                    query: query,
                    pageToken: pageToken
                )
            } catch {
                lastError = error
                if attempt < 2, isTransientMailError(error) {
                    // Quota Gmail : attendre plus longtemps avant retry.
                    let delayNs: UInt64 = isQuotaMailError(error)
                        ? 2_500_000_000
                        : 450_000_000
                    try? await Task.sleep(nanoseconds: delayNs)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? APIClientError.decode
    }

    private static func directGmailQuery(category: String, extra: String?) -> String? {
        var parts: [String] = []
        switch category {
        case "inbox": parts.append("in:inbox")
        case "primary": parts.append("category:primary")
        case "promotions": parts.append("category:promotions")
        case "social": parts.append("category:social")
        case "updates": parts.append("category:updates")
        case "sent": parts.append("in:sent")
        case "drafts": parts.append("in:drafts")
        default: break
        }
        if let extra, !extra.isEmpty {
            parts.append(extra)
        }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    static func mapDirectMessage(_ m: DirectMailMessage) -> MailMessageSummary {
        MailMessageSummary(
            id: m.id,
            threadId: m.threadId,
            from: parseDirectFrom(m.from),
            subject: m.subject,
            snippet: m.snippet,
            date: m.date,
            isUnread: m.labelIds.contains("UNREAD"),
            hasAttachments: nil
        )
    }

    static func parseDirectFrom(_ header: String?) -> MailAddressDTO? {
        guard let header, !header.isEmpty else { return nil }
        if let start = header.firstIndex(of: "<"),
           let end = header.firstIndex(of: ">"),
           start < end {
            let email = String(header[header.index(after: start)..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(header[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
            return MailAddressDTO(email: email, name: name.isEmpty ? nil : name)
        }
        return MailAddressDTO(email: header, name: nil)
    }

    private func isQuotaMailError(_ error: Error) -> Bool {
        if case APIClientError.http(let code, let body) = error {
            if code == 429 { return true }
            let lower = body.lowercased()
            return lower.contains("quota") || lower.contains("rate") || lower.contains("satur")
        }
        let msg = error.localizedDescription.lowercased()
        return msg.contains("quota") || msg.contains("rate") || msg.contains("satur")
    }

    private func isTransientMailError(_ error: Error) -> Bool {
        if isQuotaMailError(error) { return true }
        if case APIClientError.http(let code, _) = error {
            return code == 429 || code >= 500
        }
        if let url = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
                .contains(url.code)
        }
        return false
    }

    private func friendlyMailError(_ error: Error) -> String {
        if isQuotaMailError(error) {
            return "Gmail est saturé (trop de chargements). Attends ~30 s puis réessaie."
        }
        if case APIClientError.http(let code, _) = error, code >= 500 {
            return "Le serveur mail est temporairement indisponible (HTTP \(code)). Réessaie."
        }
        return error.localizedDescription
    }

    /// Retire un mail de la liste affichée + fenêtre triée (sans recharger).
    private func removeMessageLocally(_ id: String) -> (messageIndex: Int?, windowIndex: Int?) {
        let messageIndex = messages.firstIndex(where: { $0.id == id })
        let windowIndex = sortedWindow.firstIndex(where: { $0.id == id })
        messages.removeAll { $0.id == id }
        sortedWindow.removeAll { $0.id == id }
        persistMailCache()
        return (messageIndex, windowIndex)
    }

    private func restoreMessageLocally(
        _ msg: MailMessageSummary,
        messageIndex: Int?,
        windowIndex: Int?
    ) {
        if !messages.contains(where: { $0.id == msg.id }) {
            let idx = min(messageIndex ?? 0, messages.count)
            messages.insert(msg, at: idx)
        }
        if !sortedWindow.contains(where: { $0.id == msg.id }) {
            let idx = min(windowIndex ?? 0, sortedWindow.count)
            sortedWindow.insert(msg, at: idx)
        }
        persistMailCache()
    }

    private func applyLocalRead(_ id: String) {
        let inMessages = messages.first(where: { $0.id == id })
        let inWindow = sortedWindow.first(where: { $0.id == id })
        let wasUnread = inMessages?.isUnread == true || inWindow?.isUnread == true
        // Déjà lu / déjà retiré du filtre non-lus → no-op (évite double -1 widget).
        if unreadOnly {
            guard inMessages != nil || inWindow != nil else { return }
        } else {
            guard wasUnread else { return }
        }
        if unreadOnly {
            _ = removeMessageLocally(id)
            bumpWidgetUnread(by: -1)
            return
        }
        if let i = messages.firstIndex(where: { $0.id == id }) {
            messages[i] = messages[i].withUnread(false)
        }
        if let i = sortedWindow.firstIndex(where: { $0.id == id }) {
            sortedWindow[i] = sortedWindow[i].withUnread(false)
        }
        persistMailCache()
        bumpWidgetUnread(by: -1)
    }

    /// Estimate Gmail `is:unread` + aperçus (expéditeur / sujet) pour le widget.
    private func refreshWidgetUnreadEstimate() async {
        do {
            let page = try await client.listMailMessages(
                maxResults: 5,
                category: "inbox",
                query: "is:unread",
                pageToken: nil
            )
            let count = page.resultSizeEstimate ?? page.messages.count
            WidgetSharedStore.publishMailUnread(count, previews: Self.widgetMailPreviews(from: page.messages))
        } catch {
            // Conserve la dernière valeur widget.
        }
    }

    private func publishMailUnreadFromInbox(estimate: Int?, page: [MailMessageSummary]) {
        let previews = Self.widgetMailPreviews(from: page)
        if unreadOnly {
            WidgetSharedStore.publishMailUnread(estimate ?? page.count, previews: previews)
            return
        }
        // Hors filtre non-lu : garde le compteur existant si présent, sinon seed avec l’estimé.
        if let defaults = UserDefaults(suiteName: WidgetSharedStore.appGroupId),
           defaults.object(forKey: WidgetSharedStore.Key.mailUnread) != nil {
            let current = defaults.integer(forKey: WidgetSharedStore.Key.mailUnread)
            WidgetSharedStore.publishMailUnread(current, previews: previews)
        } else if let estimate {
            WidgetSharedStore.publishMailUnread(estimate, previews: previews)
        } else {
            let unreadCount = page.filter { $0.isUnread == true }.count
            WidgetSharedStore.publishMailUnread(unreadCount, previews: previews.filter(\.unread))
        }
    }

    private func bumpWidgetUnread(by delta: Int) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedStore.appGroupId) else { return }
        let key = WidgetSharedStore.Key.mailUnread
        let current = defaults.object(forKey: key) == nil ? 0 : defaults.integer(forKey: key)
        WidgetSharedStore.publishMailUnread(max(0, current + delta))
    }

    private static func widgetMailPreviews(from messages: [MailMessageSummary]) -> [WidgetSharedStore.MailPreviewItem] {
        messages.prefix(5).map { msg in
            let from = msg.from?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = msg.from?.email ?? ""
            let fromLabel = (from?.isEmpty == false ? from! : email).isEmpty ? "Inconnu" : (from?.isEmpty == false ? from! : email)
            let subject = (msg.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = (msg.snippet ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return WidgetSharedStore.MailPreviewItem(
                id: msg.id,
                from: fromLabel,
                subject: subject.isEmpty ? "(Sans objet)" : subject,
                snippet: String(snippet.prefix(120)),
                dateLabel: widgetMailDateLabel(msg.date),
                unread: msg.isUnread == true
            )
        }
    }

    private static func widgetMailDateLabel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return String(raw.prefix(10)) }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "fr_FR")
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }

    private func trashMessage(_ msg: MailMessageSummary) async {
        mutationError = nil
        locallyDeletedIds.insert(msg.id)
        let snapshot = msg
        let indices = removeMessageLocally(msg.id)
        do {
            try await gmailTrashMessage(messageId: msg.id)
            if snapshot.isUnread == true { bumpWidgetUnread(by: -1) }
            AppHaptics.warning()
        } catch {
            locallyDeletedIds.remove(msg.id)
            restoreMessageLocally(snapshot, messageIndex: indices.messageIndex, windowIndex: indices.windowIndex)
            mutationError = error.localizedDescription
            AppHaptics.warning()
        }
    }

    private func markRead(_ msg: MailMessageSummary) async {
        mutationError = nil
        locallyReadIds.insert(msg.id)
        if let threadId = msg.threadId {
            locallyReadIds.insert(threadId)
        }
        do {
            try await gmailMarkRead(messageId: msg.id, threadId: msg.threadId)
            applyLocalRead(msg.id)
            AppHaptics.light()
        } catch {
            locallyReadIds.remove(msg.id)
            if let threadId = msg.threadId {
                locallyReadIds.remove(threadId)
            }
            mutationError = error.localizedDescription
            AppHaptics.warning()
        }
    }

    private func connectGmail() async {
        if useDirectGmail {
            gmailOAuth.connect()
            // Rafraîchir l’état après callback OAuth (deep link).
            try? await Task.sleep(nanoseconds: 500_000_000)
            await loadOAuth()
            if gmailOAuth.isConnected {
                scheduleLoad(resetPagination: true)
            } else if let err = gmailOAuth.lastError {
                self.error = err
            }
            return
        }
        do {
            let url = try await client.gmailAuthorizationURL()
            await MainActor.run { UIApplication.shared.open(url) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MailRow: View {
    @Environment(\.themeRevision) private var themeRevision
    let message: MailMessageSummary

    var body: some View {
        let _ = themeRevision
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
    @EnvironmentObject private var infra: InfrastructureStore
    @Environment(AppNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var executionMode = ExecutionModeStore.shared
    let summary: MailMessageSummary
    /// Notifie la liste parente (lu local) — sans refresh réseau de l’inbox.
    var onMarkedRead: (() -> Void)? = nil
    @State private var thread: MailThreadDTO?
    @State private var error: String?
    @State private var loading = true
    @State private var didNotifyRead = false
    @State private var summaryText: String?
    @State private var replyDraft: String?
    @State private var replyDraftId: String?
    @State private var replyDraftTo = ""
    @State private var replyDraftSubject = ""
    @State private var replyAttachments: [EmailDraftAttachmentChip] = []
    @State private var replyRecipientSuggestions: [MailRecipientSuggestion] = []
    @State private var replyRecipientSuggestTask: Task<Void, Never>?
    @State private var editingDraft = false
    @State private var aiBusy = false
    @State private var aiStatus: String?
    @State private var draftStreaming = false
    @State private var trashing = false
    @State private var showAssistant = false
    @State private var assistantDetent: PresentationDetent = .large
    @State private var confirmSend = false
    @State private var sendStatus: String?
    @State private var aiTask: Task<Void, Never>?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var useDirectGmail: Bool {
        MailDataSource.prefersDirect(session: session, execution: executionMode, infra: infra)
    }

    private var usesOnDeviceAI: Bool {
        session.localOnlyMode || executionMode.routesLocalCapableOnDevice
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
        }
        .overlay(alignment: .bottomTrailing) {
            ContextualAssistantButton {
                assistantDetent = .large
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
                contextRef: assistantContext.ref,
                persistenceKey: assistantContext.persistenceKey
            )
            .environmentObject(session)
            .environment(nav)
            .presentationDetents([.medium, .large], selection: $assistantDetent)
            .presentationDragIndicator(.visible)
            .onAppear { assistantDetent = .large }
        }
        .onChange(of: showAssistant) { _, presented in
            if presented { assistantDetent = .large }
        }
        .onChange(of: nav.assistantDismissToken) { _, _ in
            showAssistant = false
        }
            .alert(
                "Envoyer cette réponse ?",
                isPresented: $confirmSend
            ) {
                Button("Annuler", role: .cancel) {}
                Button("Confirmer") { Task { await sendDraft() } }
            } message: {
                Text("À \(summary.from?.email ?? "destinataire")")
            }
        .task {
            // Liste parent mise à jour tout de suite (pas au retour + pas de reload inbox).
            notifyReadLocallyIfNeeded()
            await load()
        }
        .onDisappear {
            aiTask?.cancel()
            aiTask = nil
            if usesOnDeviceAI {
                Task { await LocalAIRuntime.shared.cancel() }
            }
        }
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
                        toText: $replyDraftTo,
                        subjectText: $replyDraftSubject,
                        draftId: replyDraftId,
                        statusLabel: draftStreaming ? "Rédaction…" : "Brouillon",
                        isEditing: editingDraft,
                        busy: aiBusy,
                        isStreaming: draftStreaming,
                        attachments: replyAttachments,
                        recipientSuggestions: replyRecipientSuggestions,
                        onSelectSuggestion: { _ in
                            replyRecipientSuggestions = []
                        },
                        onRecipientQueryChanged: { query in
                            scheduleReplyRecipientSuggestions(query: query)
                        },
                        onEditToggle: {
                            editingDraft.toggle()
                            replyRecipientSuggestions = []
                        },
                        onRetry: {
                            aiTask?.cancel()
                            aiTask = Task { await runSuggest() }
                        },
                        onSend: { confirmSend = true },
                        onCommitHeaders: {
                            Task { await commitReplyDraftHeaders() }
                        }
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
        Button {
            nav.openSettings()
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .accessibilityLabel("Réglages")
        .accessibilityIdentifier(A11yID.Mail.settings)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if useDirectGmail {
                let direct = try await DirectGmailProvider().getThread(id: threadId)
                thread = MailThreadDTO(
                    id: direct.id,
                    subject: direct.subject ?? summary.subject,
                    messages: direct.messages.map { msg in
                        MailThreadMessage(
                            id: msg.id,
                            threadId: msg.threadId ?? direct.threadId ?? direct.id,
                            from: MailInboxView.parseDirectFrom(msg.from),
                            subject: msg.subject,
                            date: msg.date,
                            snippet: msg.snippet,
                            bodyText: msg.bodyPlain,
                            bodyHtml: msg.bodyHtml,
                            isUnread: msg.labelIds.contains("UNREAD"),
                            hasAttachments: nil,
                            attachments: nil
                        )
                    }
                )
                error = nil
                do {
                    try await DirectGmailProvider().markRead(messageId: summary.id, threadId: threadId)
                    notifyReadLocallyIfNeeded()
                } catch {
                    // Fil ouvert ; pastille inbox conservée tant que Gmail n’a pas accepté.
                }
                return
            }
            thread = try await client.fetchMailThread(id: threadId)
            error = nil
            do {
                try await client.markMailRead(id: summary.id)
                notifyReadLocallyIfNeeded()
            } catch {
                // même règle : pas de succès faux
            }
        } catch is CancellationError {
            return
        } catch {
            if case APIClientError.http(let code, _) = error, code >= 500 {
                self.error = "Le serveur n’a pas pu ouvrir ce mail (HTTP \(code)). Réessaie."
            } else {
                self.error = error.localizedDescription
            }
            if case APIClientError.unauthorized = error, !useDirectGmail, !session.localOnlyMode {
                await session.logout()
            }
        }
    }

    private func notifyReadLocallyIfNeeded() {
        guard !didNotifyRead else { return }
        didNotifyRead = true
        // Optimistic dès que le fil est chargé — la liste se met à jour sans reload.
        onMarkedRead?()
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
            if usesOnDeviceAI {
                if !LocalModelManager.shared.isReady {
                    await LocalModelManager.shared.loadIntoEngine()
                }
                let text = try await MailSummarizeWorkflow.run(
                    .init(threadId: threadId),
                    runtime: LocalAIRuntime.shared,
                    onToken: { token in
                        self.aiStatus = nil
                        self.summaryText = (self.summaryText ?? "") + token
                    }
                )
                summaryText = text
                AppHaptics.success()
                return
            }
            final class Box: @unchecked Sendable { var value = "" }
            let box = Box()
            try await client.streamSummarizeMail(threadId: threadId) { token in
                box.value += token
                let snapshot = box.value
                Task { @MainActor in
                    self.aiStatus = nil
                    self.summaryText = snapshot
                }
            }
            AppHaptics.success()
        } catch is CancellationError {
            return
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
            if usesOnDeviceAI {
                if !LocalModelManager.shared.isReady {
                    await LocalModelManager.shared.loadIntoEngine()
                }
                replyDraft = ""
                let confirmation = try await MailReplyWorkflow.run(
                    .init(threadId: threadId, instruction: "Propose une réponse au dernier message."),
                    runtime: LocalAIRuntime.shared,
                    onToken: { token in
                        self.aiStatus = nil
                        self.replyDraft = (self.replyDraft ?? "") + token
                    }
                )
                replyDraft = confirmation.proposedBody
                replyDraftId = confirmation.draftId
                if replyDraftTo.isEmpty { replyDraftTo = confirmation.to }
                if replyDraftSubject.isEmpty { replyDraftSubject = confirmation.subject }
                AppHaptics.success()
                return
            }
            let result = try await client.streamSuggestMailReply(threadId: threadId) { token in
                Task { @MainActor in
                    self.aiStatus = nil
                    self.replyDraft = (self.replyDraft ?? "") + token
                }
            }
            replyDraft = result.bodyText
            replyDraftId = result.draftId
            if !result.to.isEmpty {
                replyDraftTo = result.to.joined(separator: ", ")
            } else if replyDraftTo.isEmpty, let email = summary.from?.email {
                replyDraftTo = email
            }
            if let subject = result.subject, !subject.isEmpty {
                replyDraftSubject = subject
            } else if replyDraftSubject.isEmpty, let subject = summary.subject {
                replyDraftSubject = subject.hasPrefix("Re:") ? subject : "Re: \(subject)"
            }
            if let id = result.draftId {
                await refreshReplyDraftAttachments(id: id)
            }
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendDraft() async {
        guard var body = replyDraft else { return }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        aiBusy = true
        defer { aiBusy = false }
        do {
            if usesOnDeviceAI {
                body = MailThreadPromptBuilder.plainBodyForSend(body)
                let toJoined = replyDraftTo
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                if GmailOAuthSession.shared.isConnected {
                    let gmail = DirectGmailProvider()
                    if let draftId = replyDraftId, !draftId.isEmpty {
                        try await gmail.sendDraft(id: draftId)
                    } else if !toJoined.isEmpty {
                        try await gmail.sendMessage(
                            to: toJoined,
                            subject: replyDraftSubject,
                            body: body,
                            threadId: threadId
                        )
                    } else {
                        NativeMailShare.presentComposer(
                            to: replyDraftTo,
                            subject: replyDraftSubject,
                            body: body
                        )
                        sendStatus = "Brouillon ouvert dans Mail."
                        return
                    }
                } else {
                    NativeMailShare.presentComposer(
                        to: replyDraftTo,
                        subject: replyDraftSubject,
                        body: body
                    )
                    sendStatus = "Brouillon ouvert dans Mail."
                    return
                }
                sendStatus = "Message envoyé."
                AppHaptics.success()
                return
            }
            guard let draftId = replyDraftId else { return }
            let to = replyDraftTo
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            try await client.updateEmailDraft(
                id: draftId,
                bodyText: body,
                to: to.isEmpty ? nil : to,
                subject: replyDraftSubject
            )
            try await client.validateEmailDraft(id: draftId)
            let proposal = try await client.proposeEmailSend(draftId: draftId)
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

    private func commitReplyDraftHeaders() async {
        guard let draftId = replyDraftId else { return }
        let to = replyDraftTo
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            try await client.updateEmailDraft(
                id: draftId,
                bodyText: replyDraft,
                to: to.isEmpty ? nil : to,
                subject: replyDraftSubject
            )
            replyRecipientSuggestions = []
            AppHaptics.light()
        } catch {
            self.error = error.localizedDescription
            AppHaptics.warning()
        }
    }

    private func scheduleReplyRecipientSuggestions(query: String) {
        replyRecipientSuggestTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard editingDraft, q.count >= 1 else {
            replyRecipientSuggestions = []
            return
        }
        replyRecipientSuggestTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            do {
                let rows = try await client.suggestMailRecipients(query: q)
                guard !Task.isCancelled else { return }
                await MainActor.run { replyRecipientSuggestions = rows }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { replyRecipientSuggestions = [] }
            }
        }
    }

    private func refreshReplyDraftAttachments(id: String) async {
        do {
            let detail = try await client.fetchEmailDraft(id: id)
            replyAttachments = detail.attachments
            if replyDraftTo.isEmpty {
                replyDraftTo = detail.to.joined(separator: ", ")
            }
            if replyDraftSubject.isEmpty {
                replyDraftSubject = detail.subject
            }
        } catch {
            // best-effort
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
