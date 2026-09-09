import Foundation

/// Fichiers **on-device** (Documents de l’app) — runtime local, pas PathGuard PC.
enum LocalFilesStore {
    static let rootId = "iphone-local"
    static let rootLabel = "iPhone"

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func root() -> FileRootDTO {
        FileRootDTO(
            id: rootId,
            label: rootLabel,
            absolutePath: documentsDirectory.path,
            enabled: true
        )
    }

    static func isLocalRoot(_ id: String) -> Bool {
        id == rootId || id.hasPrefix("local:")
    }

    static func list(relativePath: String, profile: LocalModelExecutionProfile? = nil) throws -> FileListDTO {
        let base = documentsDirectory
        let folder = resolve(relativePath)
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
        for name in names.sorted().prefix(max(budget * 4, 40)) {
            if name.hasPrefix(".") { continue }
            let url = folder.appendingPathComponent(name)
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue
            let mtime = (attrs?[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970 * 1000) }
            let rel = relative(from: url)
            entries.append(
                FileEntryDTO(
                    fileId: "local:\(rel)",
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
        let list = (try? list(relativePath: "", profile: profile).entries) ?? []
        return list.compactMap { entry in
            let name = (entry.name ?? entry.relativePath).lowercased()
            guard name.contains(needle) else { return nil }
            return FileSearchHitDTO(
                fileId: entry.fileId ?? "local:\(entry.relativePath)",
                name: entry.name,
                filename: entry.name,
                relativePath: entry.relativePath,
                rootId: rootId,
                sizeBytes: entry.sizeBytes,
                isDirectory: entry.isDirectory,
                snippet: nil,
                matchSource: "name"
            )
        }
    }

    static func readText(relativePath: String, maxChars: Int) -> String? {
        let url = resolve(relativePath)
        guard url.path.hasPrefix(documentsDirectory.path) else { return nil }
        guard let data = try? Data(contentsOf: url), data.count <= 2_000_000 else { return nil }
        let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let raw, !raw.isEmpty else { return nil }
        return String(raw.prefix(maxChars))
    }

    static func catalogText(path: String, profile: LocalModelExecutionProfile) throws -> String {
        let list = try self.list(relativePath: path, profile: profile)
        if list.entries.isEmpty {
            return "Aucun fichier dans Documents iPhone (dossier app). Dépose des fichiers dans l’app pour les utiliser en local."
        }
        let lines = list.entries.prefix(profile.maxDocumentChunks * 2).map { entry in
            let kind = entry.isDirectory == true ? "dossier" : "fichier"
            let size = entry.sizeBytes.map { " \($0) o" } ?? ""
            return "- [\(kind)] \(entry.name ?? entry.relativePath)\(size) path=\(entry.relativePath)"
        }
        return "Fichiers locaux (iPhone / Documents) :\n" + lines.joined(separator: "\n")
    }

    private static func resolve(_ relativePath: String) -> URL {
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty { return documentsDirectory }
        return documentsDirectory.appendingPathComponent(trimmed)
    }

    private static func relative(from url: URL) -> String {
        let base = documentsDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == base { return "" }
        if path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return url.lastPathComponent
    }
}
