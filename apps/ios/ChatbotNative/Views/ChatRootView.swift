import SwiftUI

/// Racine Chat Mobile 3.0 — restaure la conversation générale ; « Nouveau chat » seul réinitialise.
struct ChatRootView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav

    @State private var conversation: ConversationDTO?
    @State private var booting = true
    @State private var bootError: String?
    @State private var showSwitcher = false

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let conversation {
                    ChatScreen(
                        conversation: conversation,
                        onOpenHistory: { showSwitcher = true },
                        onOpenSettings: { nav.openSettings() }
                    )
                    .id(conversation.id)
                } else if booting {
                    SoftLoadingBlock(label: "Préparation du chat…")
                } else {
                    SoftEmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        title: "Impossible d’ouvrir le chat",
                        message: bootError ?? "Réessaie pour créer une conversation.",
                        actionTitle: "Réessayer"
                    ) {
                        Task { await bootOrRestoreGeneral(forceNew: false) }
                    }
                }
            }
            .accessibilityIdentifier(A11yID.Chat.root)
        }
        .task {
            if UserDefaults.standard.bool(forKey: "intent.requestNewChat") {
                UserDefaults.standard.set(false, forKey: "intent.requestNewChat")
                await bootOrRestoreGeneral(forceNew: true)
            } else if let req = nav.chatContextRequest {
                await openContextChat(req)
            } else if conversation == nil {
                await bootOrRestoreGeneral(forceNew: false)
            }
        }
        .sheet(isPresented: $showSwitcher) {
            ConversationSwitcherSheet(
                activeId: conversation?.id,
                onSelect: { selected in
                    ConversationSessionStore.save(
                        conversationId: selected.id,
                        scope: .general
                    )
                    conversation = selected
                    showSwitcher = false
                },
                onCreated: { created in
                    ConversationSessionStore.save(
                        conversationId: created.id,
                        scope: .general
                    )
                    conversation = created
                    showSwitcher = false
                }
            )
            .environmentObject(session)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: nav.openConversationId) { _, id in
            guard let id else { return }
            if id == "__new__" {
                nav.openConversationId = nil
                Task { await bootOrRestoreGeneral(forceNew: true) }
                return
            }
            Task { await openExisting(id: id) }
        }
        .onChange(of: nav.chatContextRequest) { _, req in
            guard let req else { return }
            Task { await openContextChat(req) }
        }
        .onAppear {
            if let conversation {
                ConversationSessionStore.save(
                    conversationId: conversation.id,
                    scope: .general
                )
            }
        }
    }

    /// Restaure la conversation générale active, ou en crée une si absente / `forceNew`.
    private func bootOrRestoreGeneral(forceNew: Bool) async {
        booting = true
        bootError = nil
        defer { booting = false }
        do {
            if forceNew {
                if let old = conversation?.id {
                    ConversationSessionStore.clear(
                        conversationId: old,
                        scope: .general
                    )
                } else {
                    ConversationSessionStore.clear(scope: .general)
                }
                let created = try await client.createConversation(scope: .general)
                ConversationSessionStore.save(conversationId: created.id, scope: .general)
                conversation = created
                return
            }
            if let existing = ConversationSessionStore.conversationId(scope: .general) {
                let list = try await client.listConversations(scope: .general)
                if let match = list.first(where: { $0.id == existing }) {
                    conversation = match
                    return
                }
            }
            // Dernière conversation récente plutôt qu'un vide systématique
            let list = try await client.listConversations(scope: .general)
            if let recent = list.first {
                ConversationSessionStore.save(conversationId: recent.id, scope: .general)
                conversation = recent
                return
            }
            let created = try await client.createConversation(scope: .general)
            ConversationSessionStore.save(conversationId: created.id, scope: .general)
            conversation = created
        } catch {
            bootError = error.localizedDescription
            conversation = nil
            if case APIClientError.unauthorized = error {
                await session.logout()
            }
        }
    }

    private func openExisting(id: String) async {
        do {
            let list = try await client.listConversations(scope: .general)
            if let match = list.first(where: { $0.id == id }) {
                ConversationSessionStore.save(conversationId: match.id, scope: .general)
                conversation = match
            }
            nav.openConversationId = nil
        } catch {
            bootError = error.localizedDescription
        }
    }

    private func openContextChat(_ req: ChatContextRequest) async {
        nav.chatContextRequest = nil
        switch req.kind {
        case .mail:
            nav.openMailAssistant(.thread(threadId: req.key, subject: req.title, from: nil))
        case .file:
            // Pas d’assistant Files : rester sur le Chat général persisté + préremplir.
            nav.askAboutFile(fileId: req.key, name: req.title)
        }
    }
}

