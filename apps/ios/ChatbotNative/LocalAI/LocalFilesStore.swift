import Foundation

/// Racines fichiers **on-device** (sandbox). Pas PathGuard PC.
enum LocalFilesStore {
    static let documentsRootId = "iphone-documents"
    static let inboxRootId = "iphone-inbox"
    static let bookmarksRootPrefix = "iphone-bookmark:"

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var inboxDirectory: URL {
        documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Compat anciens IDs.
    static let rootId = documentsRootId

    static func fileId(rootId: String, relative: String) -> String {
        "local:\(rootId)|\(relative)"
    }

    static func parseFileId(_ id: String) -> (rootId: String, relative: String)? {
        guard id.hasPrefix("local:") else { return nil }
        let rest = String(id.dropFirst("local:".count))
        if let bar = rest.firstIndex(of: "|") {
            return (String(rest[..<bar]), String(rest[rest.index(after: bar)...]))
        }
        return (documentsRootId, rest)
    }

    static func isLocalRoot(_ id: String) -> Bool {
        id == documentsRootId || id == inboxRootId || id == "iphone-local"
            || id.hasPrefix("local:") || id.hasPrefix(bookmarksRootPrefix)
    }

    static func itemCount(rootId: String) -> Int {
        (try? list(relativePath: "", rootId: rootId))?.entries.count ?? 0
    }

    static func roots() -> [FileRootDTO] {
        let docCount = itemCount(rootId: documentsRootId)
        let docSubtitle = docCount == 0
            ? "Sandbox de l’app (vide) — pas le stockage complet de l’iPhone"
            : "Sandbox de l’app · \(docCount) élément\(docCount > 1 ? "s" : "")"
        var list: [FileRootDTO] = [
            FileRootDTO(
                id: documentsRootId,
                label: "Fichiers de l’app",
                absolutePath: docSubtitle,
                enabled: true
            ),
        ]
        let inbox = inboxDirectory
        if FileManager.default.fileExists(atPath: inbox.path),
           let names = try? FileManager.default.contentsOfDirectory(atPath: inbox.path),
           names.contains(where: { !$0.hasPrefix(".") }) {
            list.append(
                FileRootDTO(
                    id: inboxRootId,
                    label: "Reçus (Inbox)",
                    absolutePath: "Fichiers ouverts dans l’app",
                    enabled: true
                )
            )
        }
        list.append(contentsOf: LocalFileBookmarkStore.shared.roots())
        #if DEBUG
        logAccessibleRoots(list)
        #endif
        return list
    }

    static func root() -> FileRootDTO {
        roots().first!
    }

    static func list(relativePath: String, rootId: String = documentsRootId, profile: LocalModelExecutionProfile? = nil) throws -> FileListDTO {
        let folder = try resolve(relativePath: relativePath, rootId: rootId)
        let base = try baseURL(for: rootId)
        guard folder.path.hasPrefix(base.path) else {
            throw AIRuntimeError.toolFailed("Chemin fichiers local hors sandbox.")
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let names = try fm.contentsOfDirectory(atPath: folder.path)
        let budget = profile?.maxDocumentChunks ?? 40
        var entries: [FileEntryDTO] = []
        for name in names.sorted().prefix(max(budget * 4, 80)) {
            if name.hasPrefix(".") { continue }
            if rootId == documentsRootId && name == "Inbox" { continue }
            let url = folder.appendingPathComponent(name)
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue
            let mtime = (attrs?[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970 * 1000) }
            let rel = relative(from: url, rootId: rootId)
            entries.append(
                FileEntryDTO(
                    fileId: fileId(rootId: rootId, relative: rel),
                    name: name,
                    relativePath: rel,
                    isDirectory: isDir.boolValue,
                    sizeBytes: size,
                    mtimeMs: mtime,
                    indexed: true
                )
            )
        }
        return FileListDTO(fileId: nil, entries: entries, nextCursor: nil)
    }

    static func search(query: String, profile: LocalModelExecutionProfile) -> [FileSearchHitDTO] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 2 else { return [] }
        var hits: [FileSearchHitDTO] = []
        let budget = max(profile.maxDocumentChunks * 4, 24)
        for root in roots() {
            walk(rootId: root.id, relative: "", needle: needle, hits: &hits, budget: budget)
            if hits.count >= budget { break }
        }
        return hits
    }

    static func readText(relativePath: String, maxChars: Int, rootId: String = documentsRootId) -> String? {
        guard let url = try? resolve(relativePath: relativePath, rootId: rootId) else { return nil }
        guard let base = try? baseURL(for: rootId), url.path.hasPrefix(base.path) else { return nil }
        guard let data = try? Data(contentsOf: url), data.count <= 2_000_000 else { return nil }
        let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let raw, !raw.isEmpty else { return nil }
        return String(raw.prefix(maxChars))
    }

    static func catalogText(path: String, profile: LocalModelExecutionProfile) throws -> String {
        var chunks: [String] = []
        for root in roots() {
            let list = try self.list(relativePath: path, rootId: root.id, profile: profile)
            let header = root.label ?? root.id
            if list.entries.isEmpty {
                chunks.append("\(header) : dossier vide.")
                continue
            }
            let lines = list.entries.prefix(profile.maxDocumentChunks * 2).map { entry in
                let kind = entry.isDirectory == true ? "dossier" : "fichier"
                let size = entry.sizeBytes.map { " \($0) o" } ?? ""
                return "- [\(kind)] \(entry.name ?? entry.relativePath)\(size)"
            }
            chunks.append("\(header) :\n" + lines.joined(separator: "\n"))
        }
        return chunks.joined(separator: "\n\n")
    }

    static func importFile(from url: URL, relativeFolder: String, rootId: String = documentsRootId) throws -> String {
        let destDir = try resolve(relativePath: relativeFolder, rootId: rootId)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        var name = url.lastPathComponent
        var dest = destDir.appendingPathComponent(name)
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            dest = destDir.appendingPathComponent(name)
            i += 1
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: dest)
        } else {
            let data = try Data(contentsOf: url)
            try data.write(to: dest)
        }
        return dest.lastPathComponent
    }

    static func createDirectory(relativePath: String, rootId: String = documentsRootId) throws {
        let url = try resolve(relativePath: relativePath, rootId: rootId)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func deleteEntry(relativePath: String, rootId: String) throws {
        let url = try resolve(relativePath: relativePath, rootId: rootId)
        let base = try baseURL(for: rootId)
        guard url.path.hasPrefix(base.path), url.path != base.path else {
            throw AIRuntimeError.toolFailed("Suppression hors sandbox.")
        }
        try FileManager.default.removeItem(at: url)
    }

    static func renameEntry(relativePath: String, newName: String, rootId: String) throws {
        let src = try resolve(relativePath: relativePath, rootId: rootId)
        let dest = src.deletingLastPathComponent().appendingPathComponent(newName)
        let base = try baseURL(for: rootId)
        guard src.path.hasPrefix(base.path), dest.path.hasPrefix(base.path) else {
            throw AIRuntimeError.toolFailed("Renommage hors sandbox.")
        }
        try FileManager.default.moveItem(at: src, to: dest)
    }

    // MARK: - Paths

    #if DEBUG
    private static func logAccessibleRoots(_ roots: [FileRootDTO]) {
        let fm = FileManager.default
        let docs = documentsDirectory
        let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask).first
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        let tmp = fm.temporaryDirectory
        let group = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.fr.nicolazer.chatbot.native")
        func describe(_ url: URL?) -> String {
            guard let url else { return "nil" }
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            let count = (try? fm.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }.count) ?? -1
            return "path=\(url.lastPathComponent) exists=\(exists) dir=\(isDir.boolValue) readable=\(fm.isReadableFile(atPath: url.path)) items=\(count)"
        }
        WorkflowTrace.log("files", [
            "documents": describe(docs),
            "library": describe(lib),
            "caches": describe(caches),
            "tmp": describe(tmp),
            "app_group": describe(group),
            "roots": "\(roots.count)",
        ])
    }
    #endif

    static func baseURL(for rootId: String) throws -> URL {
        switch rootId {
        case documentsRootId, "iphone-local":
            return documentsDirectory
        case inboxRootId:
            return inboxDirectory
        default:
            if rootId.hasPrefix(bookmarksRootPrefix) {
                guard let url = LocalFileBookmarkStore.shared.resolve(rootId: rootId) else {
                    throw AIRuntimeError.toolFailed("Dossier importé inaccessible.")
                }
                return url
            }
            throw AIRuntimeError.toolFailed("Racine fichiers inconnue.")
        }
    }

    static func resolve(relativePath: String, rootId: String) throws -> URL {
        let base = try baseURL(for: rootId)
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty { return base }
        let url = base.appendingPathComponent(trimmed)
        guard url.path.hasPrefix(base.path) else {
            throw AIRuntimeError.toolFailed("Chemin fichiers local hors sandbox.")
        }
        return url
    }

    private static func relative(from url: URL, rootId: String) -> String {
        guard let base = try? baseURL(for: rootId).standardizedFileURL.path else {
            return url.lastPathComponent
        }
        let path = url.standardizedFileURL.path
        if path == base { return "" }
        if path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return url.lastPathComponent
    }

    private static func walk(
        rootId: String,
        relative: String,
        needle: String,
        hits: inout [FileSearchHitDTO],
        budget: Int
    ) {
        guard hits.count < budget else { return }
        let list = (try? list(relativePath: relative, rootId: rootId))?.entries ?? []
        for entry in list {
            if hits.count >= budget { return }
            let name = (entry.name ?? entry.relativePath).lowercased()
            if name.contains(needle) {
                hits.append(
                    FileSearchHitDTO(
                        fileId: entry.fileId ?? fileId(rootId: rootId, relative: entry.relativePath),
                        name: entry.name,
                        filename: entry.name,
                        relativePath: entry.relativePath,
                        rootId: rootId,
                        sizeBytes: entry.sizeBytes,
                        isDirectory: entry.isDirectory,
                        snippet: nil,
                        matchSource: "name"
                    )
                )
            }
            if entry.isDirectory == true {
                walk(
                    rootId: rootId,
                    relative: entry.relativePath,
                    needle: needle,
                    hits: &hits,
                    budget: budget
                )
            }
        }
    }
}

