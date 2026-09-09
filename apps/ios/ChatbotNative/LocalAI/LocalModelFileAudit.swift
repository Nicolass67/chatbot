import Foundation

/// Audit / présence du fichier GGUF — purement filesystem, sans llama.cpp.
/// Règle unique : « installé » = exists + taille dans tolérance + magic `GGUF`.
enum LocalModelPresence: Equatable, Sendable {
    case missing
    /// Fichier présent mais invalide (taille ou magic).
    case invalid(size: Int64, sizeOK: Bool, magicOK: Bool)
    case installed(size: Int64)

    var isFullyInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    var size: Int64 {
        switch self {
        case .missing: return 0
        case .invalid(let size, _, _): return size
        case .installed(let size): return size
        }
    }
}

enum LocalModelFileAudit {
    static let sizeToleranceFraction: Double = 0.05

    static func validateSize(_ actual: Int64, expected: Int64) -> Bool {
        guard expected > 0, actual > 0 else { return false }
        let tolerance = Double(expected) * sizeToleranceFraction
        return abs(Double(actual - expected)) <= tolerance
    }

    static func isGGUFMagic(at url: URL, fileManager: FileManager = .default) -> Bool {
        let path = url.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        return data == Data("GGUF".utf8)
    }

    static func isGGUFMagic(dataPrefix: Data) -> Bool {
        dataPrefix.count >= 4 && dataPrefix.prefix(4) == Data("GGUF".utf8)
    }

    /// Évalue la présence réelle du modèle — aucune persistance UserDefaults.
    static func probe(
        at url: URL,
        expectedBytes: Int64,
        fileManager: FileManager = .default
    ) -> LocalModelPresence {
        let path = url.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else { return .missing }
        let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        let sizeOK = validateSize(size, expected: expectedBytes)
        let magicOK = isGGUFMagic(at: url, fileManager: fileManager)
        if sizeOK, magicOK { return .installed(size: size) }
        return .invalid(size: size, sizeOK: sizeOK, magicOK: magicOK)
    }

    static func directoryListing(at directory: URL, fileManager: FileManager = .default) -> [String] {
        let path = directory.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else { return [] }
        return ((try? fileManager.contentsOfDirectory(atPath: path)) ?? []).sorted()
    }

    /// Log metadata-only (jamais le contenu GGUF).
    static func log(_ channel: String, _ fields: [String: any CustomStringConvertible]) {
        let body = fields
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        print("[\(channel)] \(body)")
    }
}
