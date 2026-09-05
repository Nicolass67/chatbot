import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum FilesViewMode: String, CaseIterable, Identifiable {
    case list, grid, details
    var id: String { rawValue }
    var label: String {
        switch self {
        case .list: return "Liste"
        case .grid: return "Grille"
        case .details: return "Détails"
        }
    }
    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        case .details: return "list.bullet.rectangle"
        }
    }
}

enum FilesSortMode: String, CaseIterable, Identifiable {
    case name, date, size, type
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: return "Nom"
        case .date: return "Date"
        case .size: return "Taille"
        case .type: return "Type"
        }
    }
}

enum FilesTypeFilter: String, CaseIterable, Identifiable {
    case all, folders, images, pdf, documents, indexed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Tout"
        case .folders: return "Dossiers"
        case .images: return "Images"
        case .pdf: return "PDF"
        case .documents: return "Docs"
        case .indexed: return "Indexés"
        }
    }
}

/// Destination unique enregistrée à la racine du NavigationStack (évite destinations imbriquées).
enum FilesDestination: Hashable, Codable {
    case folder(rootId: String, path: String, title: String)
    case file(fileId: String, title: String, rootId: String, folderPath: String)
}

enum FilesIndexStatus: Equatable {
    case idle
    case indexing(rootLabel: String)
    case done(indexed: Int, skipped: Int, rootLabel: String)
    case failed(String)

    var isIndexing: Bool {
        if case .indexing = self { return true }
        return false
    }
}

