import Foundation

enum ProtectedStructureDetector {
    static func detect(
        in inventory: OrganizationInventory,
        manualProtected: Set<String>
    ) -> [ProtectedStructure] {
        var results: [ProtectedStructure] = []
        let folders = inventory.items.filter(\.isDirectory)
        let byParent = Dictionary(grouping: inventory.items, by: \.parentRelativePath)

        for folder in folders {
            let path = OrganizationPathUtils.normalize(folder.relativePath)
            let name = folder.name.lowercased()

            if manualProtected.contains(path)
                || manualProtected.contains(where: { path.hasPrefix($0 + "/") }) {
                results.append(.init(relativePath: path, name: folder.name, level: .protected, reason: "Protection manuelle", manual: true))
                continue
            }
            if looksProtectedName(name) {
                results.append(.init(relativePath: path, name: folder.name, level: .protected, reason: "Nom caractéristique d’une structure applicative", manual: false))
                continue
            }

            let children = byParent[path] ?? []
            let childFiles = children.filter { !$0.isDirectory }
            let childDirs = children.filter(\.isDirectory)
            let tech = childFiles.filter { isTechnicalExtension($0.extensionLower) }

            if childFiles.count >= 8, Double(tech.count) / Double(max(childFiles.count, 1)) >= 0.6 {
                results.append(.init(relativePath: path, name: folder.name, level: .protected, reason: "Majorité de fichiers techniques / binaires", manual: false))
                continue
            }
            if ["app", "bundle", "framework", "photoslibrary", "dataset"].contains(where: { name.hasSuffix(".\($0)") }) {
                results.append(.init(relativePath: path, name: folder.name, level: .protected, reason: "Bundle / bibliothèque", manual: false))
                continue
            }
            if childDirs.count >= 12 && childFiles.count >= 20 {
                results.append(.init(relativePath: path, name: folder.name, level: .review, reason: "Arborescence dense — vérifier avant organisation interne", manual: false))
            }
        }

        var best: [String: ProtectedStructure] = [:]
        for s in results {
            if let existing = best[s.relativePath], rank(existing.level) >= rank(s.level) { continue }
            best[s.relativePath] = s
        }
        return best.values.sorted { $0.relativePath < $1.relativePath }
    }

    private static func rank(_ level: OrganizationProtectionLevel) -> Int {
        switch level {
        case .normal: return 0
        case .review: return 1
        case .protected: return 2
        }
    }

    private static func looksProtectedName(_ name: String) -> Bool {
        let needles = [
            "node_modules", ".git", ".svn", ".hg", "__pycache__", ".venv", "venv",
            ".idea", ".vscode", "xcuserdata", "deriveddata", "pods",
            "library", "application support", "caches", "cache",
            "sqlite", "realm", "leveldb", "indexeddb", ".trash", ".trashes", "$recycle"
        ]
        return needles.contains { name == $0 || name.hasPrefix($0) || name.contains($0) }
    }

    private static func isTechnicalExtension(_ ext: String) -> Bool {
        ["dll", "so", "dylib", "exe", "bin", "dat", "db", "sqlite", "sqlite3", "realm", "idx", "pack", "o", "a", "class", "jar", "wasm", "pyc", "pyo", "map", "lock", "pid"].contains(ext)
    }
}

@MainActor
final class OrganizationProtectionStore {
    static let shared = OrganizationProtectionStore()
    private let defaultsKey = "files.organizer.manualProtected"
    private let alwaysKey = "files.organizer.alwaysProtected"
    private(set) var protectedByRoot: [String: Set<String>] = [:]
    private(set) var alwaysProtectedByRoot: [String: Set<String>] = [:]

    init() { load() }

    func manualSet(rootId: String) -> Set<String> {
        (protectedByRoot[rootId] ?? []).union(alwaysProtectedByRoot[rootId] ?? [])
    }

    func protect(rootId: String, path: String, always: Bool) {
        let n = OrganizationPathUtils.normalize(path)
        var ephemeral = protectedByRoot[rootId] ?? []
        ephemeral.insert(n)
        protectedByRoot[rootId] = ephemeral
        if always {
            var alwaysSet = alwaysProtectedByRoot[rootId] ?? []
            alwaysSet.insert(n)
            alwaysProtectedByRoot[rootId] = alwaysSet
        }
        persist()
    }

    func unprotect(rootId: String, path: String) {
        let n = OrganizationPathUtils.normalize(path)
        protectedByRoot[rootId]?.remove(n)
        alwaysProtectedByRoot[rootId]?.remove(n)
        persist()
    }

    private func load() {
        protectedByRoot = decode(defaultsKey)
        alwaysProtectedByRoot = decode(alwaysKey)
        for (root, paths) in alwaysProtectedByRoot {
            var set = protectedByRoot[root] ?? []
            set.formUnion(paths)
            protectedByRoot[root] = set
        }
    }

    private func persist() {
        encode(protectedByRoot, key: defaultsKey)
        encode(alwaysProtectedByRoot, key: alwaysKey)
    }

    private func decode(_ key: String) -> [String: Set<String>] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let obj = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return obj.mapValues(Set.init)
    }

    private func encode(_ value: [String: Set<String>], key: String) {
        let plain = value.mapValues { Array($0).sorted() }
        if let data = try? JSONEncoder().encode(plain) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
