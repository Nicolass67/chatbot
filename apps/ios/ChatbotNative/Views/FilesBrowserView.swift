import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum FilesViewMode: String {
    case list, grid
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
enum FilesDestination: Hashable {
    case folder(rootId: String, path: String, title: String)
    case file(fileId: String, title: String, rootId: String, folderPath: String)
}

struct FilesBrowserView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    @State private var path = NavigationPath()
    @State private var roots: [FileRootDTO] = []
    @State private var rootsById: [String: FileRootDTO] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var searchQuery = ""
    @State private var searchHits: [FileSearchHitDTO] = []
    @State private var searching = false
    @State private var showAssistant = false
    @State private var assistantContext = FilesAssistantContext.global

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AmbientBackground()
                content
                ContextualAssistantButton {
                    assistantContext = .global
                    showAssistant = true
                }
                .accessibilityIdentifier(A11yID.Files.assistant)
            }
            .navigationTitle("Files")
            .accessibilityIdentifier(A11yID.Files.root)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        nav.openSettings()
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Réglages")
                    .accessibilityIdentifier(A11yID.Files.settings)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $searchQuery, prompt: "Rechercher un fichier")
            .onChange(of: searchQuery) { _, q in
                Task { await runSearch(q) }
            }
            .onChange(of: nav.filesDeepLink) { _, link in
                guard let link else { return }
                if let q = link.query, !q.isEmpty {
                    searchQuery = q
                    Task { await runSearch(q) }
                }
                if let rootId = link.rootId, let root = rootsById[rootId] {
                    path.append(FilesDestination.folder(rootId: root.id, path: "", title: root.label ?? "Root"))
                }
                nav.filesDeepLink = nil
            }
            .onChange(of: nav.presentFilesAssistant) { _, present in
                if present {
                    assistantContext = nav.filesAssistantContext
                    showAssistant = true
                    nav.presentFilesAssistant = false
                }
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
                        // Nested drill-in requires folder listing — UI tests / HID handle deeper levels.
                    }
                    nav.qaIntent = nil
                case .filesFile:
                    // Prefers search hit / first file once a folder is open — intent marks request.
                    nav.qaIntent = nil
                case .filesAssistant:
                    assistantContext = .global
                    showAssistant = true
                    nav.qaIntent = nil
                default:
                    break
                }
            }
            .refreshable { await loadRoots() }
            .task { await loadRoots() }
            .navigationDestination(for: FilesDestination.self) { dest in
                destinationView(dest)
            }
            .sheet(isPresented: $showAssistant) {
                ContextualAssistantSheet(
                    scope: .files,
                    title: assistantContext.sheetTitle,
                    contextLabel: assistantContext.label,
                    contextRef: assistantContext.ref
                )
                .environmentObject(session)
                .environment(nav)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
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
                    onAskAssistant: {
                        assistantContext = .folder(rootId: root.id, path: folderPath, title: title)
                        showAssistant = true
                    }
                )
            } else {
                SoftEmptyState(
                    systemImage: "externaldrive.badge.xmark",
                    title: "Racine introuvable",
                    message: "Cette racine n’est plus disponible."
                )
            }
        case .file(let fileId, let title, let rootId, let folderPath):
            FilePreviewView(
                fileId: fileId,
                title: title,
                onAskAssistant: {
                    assistantContext = .file(fileId: fileId, name: title, rootId: rootId, path: folderPath)
                    showAssistant = true
                }
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
                        Button {
                            path.append(
                                FilesDestination.folder(
                                    rootId: root.id,
                                    path: "",
                                    title: root.label ?? "Root"
                                )
                            )
                        } label: {
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
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(A11yID.Files.folder)
                        Divider().overlay(AppTheme.borderSubtle).padding(.leading, 54)
                    }
                }
                .padding(.bottom, 72)
            }
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
                .padding(.bottom, 72)
            }
        }
    }

    private func loadRoots() async {
        loading = true
        defer { loading = false }
        do {
            roots = try await client.listFileRoots()
            rootsById = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
            error = nil
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
    let root: FileRootDTO
    let path: String
    let title: String
    var onOpenFolder: (FileEntryDTO) -> Void
    var onOpenFile: (FileEntryDTO) -> Void
    var onAskAssistant: () -> Void

    @State private var entries: [FileEntryDTO] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var nextCursor: String?
    @State private var error: String?
    @State private var openError: String?
    @State private var viewMode: FilesViewMode = .list
    @State private var typeFilter: FilesTypeFilter = .all
    @State private var showMkdir = false
    @State private var mkdirName = ""
    @State private var renameTarget: FileEntryDTO?
    @State private var renameText = ""
    @State private var showImporter = false
    @State private var pendingPropose: FilesProposeResult?
    @State private var confirming = false
    @State private var uploading = false

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var breadcrumb: String {
        path.isEmpty ? (root.label ?? "Root") : "\(root.label ?? "Root") / \(path.replacingOccurrences(of: "/", with: " / "))"
    }

    private var filtered: [FileEntryDTO] {
        entries.filter { entry in
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
                } else if filtered.isEmpty {
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
                } else {
                    list
                }
            }
            ContextualAssistantButton(action: onAskAssistant)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                Menu {
                    Button { showMkdir = true } label: { Label("Nouveau dossier", systemImage: "folder.badge.plus") }
                    Button { showImporter = true } label: { Label("Importer un fichier", systemImage: "square.and.arrow.down") }
                        .disabled(uploading)
                    Divider()
                    Picker("Vue", selection: $viewMode) {
                        Label("Liste", systemImage: "list.bullet").tag(FilesViewMode.list)
                        Label("Grille", systemImage: "square.grid.2x2").tag(FilesViewMode.grid)
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
        .alert("Nouveau dossier", isPresented: $showMkdir) {
            TextField("Nom", text: $mkdirName)
            Button("Annuler", role: .cancel) { mkdirName = "" }
            Button("Créer") { Task { await createDirectory() } }
        } message: {
            Text("Le dossier sera créé sous « \(title) » après confirmation.")
        }
        .alert("Renommer", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Nouveau nom", text: $renameText)
            Button("Annuler", role: .cancel) { renameTarget = nil }
            Button("Proposer") { Task { await renameEntry() } }
        }
        .alert("Confirmer l’action ?", isPresented: Binding(
            get: { pendingPropose != nil },
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
        .task { await load(reset: true) }
    }

    private func isFolder(_ entry: FileEntryDTO) -> Bool { entry.isDirectory == true }

    private var list: some View {
        List {
            ForEach(filtered) { entry in
                Button {
                    if isFolder(entry) { onOpenFolder(entry) } else { onOpenFile(entry) }
                } label: {
                    fileRow(entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .listRowBackground(AppTheme.surface.opacity(0.35))
                .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                .contextMenu {
                    if entry.fileId != nil {
                        Button {
                            renameTarget = entry
                            renameText = entry.name ?? ""
                        } label: { Label("Renommer", systemImage: "pencil") }
                    }
                }
                .onAppear {
                    if entry.id == filtered.last?.id {
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
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(filtered) { entry in
                    Button {
                        if isFolder(entry) { onOpenFolder(entry) } else { onOpenFile(entry) }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: isFolder(entry) ? "folder.fill" : iconName(for: entry.name ?? ""))
                                .font(.system(size: 28))
                                .foregroundStyle(isFolder(entry) ? AppTheme.accent : AppTheme.muted)
                                .frame(height: 48)
                            Text(entry.name ?? entry.relativePath)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.foreground)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if entry.id == filtered.last?.id {
                            Task { await loadMoreIfNeeded() }
                        }
                    }
                }
            }
            .padding(14)
            .padding(.bottom, 72)
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
                if !isFolder(entry), let size = entry.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                } else if isFolder(entry) {
                    Text("Dossier")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                }
            }
            Spacer()
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
        if n.hasSuffix(".png") || n.hasSuffix(".jpg") || n.hasSuffix(".jpeg") || n.hasSuffix(".webp") { return "photo" }
        if n.hasSuffix(".md") || n.hasSuffix(".txt") { return "doc.plaintext" }
        if n.hasSuffix(".json") || n.hasSuffix(".csv") { return "tablecells" }
        return "doc.fill"
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
            entries = Self.sorted(list.entries)
            nextCursor = list.nextCursor
            error = nil
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
            entries = Self.sorted(merged)
            nextCursor = list.nextCursor
        } catch {
            // silent — user still has first page
        }
    }

    private static func sorted(_ items: [FileEntryDTO]) -> [FileEntryDTO] {
        items.sorted { a, b in
            let ad = a.isDirectory == true
            let bd = b.isDirectory == true
            if ad != bd { return ad && !bd }
            return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
        }
    }

    private func createDirectory() async {
        let name = mkdirName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mkdirName = ""
        let dest = path.isEmpty ? name : "\(path)/\(name)"
        do {
            pendingPropose = try await client.proposeCreateDirectory(rootId: root.id, destRelativePath: dest)
            AppHaptics.light()
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

struct FilePreviewView: View {
    @EnvironmentObject private var session: AppSessionStore
    let fileId: String
    let title: String
    var onAskAssistant: (() -> Void)? = nil

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
                        message: "Ce type de fichier n’a pas d’aperçu natif — utilise Partager ou Demander."
                    )
                }
            }
            if let onAskAssistant {
                ContextualAssistantButton(action: onAskAssistant)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let onAskAssistant {
                    Button {
                        AppHaptics.light()
                        onAskAssistant()
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Assistant Files")
                    .accessibilityIdentifier(A11yID.Files.assistant)
                }
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
