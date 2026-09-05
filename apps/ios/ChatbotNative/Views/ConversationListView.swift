import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var items: [ConversationDTO] = []
    @State private var error: String?
    @State private var loading = false
    @State private var renameTarget: ConversationDTO?
    @State private var renameText = ""

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                Group {
                    if loading && items.isEmpty {
                        SoftSkeletonList(rows: 5)
                    } else if items.isEmpty {
                        emptyState
                    } else {
                        conversationList
                    }
                }
            }
            .navigationTitle("Chat")
            .tabRootNavigationChrome()
            .navigationDestination(for: ConversationDTO.self) { conv in
                ChatScreen(conversation: conv)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await create() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .accessibilityLabel("Nouvelle conversation")
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .alert("Renommer", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Titre", text: $renameText)
                Button("Annuler", role: .cancel) { renameTarget = nil }
                Button("Enregistrer") {
                    Task { await commitRename() }
                }
            }
        }
    }

    private var emptyState: some View {
        SoftEmptyState(
            systemImage: "bubble.left.and.bubble.right",
            title: "Aucune conversation",
            message: "Démarre un nouveau chat pour parler au modèle local.",
            actionTitle: "Nouveau chat"
        ) {
            Task { await create() }
        }
    }

    private var conversationList: some View {
        List {
            if let error {
                Text(error)
                    .foregroundStyle(AppTheme.danger)
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { conv in
                NavigationLink(value: conv) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(conv.title?.isEmpty == false ? conv.title! : "Nouvelle conversation")
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.foreground)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            if let mode = conv.chatMode, mode == "agent" {
                                Text("Agent")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.accentSubtle)
                                    .clipShape(Capsule())
                            }
                            if let updated = conv.updatedAt {
                                Text(Self.friendlyDate(updated))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.mutedForeground)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(AppTheme.borderSubtle)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await delete(conv) }
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                    .tint(AppTheme.danger)
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
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await client.listConversations()
            error = nil
        } catch {
            self.error = error.localizedDescription
            if case APIClientError.unauthorized = error {
                await session.logout()
            }
        }
    }

    private func create() async {
        do {
            let created = try await client.createConversation()
            items.insert(created, at: 0)
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

    private static func friendlyDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "fr_FR")
        rel.unitsStyle = .short
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
