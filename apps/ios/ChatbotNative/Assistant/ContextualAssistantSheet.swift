import SwiftUI

/// Sheet Assistant in-place (Mail) — conserve l’écran hôte derrière.
/// Conversation persistante : fermer ≠ recréer (sauf « Nouvelle conversation »).
struct ContextualAssistantSheet: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss

    let scope: ConversationScope
    let title: String
    let contextLabel: String
    let contextRef: ActiveContextHint
    /// Clé de persistance explicite (Mail thread / Files folder|file|global).
    var persistenceKey: String? = nil

    @State private var conversation: ConversationDTO?
    @State private var error: String?
    @State private var booting = true
    @State private var showHistory = false

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var contextKey: String {
        if let persistenceKey, !persistenceKey.isEmpty { return persistenceKey }
        return contextRef.mailThreadId
            ?? contextRef.fileId
            ?? ConversationSessionStore.globalContextKey
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextChip
                    .accessibilityIdentifier(A11yID.Assistant.contextChip)
                ZStack {
                    AmbientBackground()
                    if booting {
                        SoftLoadingBlock(label: "Préparation de l’assistant…")
                    } else if let error {
                        SoftEmptyState(
                            systemImage: "exclamationmark.triangle",
                            title: "Impossible d’ouvrir",
                            message: error,
                            actionTitle: "Réessayer"
                        ) { Task { await boot() } }
                    } else if let conversation {
                        AssistantChatHost(
                            conversation: conversation,
                            scope: scope,
                            activeContext: contextRef,
                            persistenceKey: contextKey,
                            onRequestClose: { dismiss() }
                        )
                        .id(conversation.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                        .accessibilityIdentifier(A11yID.Assistant.close)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock")
                    }
                    .accessibilityLabel(scope.historyTitle)
                    .accessibilityIdentifier(A11yID.Assistant.history)
                }
            }
            .sheet(isPresented: $showHistory) {
                ScopedConversationSwitcher(
                    scope: scope,
                    activeId: conversation?.id,
                    onSelect: { conv in
                        ConversationSessionStore.save(
                            conversationId: conv.id,
                            scope: scope,
                            contextKey: contextKey
                        )
                        conversation = conv
                        showHistory = false
                    },
                    onCreate: {
                        Task {
                            await createFresh()
                            showHistory = false
                        }
                    }
                )
                .environmentObject(session)
                .presentationDetents([.medium, .large])
            }
            .task { await boot() }
        }
        .accessibilityIdentifier(A11yID.Assistant.root)
    }

    private var contextChip: some View {
        HStack(spacing: 8) {
            Image(systemName: scope == .mail ? "envelope.fill" : "folder.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            Text(contextLabel)
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.surface.opacity(0.9))
        .overlay(alignment: .bottom) {
            Divider().overlay(AppTheme.borderSubtle)
        }
    }

    private func boot() async {
        booting = true
        defer { booting = false }
        do {
            if let existing = ConversationSessionStore.conversationId(
                scope: scope,
                contextKey: contextKey
            ) {
                let all = try await client.listConversations(scope: scope)
                if let match = all.first(where: { $0.id == existing }) {
                    conversation = match
                    error = nil
                    return
                }
            }
            let created = try await client.createConversation(
                scope: scope,
                contextKey: contextKey == ConversationSessionStore.globalContextKey
                    ? nil
                    : contextKey,
                contextLabel: contextLabel,
                title: Self.seedTitle(sheetTitle: title, contextLabel: contextLabel)
            )
            ConversationSessionStore.save(
                conversationId: created.id,
                scope: scope,
                contextKey: contextKey
            )
            conversation = created
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createFresh() async {
        do {
            if let old = conversation?.id {
                ConversationSessionStore.clear(
                    conversationId: old,
                    scope: scope,
                    contextKey: contextKey
                )
            } else {
                ConversationSessionStore.clear(scope: scope, contextKey: contextKey)
            }
            let created = try await client.createConversation(
                scope: scope,
                contextKey: contextKey == ConversationSessionStore.globalContextKey
                    ? nil
                    : contextKey,
                contextLabel: contextLabel,
                title: Self.seedTitle(sheetTitle: title, contextLabel: contextLabel)
            )
            ConversationSessionStore.save(
                conversationId: created.id,
                scope: scope,
                contextKey: contextKey
            )
            conversation = created
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Titre initial : objet mail / nom fichier si pertinent ; sinon nil → placeholder auto côté API.
    private static func seedTitle(sheetTitle: String, contextLabel: String?) -> String? {
        let placeholders: Set<String> = [
            "Mail Assistant", "Files Assistant",
            "Assistant Mail", "Assistant Files",
            "Nouvelle conversation", "Nouveau chat",
        ]
        let fromContext = contextLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromContext.isEmpty, !placeholders.contains(fromContext) {
            return String(fromContext.prefix(80))
        }
        let fromSheet = sheetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromSheet.isEmpty, !placeholders.contains(fromSheet) {
            return String(fromSheet.prefix(80))
        }
        return nil
    }
}

/// Host chat minimal réutilisant ChatScreen pour un scope donné.
struct AssistantChatHost: View {
    @EnvironmentObject private var session: AppSessionStore
    let conversation: ConversationDTO
    let scope: ConversationScope
    let activeContext: ActiveContextHint
    var persistenceKey: String? = nil
    var onRequestClose: (() -> Void)? = nil

    var body: some View {
        ChatScreen(
            conversation: conversation,
            forcedScope: scope,
            forcedActiveContext: activeContext,
            persistenceKeyOverride: persistenceKey,
            onRequestClose: onRequestClose
        )
        .environmentObject(session)
    }
}

struct ScopedConversationSwitcher: View {
    @EnvironmentObject private var session: AppSessionStore
    let scope: ConversationScope
    var activeId: String?
    var onSelect: (ConversationDTO) -> Void
    var onCreate: () -> Void

    @State private var items: [ConversationDTO] = []
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var renameTarget: ConversationDTO?
    @State private var renameText = ""

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var filtered: [ConversationDTO] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { ($0.title ?? "").localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading && items.isEmpty {
                    SoftLoadingBlock(label: "Chargement…")
                } else if let error, items.isEmpty {
                    SoftEmptyState(
                        systemImage: "exclamationmark.triangle",
                        title: "Erreur",
                        message: error,
                        actionTitle: "Réessayer"
                    ) { Task { await load() } }
                } else if filtered.isEmpty {
                    SoftEmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        title: scope.historyTitle,
                        message: scope.emptyHistoryMessage,
                        actionTitle: "Nouvelle conversation"
                    ) { onCreate() }
                } else {
                    List {
                        ForEach(filtered) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title?.isEmpty == false ? item.title! : "Conversation")
                                            .font(.body.weight(item.id == activeId ? .semibold : .regular))
                                            .foregroundStyle(AppTheme.foreground)
                                            .lineLimit(1)
                                        if let label = item.contextLabel, !label.isEmpty {
                                            Text(label)
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.mutedForeground)
                                                .lineLimit(1)
                                        }
                                        if let updated = item.updatedAt {
                                            Text(Self.friendlyDate(updated))
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.mutedForeground)
                                        }
                                    }
                                    Spacer()
                                    if item.id == activeId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(AppTheme.surface.opacity(0.5))
                            .swipeActions(edge: .leading) {
                                Button {
                                    renameTarget = item
                                    renameText = item.title ?? ""
                                } label: {
                                    Label("Renommer", systemImage: "pencil")
                                }
                                .tint(AppTheme.accent)
                            }
                            .contextMenu {
                                Button("Ouvrir", systemImage: "bubble.left") { onSelect(item) }
                                Button("Renommer", systemImage: "pencil") {
                                    renameTarget = item
                                    renameText = item.title ?? ""
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AmbientBackground())
            .navigationTitle(scope.historyTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Rechercher")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onCreate) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Nouvelle conversation")
                }
            }
            .task { await load() }
            .alert("Renommer la conversation", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Titre", text: $renameText)
                Button("Annuler", role: .cancel) { renameTarget = nil }
                Button("Enregistrer") { Task { await commitRename() } }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await client.listConversations(scope: scope)
            error = nil
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
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
            AppHaptics.warning()
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
