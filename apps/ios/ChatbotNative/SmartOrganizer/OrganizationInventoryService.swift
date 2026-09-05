import Foundation

enum OrganizationInventoryService {
    static let maxItems = 2500
    static let maxDepth = 8

    /// Inventaire récursif via `APIClient.listFiles`, avec pagination et plafonds.
    static func build(
        client: APIClient,
        scope: OrganizationScope,
        cancelRequested: () -> Bool = { false },
        onProgress: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> OrganizationInventory {
        let rootPath = OrganizationPathUtils.normalize(scope.relativePath)
        let rootDepth = OrganizationPathUtils.depth(of: rootPath)
        var collected: [OrganizationInventoryItem] = []
        var queue: [(path: String, depth: Int)] = [(rootPath, 0)]
        var visited = Set<String>()

        onProgress?("Scan du dossier…", 0.02)

        while !queue.isEmpty {
            if cancelRequested() { throw OrganizationEngineError.cancelled }
            let current = queue.removeFirst()
            let norm = OrganizationPathUtils.normalize(current.path)
            if visited.contains(norm) { continue }
            visited.insert(norm)

            if current.depth > maxDepth { continue }

            var cursor: String? = nil
            repeat {
                if cancelRequested() { throw OrganizationEngineError.cancelled }
                let page = try await client.listFiles(rootId: scope.rootId, path: norm, cursor: cursor)
                for entry in page.entries {
                    if collected.count >= maxItems { break }
                    let name = entry.name ?? OrganizationPathUtils.basename(of: entry.relativePath)
                    let rel = OrganizationPathUtils.normalize(entry.relativePath)
                    let isDir = entry.isDirectory == true
                    let parent = OrganizationPathUtils.parent(of: rel)
                    let absDepth = OrganizationPathUtils.depth(of: rel)
                    let relativeDepth = max(0, absDepth - rootDepth)

                    let item = OrganizationInventoryItem(
                        fileId: entry.fileId,
                        name: name,
                        relativePath: rel,
                        isDirectory: isDir,
                        extensionLower: OrganizationPathUtils.fileExtension(of: name),
                        sizeBytes: entry.sizeBytes ?? 0,
                        mtimeMs: entry.mtimeMs,
                        parentRelativePath: parent,
                        depth: relativeDepth
                    )
                    collected.append(item)

                    if isDir, relativeDepth < maxDepth, !visited.contains(rel) {
                        queue.append((rel, relativeDepth + 1))
                    }
                }
                cursor = page.nextCursor
                let progress = min(0.9, Double(collected.count) / Double(maxItems))
                onProgress?(
                    "Scan… \(collected.count) élément\(collected.count > 1 ? "s" : "")",
                    progress
                )
            } while cursor != nil && !(cursor?.isEmpty ?? true) && collected.count < maxItems

            if collected.count >= maxItems { break }
        }

        onProgress?("Inventaire terminé (\(collected.count))", 1.0)
        return OrganizationInventory(scope: scope, items: collected, scannedAt: Date())
    }
}
