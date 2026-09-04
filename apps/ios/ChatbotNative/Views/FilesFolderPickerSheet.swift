import SwiftUI

/// Destination récente pour « Enregistrer dans Files ».
struct FilesSaveDestination: Codable, Hashable, Identifiable {
    var id: String { "\(rootId)|\(path)" }
    let rootId: String
    let rootLabel: String
    let path: String

    var displayPath: String {
        let label = rootLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if p.isEmpty { return label.isEmpty ? "Racine" : label }
        return "\(label.isEmpty ? "Files" : label) / \(p.replacingOccurrences(of: "/", with: " / "))"
    }
}

private enum FilesRecentDestinations {
    private static let key = "files.recentSaveDestinations"
    private static let maxCount = 5

    static func load() -> [FilesSaveDestination] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([FilesSaveDestination].self, from: data)
        else { return [] }
        return items
    }

    static func remember(_ dest: FilesSaveDestination) {
        var items = load().filter { $0.id != dest.id }
        items.insert(dest, at: 0)
        if items.count > maxCount { items = Array(items.prefix(maxCount)) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

private struct FolderPickerNav: Hashable {
    let root: FileRootDTO
    let path: String
    let title: String
}

/// Sélecteur de dossier Files (racines → navigation → recherche → enregistrer ici).
struct FilesFolderPickerSheet: View {
    @EnvironmentObject private var session: AppSessionStore

    let filename: String
    let mimeType: String
    let loadData: () async throws -> Data
    var onFinished: (_ saved: Bool, _ destination: FilesSaveDestination?) -> Void

    @State private var roots: [FileRootDTO] = []
    @State private var path = NavigationPath()
    @State private var loadingRoots = true
    @State private var rootsError: String?
    @State private var recent: [FilesSaveDestination] = []
    @State private var searchText = ""
    @State private var searchHits: [FileSearchHitDTO] = []
    @State private var searching = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var mkdirName = ""
    @State private var showMkdir = false
    @State private var mkdirConfirm: FilesProposeResult?
    @State private var confirmingMkdir = false
    @State private var currentFolder: FolderPickerNav?
    @State private var folderRefresh = 0
    @State private var pendingMkdirDest: String?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var isSearching: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .navigationTitle("Enregistrer dans Files")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Chercher un dossier")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { onFinished(false, nil) }
                            .disabled(saving)
                    }
                }
                .navigationDestination(for: FolderPickerNav.self) { folder in
                    folderBrowser(folder)
                        .id("\(folder.root.id)|\(folder.path)|\(folderRefresh)")
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .task { await loadRoots() }
        .onChange(of: searchText) { _, q in
            Task { await runSearch(q) }
        }
        .alert("Nouveau dossier", isPresented: $showMkdir) {
            TextField("Nom", text: $mkdirName)
            Button("Annuler", role: .cancel) {
                mkdirName = ""
                pendingMkdirDest = nil
            }
            Button("Créer") { Task { await proposeMkdir() } }
        } message: {
            Text("Créé dans le dossier courant, après confirmation.")
        }
        .sheet(item: $mkdirConfirm) { proposal in
            MkdirConfirmSheet(
                detail: proposal.detail,
                confirming: confirmingMkdir,
                onConfirm: { Task { await resolveMkdir(proposal, confirm: true) } },
                onCancel: { Task { await resolveMkdir(proposal, confirm: false) } }
            )
        }
        .alert("Enregistrement", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        ZStack {
            AmbientBackground()
            if loadingRoots {
                SoftLoadingBlock(label: "Chargement des emplacements…")
            } else if let rootsError {
                SoftErrorBanner(message: rootsError) {
                    Task { await loadRoots() }
                }
                .padding()
            } else if isSearching {
                searchResultsList
            } else {
                List {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.badge.arrow.up")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(filename)
                                    .font(CNFont.callout.weight(.semibold))
                                    .foregroundStyle(AppTheme.foreground)
                                    .lineLimit(2)
                                Text("Choisis un dossier, puis Enregistrer ici.")
                                    .font(CNFont.caption2)
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        .listRowBackground(AppTheme.surface.opacity(0.55))
                    }

                    if !recent.isEmpty {
                        Section("Récents") {
                            ForEach(recent) { dest in
                                Button {
                                    Task { await save(to: dest) }
                                } label: {
                                    Label(dest.displayPath, systemImage: "clock.arrow.circlepath")
                                        .foregroundStyle(AppTheme.foreground)
                                }
                                .disabled(saving)
                                .listRowBackground(AppTheme.surface.opacity(0.35))
                            }
                        }
                    }

                    Section("Emplacements") {
                        ForEach(roots) { root in
                            Button {
                                let nav = FolderPickerNav(
                                    root: root,
                                    path: "",
                                    title: root.label ?? "Racine"
                                )
                                currentFolder = nav
                                path.append(nav)
                            } label: {
                                Label(root.label ?? "Racine", systemImage: "externaldrive.fill")
                                    .foregroundStyle(AppTheme.foreground)
                            }
                            .listRowBackground(AppTheme.surface.opacity(0.35))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }

            if saving {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView("Enregistrement…")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var searchResultsList: some View {
        List {
            if searching {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if searchHits.isEmpty {
                Text("Aucun dossier trouvé")
                    .foregroundStyle(AppTheme.muted)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(searchHits) { hit in
                    Button {
                        jumpToSearchHit(hit)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.name ?? hit.filename ?? "Dossier")
                                .font(CNFont.callout.weight(.medium))
                                .foregroundStyle(AppTheme.foreground)
                            if let rp = hit.relativePath, !rp.isEmpty {
                                Text(rp)
                                    .font(CNFont.caption2)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.surface.opacity(0.35))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func folderBrowser(_ folder: FolderPickerNav) -> some View {
        FolderPickerBrowser(
            root: folder.root,
            path: folder.path,
            title: folder.title,
            filename: filename,
            saving: saving,
            onOpenSubfolder: { entry in
                let next = FolderPickerNav(
                    root: folder.root,
                    path: entry.relativePath,
                    title: entry.name ?? entry.relativePath
                )
                currentFolder = next
                path.append(next)
            },
            onSaveHere: {
                let dest = FilesSaveDestination(
                    rootId: folder.root.id,
                    rootLabel: folder.root.label ?? "Racine",
                    path: folder.path
                )
                Task { await save(to: dest) }
            },
            onNewFolder: {
                currentFolder = folder
                showMkdir = true
            }
        )
        .onAppear { currentFolder = folder }
    }

    private func loadRoots() async {
        loadingRoots = true
        rootsError = nil
        defer { loadingRoots = false }
        do {
            let all = try await client.listFileRoots()
            roots = all.filter { $0.enabled != false }
            recent = FilesRecentDestinations.load().filter { dest in
                roots.contains(where: { $0.id == dest.rootId })
            }
            if roots.isEmpty {
                rootsError = "Aucun emplacement Files configuré."
            }
        } catch {
            rootsError = error.localizedDescription
        }
    }

    private func runSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            searchHits = []
            return
        }
        searching = true
        defer { searching = false }
        do {
            let hits = try await client.searchFiles(query: q, mode: "name")
            searchHits = hits.filter { $0.isDirectory == true }
        } catch {
            searchHits = []
        }
    }

    private func jumpToSearchHit(_ hit: FileSearchHitDTO) {
        guard let rootId = hit.rootId,
              let root = roots.first(where: { $0.id == rootId })
        else { return }
        let folderPath = hit.relativePath ?? ""
        path = NavigationPath()
        let rootNav = FolderPickerNav(root: root, path: "", title: root.label ?? "Racine")
        path.append(rootNav)
        let normalized = folderPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normalized.isEmpty {
            var cumulative = ""
            for segment in normalized.split(separator: "/") {
                cumulative = cumulative.isEmpty ? String(segment) : "\(cumulative)/\(segment)"
                path.append(
                    FolderPickerNav(
                        root: root,
                        path: cumulative,
                        title: String(segment)
                    )
                )
            }
        }
        currentFolder = FolderPickerNav(
            root: root,
            path: normalized,
            title: hit.name ?? hit.filename ?? String(normalized.split(separator: "/").last ?? "Dossier")
        )
        searchText = ""
        searchHits = []
    }

    private func save(to dest: FilesSaveDestination) async {
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            let data = try await loadData()
            try await client.uploadFiles(
                rootId: dest.rootId,
                destRelativePath: dest.path,
                filename: filename,
                data: data,
                mimeType: mimeType.isEmpty ? "application/octet-stream" : mimeType
            )
            FilesRecentDestinations.remember(dest)
            AppHaptics.success()
            onFinished(true, dest)
        } catch {
            AppHaptics.warning()
            saveError = error.localizedDescription
        }
    }

    private func proposeMkdir() async {
        let name = mkdirName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let folder = currentFolder else { return }
        mkdirName = ""
        let dest = folder.path.isEmpty ? name : "\(folder.path)/\(name)"
        pendingMkdirDest = dest
        do {
            let proposal = try await client.proposeCreateDirectory(
                rootId: folder.root.id,
                destRelativePath: dest
            )
            AppHaptics.light()
            try? await Task.sleep(nanoseconds: 450_000_000)
            mkdirConfirm = proposal
        } catch {
            pendingMkdirDest = nil
            saveError = error.localizedDescription
        }
    }

    private func resolveMkdir(_ pending: FilesProposeResult, confirm: Bool) async {
        confirmingMkdir = true
        defer {
            confirmingMkdir = false
            mkdirConfirm = nil
        }
        do {
            try await client.confirmFilesAction(
                actionId: pending.actionId,
                confirmationToken: pending.confirmationToken,
                confirm: confirm
            )
            if confirm, let folder = currentFolder {
                AppHaptics.success()
                let dest = (pendingMkdirDest ?? pending.destRelativePath)
                    .replacingOccurrences(of: "\\", with: "/")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                pendingMkdirDest = nil
                guard !dest.isEmpty else {
                    folderRefresh += 1
                    return
                }
                let name = dest.split(separator: "/").last.map(String.init) ?? dest
                let next = FolderPickerNav(root: folder.root, path: dest, title: name)
                currentFolder = next
                path.append(next)
                folderRefresh += 1
            } else {
                pendingMkdirDest = nil
            }
        } catch {
            pendingMkdirDest = nil
            saveError = error.localizedDescription
        }
    }
}

private struct FolderPickerBrowser: View {
    @EnvironmentObject private var session: AppSessionStore
    let root: FileRootDTO
    let path: String
    let title: String
    let filename: String
    let saving: Bool
    let onOpenSubfolder: (FileEntryDTO) -> Void
    let onSaveHere: () -> Void
    let onNewFolder: () -> Void

    @State private var folders: [FileEntryDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var fileCount = 0

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            Group {
                if loading {
                    SoftLoadingBlock(label: "Dossiers…")
                } else if let error {
                    SoftErrorBanner(message: error) {
                        Task { await load() }
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            Text(breadcrumb)
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.muted)
                                .listRowBackground(AppTheme.surface.opacity(0.35))
                        }

                        if folders.isEmpty {
                            Section {
                                Text(fileCount > 0
                                      ? "Aucun sous-dossier — tu peux enregistrer ici."
                                      : "Dossier vide — tu peux enregistrer ici.")
                                    .font(CNFont.callout)
                                    .foregroundStyle(AppTheme.muted)
                                    .listRowBackground(Color.clear)
                            }
                        } else {
                            Section("Dossiers") {
                                ForEach(folders) { entry in
                                    Button {
                                        onOpenSubfolder(entry)
                                    } label: {
                                        Label(
                                            entry.name ?? entry.relativePath,
                                            systemImage: "folder.fill"
                                        )
                                        .foregroundStyle(AppTheme.foreground)
                                    }
                                    .listRowBackground(AppTheme.surface.opacity(0.35))
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNewFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("Nouveau dossier")
                .disabled(saving)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().overlay(AppTheme.borderSubtle)
                Button(action: onSaveHere) {
                    Label("Enregistrer ici", systemImage: "square.and.arrow.down.fill")
                        .font(CNFont.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                Text(filename)
                    .font(CNFont.caption2)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
        .task(id: "\(root.id)|\(path)") { await load() }
    }

    private var breadcrumb: String {
        let label = root.label ?? "Racine"
        let p = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if p.isEmpty { return label }
        return "\(label) / \(p.replacingOccurrences(of: "/", with: " / "))"
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let list = try await client.listFiles(rootId: root.id, path: path)
            let dirs = list.entries.filter { $0.isDirectory == true }
                .sorted {
                    ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
                }
            folders = dirs
            fileCount = list.entries.filter { $0.isDirectory != true }.count
        } catch {
            self.error = error.localizedDescription
        }
    }
}