/// Switcher d’historique (sheet) — remplace la liste comme racine Chat.
struct ConversationSwitcherSheet: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dismiss) private var dismiss

    var activeId: String? = nil
    let onSelect: (ConversationDTO) -> Void
    let onCreated: (ConversationDTO) -> Void

    @State private var items: [ConversationDTO] = []
    @State private var error: String?
    @State private var loading = false
    @State private var renameTarget: ConversationDTO?
    @State private var renameText = ""
    @State private var search = ""

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var filtered: [ConversationDTO] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private var sectioned: [(title: String, items: [ConversationDTO])] {
        let calendar = Calendar.current
        let now = Date()
        var today: [ConversationDTO] = []
        var yesterday: [ConversationDTO] = []
        var week: [ConversationDTO] = []
        var older: [ConversationDTO] = []

        for conv in filtered {
            guard let date = Self.parseDate(conv.updatedAt) else {
                older.append(conv)
                continue
            }
            if calendar.isDateInToday(date) {
                today.append(conv)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(conv)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
                week.append(conv)
            } else {
                older.append(conv)
            }
        }

        var out: [(String, [ConversationDTO])] = []
        if !today.isEmpty { out.append(("Aujourd’hui", today)) }
        if !yesterday.isEmpty { out.append(("Hier", yesterday)) }
        if !week.isEmpty { out.append(("Cette semaine", week)) }
        if !older.isEmpty { out.append(("Plus ancien", older)) }
        return out
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                Group {
                    if loading && items.isEmpty {
                        SoftSkeletonList(rows: 5)
                    } else if items.isEmpty {
                        SoftEmptyState(
                            systemImage: "bubble.left.and.bubble.right",
                            title: "Aucune conversation",
                            message: "Les chats passés apparaîtront ici.",
                            actionTitle: "Nouveau chat"
                        ) {
                            Task { await create() }
                        }
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Rechercher")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await create() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Nouvelle conversation")
                    .accessibilityIdentifier(A11yID.Chat.newConversation)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton()
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("Renommer", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Titre", text: $renameText)
                Button("Annuler", role: .cancel) { renameTarget = nil }
                Button("Enregistrer") { Task { await commitRename() } }
            }
        }
    }

    private var list: some View {
        List {
            if let error {
                Text(error)
                    .foregroundStyle(AppTheme.danger)
                    .listRowBackground(Color.clear)
            }
            ForEach(sectioned, id: \.title) { section in
                Section {
                    ForEach(section.items) { conv in
                        conversationRow(conv)
                    }
                } header: {
                    Text(section.title)
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func conversationRow(_ conv: ConversationDTO) -> some View {
        let isActive = conv.id == activeId
        return Button {
            onSelect(conv)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conv.title?.isEmpty == false ? conv.title! : "Nouvelle conversation")
                        .font(.body.weight(isActive ? .semibold : .medium))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let mode = conv.chatMode, mode == "agent" {
                            Text("Agent")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        if let updated = conv.updatedAt {
                            Text(Self.friendlyDate(updated))
                                .font(.caption)
                                .foregroundStyle(AppTheme.mutedForeground)
                        }
                    }
                }
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("Conversation active")
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? AppTheme.accent.opacity(0.08) : Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await delete(conv) }
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                renameTarget = conv
                renameText = conv.title ?? ""
            } label: {
                Label("Renommer", systemImage: "pencil")
            }
            .tint(AppTheme.accent)
        }
        .contextMenu {
            Button("Ouvrir", systemImage: "bubble.left") { onSelect(conv) }
            Button("Renommer", systemImage: "pencil") {
                renameTarget = conv
                renameText = conv.title ?? ""
            }
            Button("Supprimer", systemImage: "trash", role: .destructive) {
                Task { await delete(conv) }
            }
        }
        .accessibilityLabel(conv.title ?? "Nouvelle conversation")
        .accessibilityValue(isActive ? "Active" : "")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await client.listConversations(scope: .general)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create() async {
        do {
            let created = try await client.createConversation(scope: .general)
            ConversationSessionStore.save(conversationId: created.id, scope: .general)
            items.insert(created, at: 0)
            onCreated(created)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ conv: ConversationDTO) async {
        do {
            try await client.deleteConversation(id: conv.id)
            items.removeAll { $0.id == conv.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func commitRename() async {
        guard let target = renameTarget else { return }
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            let updated = try await client.renameConversation(id: target.id, title: title)
            if let idx = items.firstIndex(where: { $0.id == target.id }) {
                items[idx] = updated
            }
            renameTarget = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func parseDate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private static func friendlyDate(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "fr_FR")
        rel.unitsStyle = .short
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