struct FilesBrowserView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    /// Pile typée (pas `NavigationPath`) pour pouvoir la cacher entre onglets.
    @State private var path: [FilesDestination] = []
    @State private var roots: [FileRootDTO] = []
    @State private var rootsById: [String: FileRootDTO] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var searchQuery = ""
    @State private var searchHits: [FileSearchHitDTO] = []
    @State private var searching = false
    @State private var pendingDeepLink: FilesDeepLink?
    @State private var indexStatus: FilesIndexStatus = .idle
    @State private var showAssistant = false
    @State private var sheetContext: FilesAssistantContext = .global
    @State private var assistantDetent: PresentationDetent = .large
    @State private var selection = FilesSelectionStore()
    @State private var showDeleteConfirm = false
    @State private var showMovePicker = false
    @State private var mutatingSelection = false
    @State private var selectionError: String?
    @State private var organizerScope: OrganizationScope?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private func openFilesAssistant(_ context: FilesAssistantContext) {
        sheetContext = context
        assistantDetent = .large
        showAssistant = true
    }

    private func openOrganizerFromAssistantContext() {
        showAssistant = false
        switch sheetContext {
        case .folder(let rootId, let path, let title):
            organizerScope = .root(rootId: rootId, relativePath: path, displayName: title)
        case .file(_, let name, let rootId, let path):
            let parent = FilesPathHelpers.parentFolder(of: path)
            let title = parent.isEmpty ? name : FilesPathHelpers.lastSegment(of: parent)
            organizerScope = .root(
                rootId: rootId,
                relativePath: parent,
                displayName: title.isEmpty ? "Dossier" : title
            )
        case .global:
            if let root = roots.first {
                organizerScope = .root(
                    rootId: root.id,
                    relativePath: "",
                    displayName: root.label ?? "Root"
                )
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AmbientBackground()
                VStack(spacing: 0) {
                    filesIndexBanner
                    content
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !selection.isSelecting {
                    ContextualAssistantButton(tint: AppTheme.filesAccent) {
                        openFilesAssistant(.global)
                    }
                }
            }
            .navigationTitle("Files")
            .tabRootNavigationChrome()
            .accessibilityIdentifier(A11yID.Files.root)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selection.isSelecting {
                        Button("OK") { selection.endSelecting() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selection.isSelecting {
                        EmptyView()
                    } else {
                        Menu {
                            Button {
                                selection.beginSelecting()
                                AppHaptics.light()
                            } label: {
                                Label("Sélectionner", systemImage: "checkmark.circle")
                            }
                            Button {
                                Task { await reindexAllRoots() }
                            } label: {
                                Label("Réindexer tous les disques", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(indexStatus.isIndexing || roots.isEmpty)
                            Button {
                                nav.openSettings()
                            } label: {
                                Label("Réglages", systemImage: "person.crop.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Actions Files")
                        .accessibilityIdentifier(A11yID.Files.settings)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .searchable(
                text: $searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Rechercher un fichier"
            )
            .onChange(of: searchQuery) { _, q in
                Task { await runSearch(q) }
            }
            .onChange(of: nav.filesDeepLink) { _, link in
                guard let link else { return }
                if rootsById.isEmpty && roots.isEmpty {
                    pendingDeepLink = link
                } else {
                    if rootsById.isEmpty {
                        rootsById = Dictionary(roots.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                    }
                    applyFilesDeepLink(link)
                }
                nav.filesDeepLink = nil
            }
            .onChange(of: nav.presentFilesAssistant) { _, present in
                guard present else { return }
                openFilesAssistant(nav.filesAssistantContext)
                nav.presentFilesAssistant = false
            }
            .onChange(of: nav.qaIntent) { _, intent in
                guard let intent else { return }
                switch intent {
                case .files:
                    nav.qaIntent = nil
                case .filesDocuments:
                    if let root = roots.first(where: {
                        ($0.label ?? "").localizedCaseInsensitiveContains("document")
                            || ($0.absolutePath ?? "").localizedCaseInsensitiveContains("Documents")
                    }) ?? roots.first {
                        path.append(FilesDestination.folder(rootId: root.id, path: "", title: root.label ?? "Documents"))
                    }
                    nav.qaIntent = nil
                case .filesNested:
                    if let root = roots.first {
                        path.append(FilesDestination.folder(rootId: root.id, path: "", title: root.label ?? "Root"))
                    }
                    nav.qaIntent = nil
                case .filesFile:
                    nav.qaIntent = nil
                case .filesAssistant:
                    openFilesAssistant(.global)
                    nav.qaIntent = nil
                default:
                    break
                }
            }
            .refreshable { await loadRoots() }
            .task {
                if roots.isEmpty, let cached = TabMemoryCache.fileRoots, !cached.isEmpty {
                    roots = cached
                    rootsById = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                }
                if roots.isEmpty {
                    await loadRoots()
                }
                // Restaure l’emplacement (dossier ouvert) après un remount TabView Mail ↔ Files.
                if path.isEmpty, let saved = TabMemoryCache.filesPath, !saved.isEmpty {
                    path = saved
                }
                // Deep-link posé avant l’apparition de l’onglet (ex. « Ouvrir le dossier » depuis Mail).
                consumePendingFilesDeepLink()
            }
            .onChange(of: path) { _, newPath in
                TabMemoryCache.filesPath = newPath
            }
            .onChange(of: roots) { _, newRoots in
                rootsById = Dictionary(newRoots.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                if !newRoots.isEmpty {
                    TabMemoryCache.fileRoots = newRoots
                }
                consumePendingFilesDeepLink()
            }
            .navigationDestination(for: FilesDestination.self) { dest in
                destinationView(dest)
                    // NavigationDestination ne hérite pas toujours de l’environment du root —
                    // sans ça `@Environment(FilesSelectionStore.self)` crash à l’ouverture d’un disque.
                    .environment(selection)
            }
            .sheet(isPresented: $showAssistant) {
                ContextualAssistantSheet(
                    scope: .files,
                    title: sheetContext.sheetTitle,
                    contextLabel: sheetContext.label,
                    contextRef: sheetContext.ref,
                    persistenceKey: sheetContext.persistenceKey,
                    onRequestOrganize: openOrganizerFromAssistantContext
                )
                .environmentObject(session)
                .environment(nav)
                .presentationDetents([.medium, .large], selection: $assistantDetent)
                .presentationDragIndicator(.visible)
                .onAppear { assistantDetent = .large }
            }
            .sheet(item: $organizerScope) { scope in
                SmartOrganizerSheet(
                    scope: scope,
                    onFinished: {
                        selection.bumpContent()
                    }
                )
                .environmentObject(session)
            }
            .onReceive(NotificationCenter.default.publisher(for: .smartOrganizerRequest)) { note in
                guard let rootId = note.userInfo?[SmartOrganizerRequestKeys.rootId] as? String,
                      !rootId.isEmpty
                else { return }
                let folderPath = (note.userInfo?[SmartOrganizerRequestKeys.path] as? String) ?? ""
                let title = (note.userInfo?[SmartOrganizerRequestKeys.title] as? String) ?? "Dossier"
                showAssistant = false
                organizerScope = .root(rootId: rootId, relativePath: folderPath, displayName: title)
            }
            .onChange(of: showAssistant) { _, presented in
                if presented { assistantDetent = .large }
            }
            .onChange(of: nav.assistantDismissToken) { _, _ in
                showAssistant = false
            }
        }
        // Barre + alertes sur le NavigationStack (pas le root) pour rester visibles
        // dans les dossiers poussés (Documents, etc.).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selection.isSelecting {
                FilesMultiSelectBar(
                    count: selection.count,
                    busy: mutatingSelection,
                    onMove: { showMovePicker = true },
                    onMail: {
                        let files = selection.items.map { (fileId: $0.fileId, filename: $0.filename) }
                        guard !files.isEmpty else { return }
                        selection.endSelecting()
                        nav.shareFilesToMail(files: files)
                        AppHaptics.light()
                    },
                    onDelete: { showDeleteConfirm = true },
                    onClear: { selection.clear() }
                )
            }
        }
        .sheet(isPresented: $showMovePicker) {
            FilesMovePickerSheet(
                itemCount: selection.count,
                previewNames: selection.items.map(\.filename),
                onCancel: { showMovePicker = false },
                onPick: { dest in
                    showMovePicker = false
                    Task { await moveSelectedFiles(to: dest) }
                }
            )
            .environmentObject(session)
        }
        .alert(
            selection.count <= 1 ? "Supprimer le fichier ?" : "Supprimer \(selection.count) fichiers ?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                Task { await deleteSelectedFiles() }
            }
        } message: {
            Text("Cette action est définitive. Une confirmation serveur est demandée pour chaque fichier.")
        }
        .alert("Files", isPresented: Binding(
            get: { selectionError != nil },
            set: { if !$0 { selectionError = nil } }
        )) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: {
            Text(selectionError ?? "")
        }
        .environment(selection)
    }

    private func deleteSelectedFiles() async {
        let targets = selection.items
        guard !targets.isEmpty else { return }
        mutatingSelection = true
        defer { mutatingSelection = false }
        var failed: [String] = []
        var deletedIds = Set<String>()
        for item in targets {
            do {
                let proposal = try await client.proposeDeleteFile(sourceFileId: item.fileId)
                try await client.confirmFilesAction(
                    actionId: proposal.actionId,
                    confirmationToken: proposal.confirmationToken,
                    confirm: true
                )
                deletedIds.insert(item.fileId)
            } catch {
                failed.append(item.filename)
            }
        }
        selection.remove(fileIds: deletedIds)
        selection.bumpContent(removedFileIds: deletedIds)
        if failed.isEmpty {
            AppHaptics.success()
            if selection.isEmpty { selection.endSelecting() }
        } else {
            AppHaptics.warning()
            selectionError = "Échec pour : \(failed.joined(separator: ", "))"
        }
    }

    private func moveSelectedFiles(to dest: FilesSaveDestination) async {
        let targets = selection.items
        guard !targets.isEmpty else { return }
        mutatingSelection = true
        defer { mutatingSelection = false }
        let destDir = dest.path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var failed: [String] = []
        var movedIds = Set<String>()
        for item in targets {
            let basename = (item.filename as NSString).lastPathComponent
            let destRel = destDir.isEmpty ? basename : "\(destDir)/\(basename)"
            let sourceParent = (item.relativePath as NSString).deletingLastPathComponent
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if item.rootId == dest.rootId && sourceParent == destDir {
                movedIds.insert(item.fileId)
                continue
            }
            do {
                let proposal = try await client.proposeMoveFile(
                    sourceFileId: item.fileId,
                    destRootId: dest.rootId,
                    destRelativePath: destRel
                )
                try await client.confirmFilesAction(
                    actionId: proposal.actionId,
                    confirmationToken: proposal.confirmationToken,
                    confirm: true
                )
                movedIds.insert(item.fileId)
            } catch {
                failed.append(item.filename)
            }
        }
        selection.remove(fileIds: movedIds)
        selection.bumpContent(removedFileIds: movedIds)
        if failed.isEmpty {
            AppHaptics.success()
            if selection.isEmpty { selection.endSelecting() }
        } else {
            AppHaptics.warning()
            selectionError = "Échec pour : \(failed.joined(separator: ", "))"
        }
    }

    /// Applique un deep-link en attente (state local ou `nav.filesDeepLink`).
    private func consumePendingFilesDeepLink() {
        if let pending = pendingDeepLink {
            pendingDeepLink = nil
            applyFilesDeepLink(pending)
            return
        }
        if let link = nav.filesDeepLink {
            nav.filesDeepLink = nil
            applyFilesDeepLink(link)
        }
    }

    /// Navigation exacte : preview fichier, dossier parent, ou recherche.
    private func applyFilesDeepLink(_ link: FilesDeepLink) {
        switch link.intent {
        case .search:
            if let q = link.query, !q.isEmpty {
                searchQuery = q
                Task { await runSearch(q) }
            }
            if let rootId = link.rootId, rootsById[rootId] != nil {
                path = [
                    FilesDestination.folder(
                        rootId: rootId,
                        path: "",
                        title: rootsById[rootId]?.label ?? "Root"
                    )
                ]
            }
        case .folder:
            navigateToFolder(rootId: link.rootId, folderPath: link.folderPath ?? "")
        case .preview, .download:
            let folder = link.folderPath ?? ""
            navigateToFolder(rootId: link.rootId, folderPath: folder)
            if let fileId = link.fileId, !fileId.isEmpty {
                let title = link.fileName ?? "Fichier"
                let rootId = link.rootId
                    ?? roots.first?.id
                    ?? ""
                path.append(
                    FilesDestination.file(
                        fileId: fileId,
                        title: title,
                        rootId: rootId,
                        folderPath: folder
                    )
                )
            }
        }
    }

    /// Dossier parent d’un `relativePath` fichier/dossier ("" = racine).
    private static func parentFolderPath(of relativePath: String) -> String {
        let normalized = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let slash = normalized.lastIndex(of: "/") else { return "" }
        return String(normalized[..<slash])
    }

    private func navigateToFolder(rootId: String?, folderPath: String) {
        let resolvedRootId = rootId ?? roots.first?.id
        guard let resolvedRootId,
              let root = rootsById[resolvedRootId] ?? roots.first(where: { $0.id == resolvedRootId }) ?? roots.first
        else { return }
        let rootKey = root.id
        // Une seule assignation de path (évite crash SwiftUI sur appends enchaînés).
        var next: [FilesDestination] = [
            FilesDestination.folder(
                rootId: rootKey,
                path: "",
                title: root.label ?? "Root"
            )
        ]
        let normalized = folderPath.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normalized.isEmpty {
            var cumulative = ""
            for segment in normalized.split(separator: "/") {
                cumulative = cumulative.isEmpty ? String(segment) : "\(cumulative)/\(segment)"
                next.append(
                    FilesDestination.folder(
                        rootId: rootKey,
                        path: cumulative,
                        title: String(segment)
                    )
                )
            }
        }
        path = next
    }

    @ViewBuilder
    private func destinationView(_ dest: FilesDestination) -> some View {
        switch dest {
        case .folder(let rootId, let folderPath, let title):
            if let root = rootsById[rootId] {
                FileFolderView(
                    root: root,
                    path: folderPath,
                    title: title,
                    selection: selection,
                    onOpenFolder: { entry in
                        path.append(
                            FilesDestination.folder(
                                rootId: root.id,
                                path: entry.relativePath,
                                title: entry.name ?? entry.relativePath
                            )
                        )
                    },
                    onOpenFile: { entry in
                        guard let fileId = entry.fileId, !fileId.isEmpty else { return }
                        path.append(
                            FilesDestination.file(
                                fileId: fileId,
                                title: entry.name ?? entry.relativePath,
                                rootId: root.id,
                                folderPath: folderPath
                            )
                        )
                    },
                    onRevealDestination: { entry in
                        let parent = Self.parentFolderPath(of: entry.relativePath)
                        navigateToFolder(rootId: root.id, folderPath: parent)
                    },
                    onReindex: {
                        Task { await reindexRoot(root) }
                    },
                    isReindexing: indexStatus.isIndexing
                )
            } else {
                SoftEmptyState(
                    systemImage: "externaldrive.badge.xmark",
                    title: "Racine introuvable",
                    message: "Cette racine n’est plus disponible."
                )
            }
        case .file(let fileId, let title, _, _):
            FilePreviewView(
                fileId: fileId,
                title: title
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            searchResults
        } else if loading && roots.isEmpty {
            SoftLoadingBlock(label: "Chargement des disques…")
        } else if let error, roots.isEmpty {
            SoftEmptyState(
                systemImage: "folder.badge.questionmark",
                title: "Impossible de charger",
                message: error,
                actionTitle: "Réessayer"
            ) { Task { await loadRoots() } }
        } else if roots.filter({ $0.enabled != false }).isEmpty {
            SoftEmptyState(
                systemImage: "externaldrive",
                title: "Aucun disque",
                message: "Aucune racine fichiers n’est configurée sur le serveur."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(roots.filter { $0.enabled != false }) { root in
                        NavigationLink(
                            value: FilesDestination.folder(
                                rootId: root.id,
                                path: "",
                                title: root.label ?? "Root"
                            )
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(root.label?.isEmpty == false ? root.label! : "Racine")
                                        .foregroundStyle(AppTheme.foreground)
                                    if let path = root.absolutePath {
                                        Text(path)
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.mutedForeground)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.mutedForeground)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)
                        .accessibilityIdentifier(A11yID.Files.folder)
                        .contextMenu {
                            Button {
                                Task { await reindexRoot(root) }
                            } label: {
                                Label("Réindexer", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(indexStatus.isIndexing)
                        }
                        Divider().overlay(AppTheme.borderSubtle).padding(.leading, 54)
                    }
                }
                .padding(.bottom, AppTheme.space24)
            }
        }
    }

    @ViewBuilder
    private var filesIndexBanner: some View {
        switch indexStatus {
        case .idle:
            EmptyView()
        case .indexing(let label):
            HStack(spacing: AppTheme.space8) {
                ProgressView()
                    .controlSize(.small)
                Text("Indexation de « \(label) »…")
                    .font(CNFont.caption.weight(.medium))
                    .foregroundStyle(AppTheme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.space16)
            .padding(.vertical, AppTheme.space8)
            .background(AppTheme.surfaceElevated.opacity(0.95))
            .accessibilityIdentifier(A11yID.Files.reindex)
        case .done(let indexed, let skipped, let label):
            HStack(spacing: AppTheme.space8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                Text("« \(label) » · \(indexed) indexés, \(skipped) ignorés")
                    .font(CNFont.caption.weight(.medium))
                    .foregroundStyle(AppTheme.foreground)
                Spacer(minLength: 0)
                Button("OK") { indexStatus = .idle }
                    .font(CNFont.caption.weight(.semibold))
            }
            .padding(.horizontal, AppTheme.space16)
            .padding(.vertical, AppTheme.space8)
            .background(AppTheme.surfaceElevated.opacity(0.95))
        case .failed(let message):
            HStack(spacing: AppTheme.space8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.danger)
                Text(message)
                    .font(CNFont.caption.weight(.medium))
                    .foregroundStyle(AppTheme.foreground)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("OK") { indexStatus = .idle }
                    .font(CNFont.caption.weight(.semibold))
            }
            .padding(.horizontal, AppTheme.space16)
            .padding(.vertical, AppTheme.space8)
            .background(AppTheme.surfaceElevated.opacity(0.95))
        }
    }

    private func reindexRoot(_ root: FileRootDTO) async {
        let label = root.label?.isEmpty == false ? root.label! : "Racine"
        indexStatus = .indexing(rootLabel: label)
        do {
            let result = try await client.indexFileRoot(rootId: root.id)
            indexStatus = .done(
                indexed: result.indexed ?? 0,
                skipped: result.skipped ?? 0,
                rootLabel: label
            )
            AppHaptics.success()
        } catch {
            indexStatus = .failed(error.localizedDescription)
            AppHaptics.error()
        }
    }

    private func reindexAllRoots() async {
        let enabled = roots.filter { $0.enabled != false }
        guard !enabled.isEmpty else { return }
        for root in enabled {
            await reindexRoot(root)
            if case .failed = indexStatus { break }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if searching && searchHits.isEmpty {
            ProgressView().tint(AppTheme.accent)
        } else if searchHits.isEmpty {
            Text("Aucun résultat")
                .foregroundStyle(AppTheme.muted)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(searchHits) { hit in
                        Button {
                            path.append(
                                FilesDestination.file(
                                    fileId: hit.fileId,
                                    title: hit.name ?? hit.filename ?? hit.relativePath ?? "Fichier",
                                    rootId: hit.rootId ?? "",
                                    folderPath: hit.relativePath ?? ""
                                )
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.name ?? hit.filename ?? "Fichier")
                                    .foregroundStyle(AppTheme.foreground)
                                if let path = hit.relativePath {
                                    Text(path)
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.mutedForeground)
                                        .lineLimit(1)
                                }
                                if let snippet = hit.snippet, !snippet.isEmpty {
                                    Text(snippet)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(AppTheme.borderSubtle).padding(.leading, 14)
                    }
                }
                .padding(.bottom, AppTheme.space24)
            }
        }
    }

    private func loadRoots() async {
        loading = true
        defer { loading = false }
        do {
            roots = try await client.listFileRoots()
            rootsById = Dictionary(roots.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            error = nil
            consumePendingFilesDeepLink()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runSearch(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchHits = []
            return
        }
        searching = true
        defer { searching = false }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            searchHits = try await client.searchFiles(query: trimmed, mode: "all")
        } catch {
            searchHits = []
        }
    }
}

struct FileFolderView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    let root: FileRootDTO
    let path: String
    let title: String
    @Bindable var selection: FilesSelectionStore
    var onOpenFolder: (FileEntryDTO) -> Void
    var onOpenFile: (FileEntryDTO) -> Void
    var onRevealDestination: (FileEntryDTO) -> Void = { _ in }
    var onReindex: (() -> Void)? = nil
    var isReindexing: Bool = false

    @State private var entries: [FileEntryDTO] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var nextCursor: String?
    @State private var error: String?
    @State private var openError: String?
    @AppStorage("files.viewMode") private var viewModeRaw: String = FilesViewMode.list.rawValue
    @AppStorage("files.sortMode") private var sortModeRaw: String = FilesSortMode.name.rawValue
    @State private var typeFilter: FilesTypeFilter = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var downloadingFileId: String?

    private var sortMode: FilesSortMode {
        FilesSortMode(rawValue: sortModeRaw) ?? .name
    }

    private var sortModeBinding: Binding<FilesSortMode> {
        Binding(
            get: { FilesSortMode(rawValue: sortModeRaw) ?? .name },
            set: { next in
                guard next.rawValue != sortModeRaw else { return }
                sortModeRaw = next.rawValue
                AppHaptics.selection()
            }
        )
    }

    private var viewModeBinding: Binding<FilesViewMode> {
        Binding(
            get: { FilesViewMode(rawValue: viewModeRaw) ?? .list },
            set: { next in
                guard next.rawValue != viewModeRaw else { return }
                viewModeRaw = next.rawValue
                AppHaptics.selection()
            }
        )
    }

    private var viewMode: FilesViewMode {
        FilesViewMode(rawValue: viewModeRaw) ?? .list
    }
    @State private var showMkdir = false
    @State private var mkdirName = ""
    @State private var mkdirConfirm: FilesProposeResult?
    @State private var renameTarget: FileEntryDTO?
    @State private var renameText = ""
    @State private var deleteTarget: FileEntryDTO?
    @State private var deletingSingle = false
    @State private var showImporter = false
    @State private var pendingPropose: FilesProposeResult?
    @State private var confirming = false
    @State private var uploading = false
    @State private var showAssistant = false
    @State private var assistantDetent: PresentationDetent = .large
    @State private var showOrganizer = false

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var folderAssistantContext: FilesAssistantContext {
        .folder(rootId: root.id, path: path, title: title)
    }

    private var breadcrumb: String {
        path.isEmpty ? (root.label ?? "Root") : "\(root.label ?? "Root") / \(path.replacingOccurrences(of: "/", with: " / "))"
    }

    /// Filtre + tri unique (Liste / Grille / Détails).
    private var displayedEntries: [FileEntryDTO] {
        let filtered = entries.filter { entry in
            switch typeFilter {
            case .all: return true
            case .folders: return entry.isDirectory == true
            case .indexed: return entry.indexed == true && entry.isDirectory != true
            case .images:
                guard entry.isDirectory != true else { return false }
                let n = (entry.name ?? "").lowercased()
                return n.hasSuffix(".png") || n.hasSuffix(".jpg") || n.hasSuffix(".jpeg") || n.hasSuffix(".webp") || n.hasSuffix(".gif")
            case .pdf:
                return entry.isDirectory != true && (entry.name ?? "").lowercased().hasSuffix(".pdf")
            case .documents:
                guard entry.isDirectory != true else { return false }
                let n = (entry.name ?? "").lowercased()
                return [".txt", ".md", ".docx", ".doc", ".csv", ".json", ".pdf"].contains { n.hasSuffix($0) }
            }
        }
        return Self.sorted(filtered, by: sortMode)
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            Group {
                if loading && entries.isEmpty {
                    SoftLoadingBlock(label: "Chargement…")
                } else if let error, entries.isEmpty {
                    SoftEmptyState(
                        systemImage: "exclamationmark.triangle",
                        title: "Erreur",
                        message: error,
                        actionTitle: "Réessayer"
                    ) { Task { await load(reset: true) } }
                } else if displayedEntries.isEmpty {
                    SoftEmptyState(
                        systemImage: "folder",
                        title: "Dossier vide",
                        message: typeFilter == .all
                            ? "Aucun élément ici. Tu peux créer un dossier ou importer."
                            : "Aucun résultat pour ce filtre.",
                        actionTitle: "Nouveau dossier"
                    ) { showMkdir = true }
                } else if viewMode == .grid {
                    grid
                } else if viewMode == .details {
                    details
                } else {
                    list
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: viewModeRaw)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: sortModeRaw)
        }
        .overlay(alignment: .bottomTrailing) {
            if !selection.isSelecting {
                ContextualAssistantButton(tint: AppTheme.filesAccent) {
                    assistantDetent = .large
                    showAssistant = true
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
                .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(title).font(.headline)
                    Text(breadcrumb)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !selection.isSelecting {
                    Menu {
                        Picker("Vue", selection: viewModeBinding) {
                            ForEach(FilesViewMode.allCases) { mode in
                                Label(mode.label, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: viewMode.systemImage)
                    }
                    .accessibilityLabel("Mode d'affichage")
                    .accessibilityValue(viewMode.label)

                    Menu {
                        Picker("Trier", selection: sortModeBinding) {
                            ForEach(FilesSortMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Trier")
                    .accessibilityValue(sortMode.label)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if selection.isSelecting {
                    Button("OK") { selection.endSelecting() }
                } else {
                    Menu {
                        Button {
                            selection.beginSelecting()
                            AppHaptics.light()
                        } label: {
                            Label("Sélectionner", systemImage: "checkmark.circle")
                        }
                        if let onReindex {
                            Button {
                                onReindex()
                            } label: {
                                Label("Réindexer ce disque", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(isReindexing)
                            .accessibilityIdentifier(A11yID.Files.reindex)
                            Divider()
                        }
                        Button { showMkdir = true } label: { Label("Nouveau dossier", systemImage: "folder.badge.plus") }
                        Button { showImporter = true } label: { Label("Importer un fichier", systemImage: "square.and.arrow.down") }
                            .disabled(uploading)
                        Button {
                            showOrganizer = true
                            AppHaptics.light()
                        } label: {
                            Label("Réorganiser", systemImage: "folder.badge.gearshape")
                        }
                        Divider()
                        Picker("Vue", selection: viewModeBinding) {
                            ForEach(FilesViewMode.allCases) { mode in
                                Label(mode.label, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                        Picker("Trier", selection: sortModeBinding) {
                            ForEach(FilesSortMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        Divider()
                        Picker("Filtrer", selection: $typeFilter) {
                            ForEach(FilesTypeFilter.allCases) { f in Text(f.label).tag(f) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Options du dossier")
                }
            }
        }
        .sheet(isPresented: $showAssistant) {
            ContextualAssistantSheet(
                scope: .files,
                title: folderAssistantContext.sheetTitle,
                contextLabel: folderAssistantContext.label,
                contextRef: folderAssistantContext.ref,
                persistenceKey: folderAssistantContext.persistenceKey,
                onRequestOrganize: {
                    showAssistant = false
                    showOrganizer = true
                }
            )
            .environmentObject(session)
            .environment(nav)
            .presentationDetents([.medium, .large], selection: $assistantDetent)
            .presentationDragIndicator(.visible)
            .onAppear { assistantDetent = .large }
        }
        .sheet(isPresented: $showOrganizer) {
            SmartOrganizerSheet(
                scope: .root(rootId: root.id, relativePath: path, displayName: title),
                onFinished: { await load(reset: true) }
            )
            .environmentObject(session)
        }
        .alert("Nouveau dossier", isPresented: $showMkdir) {
            TextField("Nom", text: $mkdirName)
            Button("Annuler", role: .cancel) { mkdirName = "" }
            Button("Créer") { Task { await createDirectory() } }
        } message: {
            Text("Le dossier sera créé sous « \(title) » après confirmation.")
        }
        .sheet(item: $mkdirConfirm) { proposal in
            MkdirConfirmSheet(
                detail: proposal.detail,
                confirming: confirming,
                onConfirm: { Task { await resolveMkdir(proposal, confirm: true) } },
                onCancel: { Task { await resolveMkdir(proposal, confirm: false) } }
            )
        }
        .alert("Renommer", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Nouveau nom", text: $renameText)
            Button("Annuler", role: .cancel) { renameTarget = nil }
            Button("Proposer") { Task { await renameEntry() } }
        }
        .alert(
            "Supprimer le fichier ?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) { deleteTarget = nil }
            Button("Supprimer", role: .destructive) {
                guard let target = deleteTarget else { return }
                Task { await deleteSingleFile(target) }
            }
        } message: {
            if let name = deleteTarget?.name ?? deleteTarget?.relativePath {
                Text("« \(name) » sera définitivement supprimé.")
            } else {
                Text("Ce fichier sera définitivement supprimé.")
            }
        }
        .alert("Confirmer l’action ?", isPresented: Binding(
            get: { pendingPropose != nil && mkdirConfirm == nil },
            set: { if !$0 && !confirming { pendingPropose = nil } }
        )) {
            Button("Annuler", role: .cancel) { Task { await resolvePropose(confirm: false) } }
            Button("Confirmer") { Task { await resolvePropose(confirm: true) } }
        } message: {
            if let pendingPropose {
                Text("\(pendingPropose.op) · \(pendingPropose.detail)")
            }
        }
        .alert("Fichier", isPresented: Binding(
            get: { openError != nil },
            set: { if !$0 { openError = nil } }
        )) {
            Button("OK", role: .cancel) { openError = nil }
        } message: {
            Text(openError ?? "")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item, .image, .pdf, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
        .onChange(of: nav.assistantDismissToken) { _, _ in
            showAssistant = false
        }
        .onChange(of: selection.contentEpoch) { _, _ in
            applyRemovedFileIds(selection.lastRemovedFileIds)
        }
        .task {
            // Même logique que les roots : restaurer le cache process avant tout réseau
            // (évite le flash « Chargement… » au retour Mail → Files).
            if entries.isEmpty,
               let snap = TabMemoryCache.folder(rootId: root.id, path: path),
               !snap.entries.isEmpty
            {
                entries = snap.entries
                nextCursor = snap.nextCursor
                loading = false
                return
            }
            if entries.isEmpty {
                await load(reset: true)
            } else {
                loading = false
            }
        }
    }

    private func isFolder(_ entry: FileEntryDTO) -> Bool { entry.isDirectory == true }

    private func selectedItem(for entry: FileEntryDTO) -> FilesSelectedItem? {
        guard let fileId = entry.fileId, !isFolder(entry) else { return nil }
        return FilesSelectedItem(
            fileId: fileId,
            filename: entry.name ?? entry.relativePath,
            rootId: root.id,
            relativePath: entry.relativePath
        )
    }

    @ViewBuilder
    private func entryContextMenu(_ entry: FileEntryDTO) -> some View {
        if let fileId = entry.fileId, !isFolder(entry) {
            Button {
                if !selection.isSelecting { selection.beginSelecting() }
                if let item = selectedItem(for: entry) { selection.select(item) }
            } label: {
                Label("Sélectionner", systemImage: "checkmark.circle")
            }
            Button {
                nav.shareFilesToMail(
                    files: [(fileId: fileId, filename: entry.name ?? entry.relativePath)]
                )
            } label: {
                Label("Envoyer par mail", systemImage: "envelope.badge")
            }
            Button {
                renameTarget = entry
                renameText = entry.name ?? ""
            } label: {
                Label("Renommer", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                deleteTarget = entry
                AppHaptics.light()
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .disabled(deletingSingle)
        } else if isFolder(entry) {
            Button {
                renameTarget = entry
                renameText = entry.name ?? ""
            } label: {
                Label("Renommer", systemImage: "pencil")
            }
            Divider()
            Button {
                OrganizationProtectionStore.shared.protect(
                    rootId: root.id,
                    path: entry.relativePath,
                    always: false
                )
                AppHaptics.light()
            } label: {
                Label("Protéger ce dossier", systemImage: "lock")
            }
            Button {
                OrganizationProtectionStore.shared.protect(
                    rootId: root.id,
                    path: entry.relativePath,
                    always: true
                )
                AppHaptics.success()
            } label: {
                Label("Toujours protéger", systemImage: "lock.shield")
            }
        } else if entry.fileId != nil {
            Button {
                renameTarget = entry
                renameText = entry.name ?? ""
            } label: {
                Label("Renommer", systemImage: "pencil")
            }
        }
    }

    private func handleEntryTap(_ entry: FileEntryDTO) {
        if selection.isSelecting {
            if let item = selectedItem(for: entry) {
                selection.toggle(item)
                AppHaptics.light()
            } else if isFolder(entry) {
                onOpenFolder(entry)
            }
            return
        }
        if isFolder(entry) { onOpenFolder(entry) } else { onOpenFile(entry) }
    }

    private var list: some View {
        List {
            ForEach(displayedEntries) { entry in
                Button {
                    handleEntryTap(entry)
                } label: {
                    HStack(spacing: 10) {
                        if selection.isSelecting, !isFolder(entry) {
                            Image(systemName: selection.contains(entry.fileId ?? "") ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    selection.contains(entry.fileId ?? "") ? AppTheme.accent : AppTheme.muted
                                )
                                .font(.title3)
                        }
                        fileRow(entry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .listRowBackground(
                    selection.contains(entry.fileId ?? "")
                        ? AppTheme.accent.opacity(0.12)
                        : AppTheme.surface.opacity(0.35)
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                .contextMenu { entryContextMenu(entry) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if entry.fileId != nil, !isFolder(entry) {
                        Button(role: .destructive) {
                            deleteTarget = entry
                            AppHaptics.light()
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
                .onAppear {
                    if entry.id == displayedEntries.last?.id {
                        Task { await loadMoreIfNeeded() }
                    }
                }
            }
            if loadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(displayedEntries) { entry in
                    Button {
                        handleEntryTap(entry)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: 6) {
                                FilesEntryThumbnail(
                                    entry: entry,
                                    baseURL: session.baseURL,
                                    token: session.token
                                )
                                .frame(height: 72)
                                .frame(maxWidth: .infinity)
                                .background(AppTheme.surfaceElevated.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))

                                Text(entry.name ?? entry.relativePath)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(AppTheme.foreground)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)

                                if !isFolder(entry), let size = entry.sizeBytes, size > 0 {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.mutedForeground)
                                        .lineLimit(1)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(
                                selection.contains(entry.fileId ?? "")
                                    ? AppTheme.accent.opacity(0.14)
                                    : AppTheme.surface.opacity(0.85)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                                    .stroke(
                                        selection.contains(entry.fileId ?? "")
                                            ? AppTheme.accent.opacity(0.45)
                                            : AppTheme.borderSubtle.opacity(0.6),
                                        lineWidth: 0.5
                                    )
                            )

                            if selection.isSelecting, !isFolder(entry) {
                                Image(systemName: selection.contains(entry.fileId ?? "") ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(
                                        selection.contains(entry.fileId ?? "") ? AppTheme.accent : AppTheme.muted
                                    )
                                    .padding(6)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .contextMenu { entryContextMenu(entry) }
                    .onAppear {
                        if entry.id == displayedEntries.last?.id {
                            Task { await loadMoreIfNeeded() }
                        }
                    }
                }
            }
            .padding(14)
            .padding(.bottom, AppTheme.space24)
        }
    }

    private var details: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(displayedEntries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            handleEntryTap(entry)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                FilesEntryThumbnail(
                                    entry: entry,
                                    baseURL: session.baseURL,
                                    token: session.token,
                                    iconSize: 28
                                )
                                .frame(width: 52, height: 52)
                                .background(AppTheme.surfaceElevated.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name ?? entry.relativePath)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.foreground)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(detailTypeLabel(for: entry))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppTheme.accent)
                                    ForEach(detailMetaLines(for: entry), id: \.self) { line in
                                        Text(line)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.mutedForeground)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if selection.isSelecting, !isFolder(entry) {
                                    Image(systemName: selection.contains(entry.fileId ?? "") ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(
                                            selection.contains(entry.fileId ?? "") ? AppTheme.accent : AppTheme.muted
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !selection.isSelecting {
                            HStack(spacing: 8) {
                                Button {
                                    handleEntryTap(entry)
                                    AppHaptics.light()
                                } label: {
                                    Text("Ouvrir")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accent)
                                .controlSize(.small)

                                if !isFolder(entry), entry.fileId != nil {
                                    Button {
                                        Task { await downloadEntry(entry) }
                                    } label: {
                                        if downloadingFileId == entry.fileId {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Text("Télécharger")
                                                .font(.caption.weight(.semibold))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(downloadingFileId != nil)
                                }

                                Button {
                                    onRevealDestination(entry)
                                    AppHaptics.light()
                                } label: {
                                    Text("Aller à la destination")
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        selection.contains(entry.fileId ?? "")
                            ? AppTheme.accent.opacity(0.12)
                            : AppTheme.surface.opacity(0.9)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                            .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                    .contextMenu { entryContextMenu(entry) }
                    .onAppear {
                        if entry.id == displayedEntries.last?.id {
                            Task { await loadMoreIfNeeded() }
                        }
                    }
                }
                if loadingMore {
                    ProgressView().controlSize(.small).padding()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, AppTheme.space24)
        }
    }

    private func detailTypeLabel(for entry: FileEntryDTO) -> String {
        if isFolder(entry) { return "Dossier" }
        let name = (entry.name ?? "").lowercased()
        if name.hasSuffix(".pdf") { return "PDF" }
        if [".png", ".jpg", ".jpeg", ".webp", ".gif", ".heic"].contains(where: { name.hasSuffix($0) }) { return "Image" }
        if [".txt", ".md"].contains(where: { name.hasSuffix($0) }) { return "Texte" }
        if let ext = name.split(separator: ".").last, ext.count <= 5 {
            return String(ext).uppercased()
        }
        return "Fichier"
    }

    private func detailMetaLines(for entry: FileEntryDTO) -> [String] {
        var lines: [String] = []
        if !isFolder(entry), let size = entry.sizeBytes, size > 0 {
            lines.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        let folder = path.isEmpty ? (root.label ?? "Documents") : path
        if !folder.isEmpty { lines.append(folder) }
        if let when = formatMtime(entry.mtimeMs, style: .details) {
            lines.append(when)
        }
        if entry.indexed == true { lines.append("Indexé") }
        return lines
    }

    private enum MtimeStyle { case list, details }

    private func formatMtime(_ ms: Int?, style: MtimeStyle = .list) -> String? {
        guard let ms, ms > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let cal = Calendar.current
        switch style {
        case .list:
            if cal.isDateInToday(date) { return "Modifié aujourd’hui" }
            if cal.isDateInYesterday(date) { return "Modifié hier" }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            return "Modifié le " + fmt.string(from: date)
        case .details:
            if cal.isDateInToday(date) { return "Modifié aujourd’hui" }
            if cal.isDateInYesterday(date) { return "Modifié hier" }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateStyle = .long
            fmt.timeStyle = .none
            return "Modifié le " + fmt.string(from: date)
        }
    }

    private func secondaryListLine(for entry: FileEntryDTO) -> String {
        if isFolder(entry) {
            if let when = formatMtime(entry.mtimeMs) {
                return "Dossier · " + when
            }
            return "Dossier"
        }
        var parts: [String] = [detailTypeLabel(for: entry)]
        if let size = entry.sizeBytes, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if let when = formatMtime(entry.mtimeMs) {
            parts.append(when)
        }
        return parts.joined(separator: " · ")
    }

    private func downloadEntry(_ entry: FileEntryDTO) async {
        guard let fileId = entry.fileId, !isFolder(entry) else { return }
        downloadingFileId = fileId
        defer { downloadingFileId = nil }
        do {
            let (data, resolvedName, _) = try await client.downloadFileBytes(fileId: fileId)
            let name = resolvedName.isEmpty ? (entry.name ?? "fichier") : resolvedName
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("files-dl", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(name)
            try data.write(to: dest, options: .atomic)
            await MainActor.run {
                NativeShare.present(url: dest, title: name)
                AppHaptics.success()
            }
        } catch {
            openError = error.localizedDescription
            AppHaptics.error()
        }
    }

    private func fileRow(_ entry: FileEntryDTO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isFolder(entry) ? "folder.fill" : iconName(for: entry.name ?? ""))
                .foregroundStyle(isFolder(entry) ? AppTheme.accent : AppTheme.muted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? entry.relativePath)
                    .foregroundStyle(AppTheme.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(secondaryListLine(for: entry))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.mutedForeground)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name ?? entry.relativePath), \(isFolder(entry) ? "dossier" : "fichier")")
    }

    private func iconName(for name: String) -> String {
        let n = name.lowercased()
        if n.hasSuffix(".pdf") { return "doc.richtext" }
        if n.hasSuffix(".png") || n.hasSuffix(".jpg") || n.hasSuffix(".jpeg") || n.hasSuffix(".webp") || n.hasSuffix(".heic") || n.hasSuffix(".gif") {
            return "photo"
        }
        if n.hasSuffix(".md") || n.hasSuffix(".txt") { return "doc.plaintext" }
        if n.hasSuffix(".json") || n.hasSuffix(".csv") { return "tablecells" }
        return "doc.fill"
    }

    private func applyRemovedFileIds(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let before = entries.count
        entries.removeAll { entry in
            guard let id = entry.fileId else { return false }
            return ids.contains(id)
        }
        guard entries.count != before else { return }
        TabMemoryCache.saveFolder(
            rootId: root.id,
            path: path,
            entries: entries,
            nextCursor: nextCursor
        )
    }

    private func load(reset: Bool) async {
        if reset {
            loading = true
            nextCursor = nil
            entries = []
        }
        defer { loading = false }
        do {
            let list = try await client.listFiles(rootId: root.id, path: path, cursor: nil)
            entries = Self.sorted(list.entries, by: sortMode)
            let fileCount = entries.filter { !isFolder($0) }.count
            let previews: [WidgetSharedStore.FilePreviewItem] = entries.prefix(6).map { entry in
                let name = entry.name ?? entry.relativePath
                let folder = isFolder(entry)
                return WidgetSharedStore.FilePreviewItem(
                    id: entry.relativePath,
                    name: name,
                    detail: Self.widgetFileDetail(name: name, isDirectory: folder, sizeBytes: entry.sizeBytes),
                    isDirectory: folder
                )
            }
            WidgetSharedStore.publishFilesRecent(
                count: fileCount,
                folderName: title,
                previews: previews
            )
            nextCursor = list.nextCursor
            error = nil
            TabMemoryCache.saveFolder(
                rootId: root.id,
                path: path,
                entries: entries,
                nextCursor: nextCursor
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMoreIfNeeded() async {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let list = try await client.listFiles(rootId: root.id, path: path, cursor: cursor)
            let merged = entries + list.entries
            entries = Self.sorted(merged, by: sortMode)
            nextCursor = list.nextCursor
            TabMemoryCache.saveFolder(
                rootId: root.id,
                path: path,
                entries: entries,
                nextCursor: nextCursor
            )
        } catch {
            // silent — user still has first page
        }
    }

    private static func widgetFileDetail(name: String, isDirectory: Bool, sizeBytes: Int?) -> String {
        if isDirectory { return "Dossier" }
        let ext = (name as NSString).pathExtension.uppercased()
        let typeLabel = ext.isEmpty ? "Fichier" : ext
        guard let sizeBytes, sizeBytes > 0 else { return typeLabel }
        let size = ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        return "\(typeLabel) · \(size)"
    }

    private static func sorted(_ items: [FileEntryDTO], by mode: FilesSortMode = .name) -> [FileEntryDTO] {
        items.sorted { a, b in
            let ad = a.isDirectory == true
            let bd = b.isDirectory == true
            if ad != bd { return ad && !bd }
            switch mode {
            case .name:
                return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
            case .date:
                let am = a.mtimeMs ?? 0
                let bm = b.mtimeMs ?? 0
                if am != bm { return am > bm }
                return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
            case .size:
                let asz = a.sizeBytes ?? 0
                let bsz = b.sizeBytes ?? 0
                if asz != bsz { return asz > bsz }
                return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
            case .type:
                let at = fileExtension(a.name ?? "")
                let bt = fileExtension(b.name ?? "")
                let cmp = at.localizedCaseInsensitiveCompare(bt)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
            }
        }
    }

    private static func fileExtension(_ name: String) -> String {
        let n = name.lowercased()
        guard let dot = n.lastIndex(of: "."), dot < n.endIndex else { return "" }
        return String(n[n.index(after: dot)...])
    }

    private func createDirectory() async {
        let name = mkdirName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mkdirName = ""
        let dest = path.isEmpty ? name : "\(path)/\(name)"
        do {
            let proposal = try await client.proposeCreateDirectory(rootId: root.id, destRelativePath: dest)
            AppHaptics.light()
            // Attendre la fermeture de l’alert « Nouveau dossier » puis sheet de confirmation
            // (évite le bug SwiftUI « second alert ignoré »).
            try? await Task.sleep(nanoseconds: 450_000_000)
            await MainActor.run {
                mkdirConfirm = proposal
            }
        } catch {
            openError = error.localizedDescription
        }
    }

    private func resolveMkdir(_ pending: FilesProposeResult, confirm: Bool) async {
        confirming = true
        defer {
            confirming = false
            mkdirConfirm = nil
        }
        do {
            try await client.confirmFilesAction(
                actionId: pending.actionId,
                confirmationToken: pending.confirmationToken,
                confirm: confirm
            )
            if confirm {
                AppHaptics.success()
                let dest = pending.destRelativePath
                    .replacingOccurrences(of: "\\", with: "/")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !dest.isEmpty {
                    let name = dest.split(separator: "/").last.map(String.init) ?? dest
                    onOpenFolder(
                        FileEntryDTO(
                            fileId: nil,
                            name: name,
                            relativePath: dest,
                            isDirectory: true,
                            sizeBytes: nil,
                            mtimeMs: nil,
                            indexed: nil
                        )
                    )
                } else {
                    await load(reset: true)
                }
            }
        } catch {
            openError = error.localizedDescription
        }
    }

    private func renameEntry() async {
        guard let target = renameTarget, let fileId = target.fileId else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !name.isEmpty else { return }
        do {
            pendingPropose = try await client.proposeRenameFile(sourceFileId: fileId, newName: name)
            AppHaptics.light()
        } catch {
            openError = error.localizedDescription
        }
    }

    private func deleteSingleFile(_ target: FileEntryDTO) async {
        guard let fileId = target.fileId else { return }
        deleteTarget = nil
        deletingSingle = true
        defer { deletingSingle = false }
        do {
            let proposal = try await client.proposeDeleteFile(sourceFileId: fileId)
            try await client.confirmFilesAction(
                actionId: proposal.actionId,
                confirmationToken: proposal.confirmationToken,
                confirm: true
            )
            applyRemovedFileIds([fileId])
            selection.remove(fileIds: [fileId])
            // Pas de bumpContent : la liste est déjà à jour localement (évite un reload).
            AppHaptics.success()
        } catch {
            AppHaptics.warning()
            openError = error.localizedDescription
        }
    }

    private func resolvePropose(confirm: Bool) async {
        guard let pending = pendingPropose else { return }
        confirming = true
        defer { confirming = false; pendingPropose = nil }
        do {
            try await client.confirmFilesAction(
                actionId: pending.actionId,
                confirmationToken: pending.confirmationToken,
                confirm: confirm
            )
            if confirm {
                AppHaptics.success()
                await load(reset: true)
            }
        } catch {
            openError = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            uploading = true
            defer { uploading = false }
            try await client.uploadFiles(
                rootId: root.id,
                destRelativePath: path,
                filename: name,
                data: data,
                mimeType: mime
            )
            AppHaptics.success()
            await load(reset: true)
        } catch {
            openError = error.localizedDescription
        }
    }
}

/// Miniature lazy pour la grille / détails Files (cache ImagePipeline, pas de gros fichiers).
private struct FilesEntryThumbnail: View {
    let entry: FileEntryDTO
    let baseURL: URL
    let token: String?
    var iconSize: CGFloat = 30

    @State private var image: UIImage?
    @State private var loading = false

    private var isFolder: Bool { entry.isDirectory == true }

    private var isVisual: Bool {
        guard !isFolder else { return false }
        let n = (entry.name ?? entry.relativePath).lowercased()
        return [".png", ".jpg", ".jpeg", ".webp", ".gif", ".heic"].contains { n.hasSuffix($0) }
    }

    private var cacheKey: String {
        "files-thumb-\(entry.fileId ?? entry.relativePath)"
    }

    private var systemIcon: String {
        if isFolder { return "folder.fill" }
        let n = (entry.name ?? "").lowercased()
        if n.hasSuffix(".pdf") { return "doc.richtext" }
        if isVisual { return "photo" }
        if n.hasSuffix(".md") || n.hasSuffix(".txt") { return "doc.plaintext" }
        if n.hasSuffix(".json") || n.hasSuffix(".csv") { return "tablecells" }
        return "doc.fill"
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: systemIcon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(isFolder ? AppTheme.accent : AppTheme.muted)
                if loading {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: entry.fileId ?? entry.relativePath) {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard isVisual, let fileId = entry.fileId, !fileId.isEmpty else { return }
        if let size = entry.sizeBytes, size > 12_000_000 { return }
        if let cached = await ImagePipeline.cached(cacheKey) {
            image = cached
            return
        }
        loading = true
        defer { loading = false }
        do {
            let client = APIClient(baseURL: baseURL, token: token)
            let dto = try await client.fetchFileContent(fileId: fileId)
            guard dto.kind == "image", let data = dto.binary,
                  let thumb = ImagePipeline.thumbnail(data: data, maxPixelSize: 220)
            else { return }
            await ImagePipeline.store(thumb, key: cacheKey)
            image = thumb
        } catch {
            // Placeholder icône déjà affiché.
        }
    }
}

struct FilePreviewView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    let fileId: String
    let title: String

    @State private var content: FileContentDTO?
    @State private var image: UIImage?
    @State private var loading = true
    @State private var error: String?
    @State private var pdfURL: URL?
    @State private var shareURL: URL?

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            Group {
                if loading {
                    SoftLoadingBlock(label: "Chargement…")
                } else if let error {
                    SoftErrorBanner(message: error) {
                        Task { await load() }
                    }
                    .padding()
                } else if let image {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                } else if let text = content?.text {
                    ScrollView {
                        Text(text)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(AppTheme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .textSelection(.enabled)
                    }
                    .background(AppTheme.codeBg.opacity(0.55))
                    if content?.truncated == true {
                        Text("Aperçu tronqué")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.muted)
                            .padding(.bottom, 8)
                    }
                } else if let pdfURL {
                    QuickLookPreview(url: pdfURL)
                        .ignoresSafeArea(edges: .bottom)
                } else if content?.kind == "pdf" {
                    SoftEmptyState(
                        systemImage: "doc.richtext",
                        title: "PDF",
                        message: "Impossible de préparer l’aperçu Quick Look."
                    )
                } else {
                    SoftEmptyState(
                        systemImage: "doc",
                        title: "Aperçu indisponible",
                        message: "Ce type de fichier n’a pas d’aperçu natif — utilise Partager."
                    )
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
                .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    nav.shareFilesToMail(files: [(fileId: fileId, filename: title)])
                    AppHaptics.light()
                } label: {
                    Image(systemName: "envelope.badge")
                }
                .accessibilityLabel("Envoyer par mail")
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                } else if let text = content?.text {
                    ShareLink(item: text) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let dto = try await client.fetchFileContent(fileId: fileId)
            content = dto
            shareURL = nil
            pdfURL = nil
            image = nil
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ql-files", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            if dto.kind == "image", let data = dto.binary {
                image = UIImage(data: data)
                let ext: String = {
                    if let name = dto.name {
                        let e = (name as NSString).pathExtension
                        if !e.isEmpty { return e }
                    }
                    return "jpg"
                }()
                let dest = dir.appendingPathComponent("\(abs(fileId.hashValue))-img.\(ext)")
                try data.write(to: dest, options: .atomic)
                shareURL = dest
            } else if dto.kind == "pdf", let data = dto.binary {
                let dest = dir.appendingPathComponent("\(abs(fileId.hashValue)).pdf")
                try data.write(to: dest, options: .atomic)
                pdfURL = dest
                shareURL = dest
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Sheet de confirmation mkdir — partagée Files browser + picker PJ.
struct MkdirConfirmSheet: View {
    let detail: String
    let confirming: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var folderName: String {
        let normalized = detail
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized.split(separator: "/").last.map(String.init) ?? (normalized.isEmpty ? "Nouveau dossier" : normalized)
    }

    private var parentPath: String? {
        let normalized = detail
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let slash = normalized.lastIndex(of: "/") else { return nil }
        let parent = String(normalized[..<slash])
        return parent.isEmpty ? nil : parent.replacingOccurrences(of: "/", with: " / ")
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(AppTheme.muted.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(AppTheme.filesAccent)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Créer ce dossier ?")
                    .font(CNFont.headline)
                    .foregroundStyle(AppTheme.foreground)
                Text(folderName)
                    .font(CNFont.title)
                    .foregroundStyle(AppTheme.foreground)
                    .multilineTextAlignment(.center)
                if let parentPath {
                    Text("dans \(parentPath)")
                        .font(CNFont.callout)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                } else {
                    Text("à la racine de l’emplacement")
                        .font(CNFont.callout)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Text(confirming ? "Création…" : "Créer et ouvrir")
                        .font(CNFont.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(confirming)

                Button("Annuler", role: .cancel, action: onCancel)
                    .disabled(confirming)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
    }
}

/// Barre multi-sélection Files — dock compact (OK uniquement dans la nav du haut).
private struct FilesMultiSelectBar: View {
    let count: Int
    let busy: Bool
    let onMove: () -> Void
    let onMail: () -> Void
    let onDelete: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(AppTheme.borderSubtle)

            HStack(alignment: .center, spacing: AppTheme.space12) {
                Button(action: onClear) {
                    HStack(spacing: 6) {
                        Text("\(max(count, 0))")
                            .font(CNFont.callout.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.accentForeground)
                            .frame(minWidth: 22)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.filesAccent)
                            )
                        Text(count <= 1 ? "sélectionné" : "sélectionnés")
                            .font(CNFont.caption.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(busy || count == 0)
                .accessibilityLabel(
                    count == 0
                        ? "Aucun fichier sélectionné"
                        : "\(count) sélectionnés, tout désélectionner"
                )

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    multiSelectAction(
                        title: "Déplacer",
                        systemImage: "folder",
                        tint: AppTheme.filesAccent,
                        emphasized: true,
                        action: onMove
                    )
                    multiSelectAction(
                        title: "Mail",
                        systemImage: "envelope",
                        tint: AppTheme.mailAccent,
                        emphasized: true,
                        action: onMail
                    )
                    multiSelectAction(
                        title: "Supprimer",
                        systemImage: "trash",
                        tint: AppTheme.danger,
                        emphasized: false,
                        action: onDelete
                    )
                }
                .disabled(busy || count == 0)
            }
            .padding(.horizontal, AppTheme.space14)
            .padding(.vertical, AppTheme.space10)
            .opacity(busy ? 0.55 : 1)
        }
        .background(.ultraThinMaterial)
    }

    private func multiSelectAction(
        title: String,
        systemImage: String,
        tint: Color,
        emphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(emphasized ? AppTheme.accentForeground : tint)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(emphasized ? tint : tint.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
