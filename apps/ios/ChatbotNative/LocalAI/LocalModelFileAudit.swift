import Foundation
import OSLog

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

    /// Visible via `pymobiledevice3 syslog` (contrairement à `print` en Release).
    private static let logger = Logger(
        subsystem: "fr.nicolazer.chatbot.native",
        category: "local-ai"
    )

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
    /// `Logger` + `NSLog` : visibles dans syslog device ; `print` Release ne l’est pas.
    static func log(_ channel: String, _ fields: [String: any CustomStringConvertible]) {
        let body = fields
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        let line = "[\(channel)] \(body)"
        logger.notice("\(line, privacy: .public)")
        NSLog("%@", line)
    }

    /// Snapshot lecture-seule du conteneur Models / Application Support.
    /// Ne crée, ne déplace, ne supprime aucun fichier.
    static func snapshotFS(
        point: String,
        finalPath: String,
        fileManager: FileManager = .default
    ) {
        let finalURL = URL(fileURLWithPath: finalPath, isDirectory: false)
        let modelsDirectory = finalURL.deletingLastPathComponent()
        let applicationSupport = modelsDirectory.deletingLastPathComponent()
        let partialPath = finalPath + ".download"
        let exists = fileManager.fileExists(atPath: finalPath)
        let size = (try? fileManager.attributesOfItem(atPath: finalPath)[.size] as? Int64) ?? 0
        let partialExists = fileManager.fileExists(atPath: partialPath)
        log("local-ai:fs-snapshot", [
            "point": point,
            "containerUUID": containerUUID(from: finalPath),
            "modelsDirectory": modelsDirectory.path(percentEncoded: false),
            "applicationSupport": applicationSupport.path(percentEncoded: false),
            "finalPath": finalPath,
            "final.exists": exists,
            "final.size": size,
            "final.readable": fileManager.isReadableFile(atPath: finalPath),
            "partial.exists": partialExists,
            "partial.path": partialPath,
            "models.entries": directoryListing(at: modelsDirectory, fileManager: fileManager).joined(separator: "|"),
            "appSupport.entries": directoryListing(at: applicationSupport, fileManager: fileManager).joined(separator: "|"),
        ])
    }

    /// Trace d’une opération filesystem (appelée autour de l’op, sans en changer le résultat).
    static func logFSOp(
        _ operation: String,
        phase: String,
        result: String,
        source: String? = nil,
        destination: String? = nil,
        watchedFinalPath: String? = nil
    ) {
        var fields: [String: any CustomStringConvertible] = [
            "operation": operation,
            "phase": phase,
            "result": result,
        ]
        if let source { fields["source"] = source }
        if let destination { fields["destination"] = destination }
        if let watchedFinalPath {
            let fm = FileManager.default
            fields["watchedFinalPath"] = watchedFinalPath
            fields["watchedFinal.exists"] = fm.fileExists(atPath: watchedFinalPath)
            fields["watchedFinal.size"] = (try? fm.attributesOfItem(atPath: watchedFinalPath)[.size] as? Int64) ?? 0
        }
        log("local-ai:fs-op", fields)
    }

    static func containerUUID(from path: String) -> String {
        // …/Application/<UUID>/Library/…
        guard let range = path.range(of: "/Application/") else { return "unknown" }
        let after = path[range.upperBound...]
        let uuid = after.split(separator: "/").first.map(String.init) ?? "unknown"
        return uuid
    }
}
