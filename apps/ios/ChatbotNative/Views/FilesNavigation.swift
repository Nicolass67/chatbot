import Foundation

enum FilesNavResult: Equatable, Sendable {
    case appended
    case poppedToExisting
    case ignoredDuplicate
}

/// Navigation Files idempotente — identité = (rootId + relativePath) / fileId, pas le titre.
enum FilesPathOps {
    static func normalizePath(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func locationKey(_ dest: FilesDestination) -> String {
        switch dest {
        case .folder(let rootId, let path, _):
            return "folder:\(rootId):\(normalizePath(path))"
        case .file(let fileId, _, let rootId, _):
            return "file:\(rootId):\(fileId)"
        }
    }

    static func isRootFolder(_ dest: FilesDestination) -> Bool {
        if case .folder(_, let path, _) = dest {
            return normalizePath(path).isEmpty
        }
        return false
    }

    static func isSameLocation(_ a: FilesDestination?, _ b: FilesDestination) -> Bool {
        guard let a else { return false }
        return locationKey(a) == locationKey(b)
    }

    /// Empile une destination sans doublon. Une root déjà présente replace/pop, elle ne s’empile pas sur elle-même.
    static func push(
        _ path: [FilesDestination],
        _ dest: FilesDestination
    ) -> (path: [FilesDestination], result: FilesNavResult) {
        if isSameLocation(path.last, dest) {
            return (path, .ignoredDuplicate)
        }
        if let idx = path.firstIndex(where: { locationKey($0) == locationKey(dest) }) {
            return (Array(path.prefix(through: idx)), .poppedToExisting)
        }
        if isRootFolder(dest) {
            // Root : réinitialise le chemin à cette unique root (jamais Root/Root).
            return ([dest], .poppedToExisting)
        }
        return (path + [dest], .appended)
    }

    static func dedupe(_ path: [FilesDestination]) -> [FilesDestination] {
        var seen = Set<String>()
        var out: [FilesDestination] = []
        for dest in path {
            let key = locationKey(dest)
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(dest)
        }
        return out
    }

    static func breadcrumb(_ path: [FilesDestination]) -> String {
        path.map { dest in
            switch dest {
            case .folder(_, _, let title):
                return title
            case .file(_, let title, _, _):
                return title
            }
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: " / ")
    }
}
