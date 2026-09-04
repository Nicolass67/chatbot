import SwiftUI

struct MemoryDTO: Identifiable, Codable, Hashable {
    let id: String
    let content: String
    let category: String
    let importance: Double?
    let createdAt: String?
    let updatedAt: String?

    var categoryLabel: String {
        switch category {
        case "preference": return "Préférence"
        case "hardware": return "Matériel"
        case "project": return "Projet"
        case "habit": return "Habitude"
        case "communication": return "Communication"
        default: return "Souvenir"
        }
    }
}

struct MemoryListView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav

    @State private var items: [MemoryDTO] = []
    @State private var search = ""
    @State private var categoryFilter = "all"
    @State private var loading = false
    @State private var error: String?
    @State private var selected: MemoryDTO?
    @State private var showCreate = false
    @State private var deleteTarget: MemoryDTO?
    @State private var draftContent = ""
    @State private var creating = false

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var categoryOptions: [(id: String, label: String)] {
        var opts: [(id: String, label: String)] = [("all", "Toutes")]
        let cats = Set(items.map(\.category)).sorted()
        for cat in cats {
            let label = items.first { $0.category == cat }?.categoryLabel ?? cat
            opts.append((cat, label))
        }
        return opts
    }

    private var filteredItems: [MemoryDTO] {
        guard categoryFilter != "all" else { return items }
        return items.filter { $0.category == categoryFilter }
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            Group {
                if loading && items.isEmpty {
                    SoftLoadingBlock(label: "Chargement des souvenirs…")
                } else if let error, items.isEmpty {
                    SoftEmptyState(
                        systemImage: "exclamationmark.triangle",
                        title: "Impossible de charger",
                        message: error,
                        actionTitle: "Réessayer"
                    ) { Task { await load() } }
                } else if items.isEmpty {
                    SoftEmptyState(
                        systemImage: "brain.head.profile",
                        title: "Aucun souvenir",
                        message: "L’assistant enregistrera ici ce qu’il retient pour mieux t’aider. Tu peux aussi en ajouter.",
                        actionTitle: "Ajouter"
                    ) { showCreate = true }
                } else {
                    List {
                        Section {
                            Text("Les souvenirs restent sur ton PC. Tu peux les modifier ou les oublier à tout moment.")
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                        .listRowBackground(AppTheme.surface.opacity(0.35))

                        if filteredItems.isEmpty {
                            Text("Aucun souvenir dans cette catégorie.")
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.muted)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(filteredItems) { item in
                            Button {
                                selected = item
                            } label: {
                                MemoryRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(AppTheme.surface.opacity(0.6))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = item
                                } label: {
                                    Label("Oublier", systemImage: "trash")
                                }
                            }
                            .accessibilityLabel("\(item.categoryLabel). \(item.content)")
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Souvenirs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Rechercher un souvenir…")
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: search) { _, q in
            if q.isEmpty { Task { await load() } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Catégorie", selection: $categoryFilter) {
                        ForEach(categoryOptions, id: \.id) { opt in
                            Text(opt.label).tag(opt.id)
                        }
                    }
                } label: {
                    Label(
                        categoryFilter == "all" ? "Catégories" : (categoryOptions.first { $0.id == categoryFilter }?.label ?? "Catégories"),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                .accessibilityLabel("Filtrer par catégorie")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: AppTheme.touchMin, minHeight: AppTheme.touchMin)
                }
                .accessibilityLabel("Ajouter un souvenir")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissButton()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await load() }
        .task { await load() }
        .onAppear {
            if let id = nav.memoryDeepLink?.memoryId,
               let match = items.first(where: { $0.id == id }) {
                selected = match
            }
            nav.memoryDeepLink = nil
        }
        .sheet(item: $selected) { item in
            MemoryDetailSheet(
                item: item,
                onForget: {
                    selected = nil
                    deleteTarget = item
                },
                onSaved: { updated in
                    if let idx = items.firstIndex(where: { $0.id == updated.id }) {
                        items[idx] = updated
                    }
                    selected = updated
                }
            )
            .environmentObject(session)
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Que dois-je retenir ?", text: $draftContent, axis: .vertical)
                            .lineLimit(3...10)
                    } footer: {
                        Text("Écris en langage naturel. L’assistant classera le souvenir.")
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .navigationTitle("Nouveau souvenir")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { showCreate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") {
                            Task { await create() }
                        }
                        .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || creating)
                    }
                }
            }
        }
        .alert(
            "Oublier ce souvenir ?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) { deleteTarget = nil }
            Button("Oublier", role: .destructive) {
                if let target = deleteTarget {
                    Task { await forget(target) }
                }
                deleteTarget = nil
            }
        } message: {
            Text(deleteTarget?.content ?? "")
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            items = try await client.listMemories(query: q.isEmpty ? nil : q)
            error = nil
        } catch {
            self.error = error.localizedDescription
            if case APIClientError.unauthorized = error {
                await session.logout()
            }
        }
    }

    private func forget(_ item: MemoryDTO) async {
        do {
            try await client.deleteMemory(id: item.id)
            AppHaptics.warning()
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        let text = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 10 else { return }
        do {
            _ = try await client.createMemory(content: text)
            AppHaptics.success()
            draftContent = ""
            showCreate = false
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MemoryRow: View {
    let item: MemoryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            HStack {
                Text(item.categoryLabel)
                    .font(CNFont.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accentSubtle)
                    .clipShape(Capsule())
                Spacer()
                if let updated = item.updatedAt ?? item.createdAt {
                    Text(AppDates.short(updated))
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                }
            }
            Text(item.content)
                .font(CNFont.body)
                .foregroundStyle(AppTheme.foreground)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, AppTheme.space4)
        .frame(minHeight: AppTheme.touchMin, alignment: .leading)
    }
}

struct MemoryDetailSheet: View {
    let item: MemoryDTO
    var onForget: () -> Void
    var onSaved: ((MemoryDTO) -> Void)? = nil

    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var error: String?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space16) {
                    Text(item.categoryLabel)
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)

                    Text("Retenu pour personnaliser les réponses. Visible uniquement dans cette app. Tu peux modifier ou oublier à tout moment.")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)

                    if editing {
                        TextField("Contenu", text: $draft, axis: .vertical)
                            .lineLimit(4...16)
                            .font(CNFont.body)
                            .padding(AppTheme.space12)
                            .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    } else {
                        Text(item.content)
                            .font(CNFont.body)
                            .foregroundStyle(AppTheme.foreground)
                            .textSelection(.enabled)
                    }

                    if let error {
                        Text(error)
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.danger)
                    }

                    if let updated = item.updatedAt ?? item.createdAt {
                        Text("Mis à jour \(AppDates.friendly(updated))")
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.space24)
            }
            .background(AppTheme.background)
            .navigationTitle("Souvenir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editing ? "Annuler" : "Fermer") {
                        if editing {
                            editing = false
                            draft = item.content
                            error = nil
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if editing {
                        Button("Enregistrer") {
                            Task { await save() }
                        }
                        .disabled(saving || draft.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    } else {
                        Button("Modifier") {
                            draft = item.content
                            editing = true
                        }
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Oublier", role: .destructive, action: onForget)
                        .disabled(editing)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton()
                }
            }
        }
    }

    private func save() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        saving = true
        defer { saving = false }
        do {
            let updated = try await client.updateMemory(id: item.id, content: text)
            AppHaptics.success()
            editing = false
            onSaved?(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
