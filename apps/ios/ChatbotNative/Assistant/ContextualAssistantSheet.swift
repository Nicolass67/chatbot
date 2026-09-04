import SwiftUI

/// Sheet Assistant in-place (Mail / Files) — conserve l’écran hôte derrière.
struct ContextualAssistantSheet: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss

    let scope: ConversationScope
    let title: String
    let contextLabel: String
    let contextRef: ActiveContextHint

    @State private var conversation: ConversationDTO?
    @State private var error: String?
    @State private var booting = true
    @State private var showHistory = false

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
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
                            activeContext: contextRef
                        )
                        .id(conversation.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        .preferredColorScheme(.dark)
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
            if let key = contextRef.mailThreadId ?? contextRef.fileId {
                let storageKind: ChatContextRequest.Kind = scope == .mail ? .mail : .file
                let req = ChatContextRequest(
                    kind: storageKind,
                    key: key,
                    title: title,
                    prefill: "",
                    forcePrefill: false
                )
                if let existing = ContextualChatStore.conversationId(for: req) {
                    let all = try await client.listConversations(scope: scope)
                    if let match = all.first(where: { $0.id == existing }) {
                        conversation = match
                        error = nil
                        return
                    }
                }
                let created = try await client.createConversation(
                    scope: scope,
                    contextKey: key,
                    contextLabel: contextLabel,
                    title: title
                )
                ContextualChatStore.save(conversationId: created.id, for: req)
                conversation = created
            } else {
                let created = try await client.createConversation(
                    scope: scope,
                    contextKey: nil,
                    contextLabel: contextLabel,
                    title: title
                )
                conversation = created
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createFresh() async {
        do {
            let created = try await client.createConversation(
                scope: scope,
                contextKey: contextRef.mailThreadId ?? contextRef.fileId,
                contextLabel: contextLabel,
                title: title
            )
            if let key = contextRef.mailThreadId ?? contextRef.fileId {
                let storageKind: ChatContextRequest.Kind = scope == .mail ? .mail : .file
                ContextualChatStore.save(
                    conversationId: created.id,
                    for: ChatContextRequest(kind: storageKind, key: key, title: title, prefill: "")
                )
            }
            conversation = created
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Host chat minimal réutilisant ChatScreen pour un scope donné.
struct AssistantChatHost: View {
    @EnvironmentObject private var session: AppSessionStore
    let conversation: ConversationDTO
    let scope: ConversationScope
    let activeContext: ActiveContextHint

    var body: some View {
        ChatScreen(
            conversation: conversation,
            forcedScope: scope,
            forcedActiveContext: activeContext
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
                                        Text(item.title ?? "Conversation")
                                            .foregroundStyle(AppTheme.foreground)
                                        if let label = item.contextLabel, !label.isEmpty {
                                            Text(label)
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.mutedForeground)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if item.id == activeId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                            }
                            .listRowBackground(AppTheme.surface.opacity(0.5))
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
        }
        .preferredColorScheme(.dark)
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
}