/// Dossiers importés (security-scoped bookmarks) persistés.
final class LocalFileBookmarkStore: @unchecked Sendable {
    static let shared = LocalFileBookmarkStore()
    private let defaultsKey = "local.files.bookmarks.v1"
    private let lock = NSLock()
    private var cache: [Item] = []

    struct Item: Codable {
        var id: String
        var label: String
        var bookmark: Data
    }

    private init() {
        load()
    }

    func roots() -> [FileRootDTO] {
        lock.lock()
        let snapshot = cache
        lock.unlock()
        return snapshot.compactMap { item in
            guard resolve(rootId: item.id) != nil else { return nil }
            return FileRootDTO(
                id: item.id,
                label: item.label,
                absolutePath: "Dossier importé",
                enabled: true
            )
        }
    }

    func addFolder(url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let id = LocalFilesStore.bookmarksRootPrefix + UUID().uuidString
        let item = Item(id: id, label: url.lastPathComponent, bookmark: data)
        lock.lock()
        cache.append(item)
        persistLocked()
        lock.unlock()
    }

    func resolve(rootId: String) -> URL? {
        lock.lock()
        let item = cache.first(where: { $0.id == rootId })
        lock.unlock()
        guard let item else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: item.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            cache = []
            return
        }
        cache = decoded
    }

    private func persistLocked() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
