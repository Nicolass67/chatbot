import SwiftUI

/// Sélecteur d’emplacement moderne pour « Déplacer vers » (multi-sélection Files).
struct FilesMovePickerSheet: View {
    @EnvironmentObject private var session: AppSessionStore

    let itemCount: Int
    let previewNames: [String]
    var onCancel: () -> Void
    var onPick: (FilesSaveDestination) -> Void

    @State private var roots: [FileRootDTO] = []
    @State private var path = NavigationPath()
    @State private var loadingRoots = true
    @State private var rootsError: String?
    @State private var recent: [FilesSaveDestination] = []
    @State private var searchText = ""
    @State private var searchHits: [FileSearchHitDTO] = []
    @State private var searching = false
    @State private var currentFolder: MovePickerNav?
    @State private var folderRefresh = 0
    @State private var mkdirName = ""
    @State private var showMkdir = false
    @State private var mkdirConfirm: FilesProposeResult?
    @State private var confirmingMkdir = false
    @State private var pendingMkdirDest: String?
    @State private var actionError: String?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var isSearching: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var summaryLine: String {
        if itemCount <= 1 {
            return previewNames.first ?? "1 fichier"
        }
        let head = previewNames.prefix(2).joined(separator: ", ")
        let extra = itemCount - min(2, previewNames.count)
        if extra > 0 {
            return "\(head) +\(extra)"
        }
        return head
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .navigationTitle("Déplacer vers")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Chercher un dossier")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler", action: onCancel)
                    }
                }
                .navigationDestination(for: MovePickerNav.self) { folder in
                    moveFolderBrowser(folder)
                        .id("\(folder.root.id)|\(folder.path)|\(folderRefresh)")
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
        .alert("Déplacement", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
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
                        moveHeroCard
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    if !recent.isEmpty {
                        Section("Récents") {
                            ForEach(recent) { dest in
                                Button {
                                    AppHaptics.light()
                                    onPick(dest)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(AppTheme.filesAccent)
                                            .frame(width: 28)
                                        Text(dest.displayPath)
                                            .foregroundStyle(AppTheme.foreground)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundStyle(AppTheme.filesAccent.opacity(0.85))
                                    }
                                }
                                .listRowBackground(AppTheme.surface.opacity(0.4))
                            }
                        }
                    }

                    Section("Emplacements") {
                        ForEach(roots) { root in
                            Button {
                                let nav = MovePickerNav(
                                    root: root,
                                    path: "",
                                    title: root.label ?? "Racine"
                                )
                                currentFolder = nav
                                path.append(nav)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "externaldrive.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.filesAccent)
                                        .frame(width: 28)
                                    Text(root.label ?? "Racine")
                                        .foregroundStyle(AppTheme.foreground)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.muted)
                                }
                            }
                            .listRowBackground(AppTheme.surface.opacity(0.4))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var moveHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.filesAccent.opacity(0.95),
                                    AppTheme.accent.opacity(0.75),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(itemCount <= 1 ? "1 fichier à déplacer" : "\(itemCount) fichiers à déplacer")
                        .font(CNFont.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                    Text(summaryLine)
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
            }
            Text("Choisis un dossier, puis Déplacer ici. Les noms sont conservés.")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    AppTheme.filesAccent.opacity(0.45),
                                    AppTheme.borderSubtle,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
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

    private func moveFolderBrowser(_ folder: MovePickerNav) -> some View {
        MovePickerBrowser(
            root: folder.root,
            path: folder.path,
            title: folder.title,
            itemCount: itemCount,
            onOpenSubfolder: { entry in
                let next = MovePickerNav(
                    root: folder.root,
                    path: entry.relativePath,
                    title: entry.name ?? entry.relativePath
                )
                currentFolder = next
                path.append(next)
            },
            onMoveHere: {
                let dest = FilesSaveDestination(
                    rootId: folder.root.id,
                    rootLabel: folder.root.label ?? "Racine",
                    path: folder.path
                )
                AppHaptics.light()
                FilesRecentDestinations.remember(dest)
                onPick(dest)
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
        let rootNav = MovePickerNav(root: root, path: "", title: root.label ?? "Racine")
        path.append(rootNav)
        let normalized = folderPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normalized.isEmpty {
            var cumulative = ""
            for segment in normalized.split(separator: "/") {
                cumulative = cumulative.isEmpty ? String(segment) : "\(cumulative)/\(segment)"
                path.append(
                    MovePickerNav(
                        root: root,
                        path: cumulative,
                        title: String(segment)
                    )
                )
            }
        }
        currentFolder = MovePickerNav(
            root: root,
            path: normalized,
            title: hit.name ?? hit.filename ?? String(normalized.split(separator: "/").last ?? "Dossier")
        )
        searchText = ""
        searchHits = []
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
            actionError = error.localizedDescription
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
                let next = MovePickerNav(root: folder.root, path: dest, title: name)
                currentFolder = next
                path.append(next)
                folderRefresh += 1
            } else {
                pendingMkdirDest = nil
            }
        } catch {
            pendingMkdirDest = nil
            actionError = error.localizedDescription
        }
    }
}

private struct MovePickerNav: Hashable {
    let root: FileRootDTO
    let path: String
    let title: String
}

private struct MovePickerBrowser: View {
    @EnvironmentObject private var session: AppSessionStore
    let root: FileRootDTO
    let path: String
    let title: String
    let itemCount: Int
    let onOpenSubfolder: (FileEntryDTO) -> Void
    let onMoveHere: () -> Void
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
                                      ? "Aucun sous-dossier — tu peux déplacer ici."
                                      : "Dossier vide — tu peux déplacer ici.")
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
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().overlay(AppTheme.borderSubtle)
                Button(action: onMoveHere) {
                    Label(
                        itemCount <= 1 ? "Déplacer ici" : "Déplacer \(itemCount) ici",
                        systemImage: "folder.fill.badge.plus"
                    )
                    .font(CNFont.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.filesAccent)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
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
