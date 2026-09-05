import Foundation

enum OrganizationHeuristicPlanner {
    /// Plan métadonnées-first. Produit toujours ≥1 proposition si un fichier est déplaçable.
    static func propose(
        inventory: OrganizationInventory,
        protected: [ProtectedStructure],
        instruction: String? = nil
    ) throws -> OrganizationPlan {
        let root = OrganizationPathUtils.normalize(inventory.scope.relativePath)
        let protectedPaths = Set(
            protected
                .filter { $0.level == .protected }
                .map { OrganizationPathUtils.normalize($0.relativePath) }
        )
        let hint = (instruction ?? "").lowercased()

        let candidates = inventory.items.filter { item in
            guard !item.isDirectory else { return false }
            guard item.depth <= 4 else { return false }
            return !isUnderProtected(item.relativePath, protected: protectedPaths)
        }

        if candidates.isEmpty {
            let anyFiles = inventory.items.contains { !$0.isDirectory }
            if !anyFiles {
                throw OrganizationEngineError.emptyFolder
            }
            throw OrganizationEngineError.alreadyOrganized
        }

        var moves: [OrganizationMove] = []
        var dirs = Set<String>()
        var seen = Set<String>()

        let rootFiles = candidates.filter {
            OrganizationPathUtils.normalize($0.parentRelativePath) == root
        }
        appendMoves(
            files: rootFiles,
            root: root,
            hint: hint,
            moves: &moves,
            dirs: &dirs,
            seen: &seen
        )

        if moves.isEmpty {
            let nested = candidates
                .filter { OrganizationPathUtils.normalize($0.parentRelativePath) != root }
                .sorted { $0.depth < $1.depth }
            appendMoves(
                files: Array(nested.prefix(40)),
                root: root,
                hint: hint,
                moves: &moves,
                dirs: &dirs,
                seen: &seen
            )
        }

        if moves.isEmpty, let forced = forcedFallback(from: candidates, root: root, hint: hint) {
            dirs.insert(OrganizationPathUtils.parent(of: forced.destinationRelativePath))
            moves.append(forced)
        }

        guard !moves.isEmpty else {
            throw OrganizationEngineError.alreadyOrganized
        }

        let autoCount = moves.filter { !$0.needsReview }.count
        let reviewCount = moves.filter(\.needsReview).count
        let avg = moves.map(\.confidence).reduce(0, +) / Double(moves.count)
        var warnings: [String] = []
        if reviewCount > 0 {
            warnings.append("\(reviewCount) à confirmer ou exclure.")
        }
        let locked = protected.filter { $0.level == .protected }.count
        if locked > 0 {
            warnings.append("\(locked) structure(s) protégée(s).")
        }

        let folders = dirs.sorted().map { OrganizationPathUtils.basename(of: $0) }.joined(separator: ", ")
        let summary = "\(autoCount) auto · \(reviewCount) revue · \(dirs.count) dossier\(dirs.count > 1 ? "s" : "") · \(folders)"

        return OrganizationPlan(
            id: UUID().uuidString,
            rootId: inventory.scope.rootId,
            rootRelativePath: root,
            createdAt: Date(),
            summary: summary,
            protectedStructures: protected,
            proposedDirectories: dirs.sorted(),
            moves: moves,
            warnings: warnings,
            conflicts: [],
            confidence: avg,
            userInstruction: instruction
        )
    }

    private static func appendMoves(
        files: [OrganizationInventoryItem],
        root: String,
        hint: String,
        moves: inout [OrganizationMove],
        dirs: inout Set<String>,
        seen: inout Set<String>
    ) {
        for file in files {
            let source = OrganizationPathUtils.normalize(file.relativePath)
            guard !seen.contains(source) else { continue }
            let cat = categorize(file: file, hint: hint)
            let destFolder = OrganizationPathUtils.join(root, cat.folderName)
            let dest = OrganizationPathUtils.join(destFolder, file.name)
            if OrganizationPathUtils.normalize(dest) == source { continue }
            if OrganizationPathUtils.normalize(file.parentRelativePath) == OrganizationPathUtils.normalize(destFolder) {
                continue
            }
            dirs.insert(destFolder)
            seen.insert(source)
            moves.append(
                OrganizationMove(
                    sourceRelativePath: file.relativePath,
                    destinationRelativePath: dest,
                    operation: .move,
                    confidence: cat.confidence,
                    reason: cat.reason,
                    sourceFileId: file.fileId,
                    sourceIsDirectory: false,
                    needsReview: cat.confidence < OrganizationConfidence.autoExecuteMinimum,
                    excluded: false
                )
            )
        }
    }

    private static func forcedFallback(
        from files: [OrganizationInventoryItem],
        root: String,
        hint: String
    ) -> OrganizationMove? {
        for file in files.sorted(by: { $0.depth < $1.depth }) {
            let cat = categorize(file: file, hint: hint)
            let destFolder = OrganizationPathUtils.join(root, cat.folderName)
            let dest = OrganizationPathUtils.join(destFolder, file.name)
            let source = OrganizationPathUtils.normalize(file.relativePath)
            if OrganizationPathUtils.normalize(dest) == source { continue }
            if OrganizationPathUtils.normalize(file.parentRelativePath) == OrganizationPathUtils.normalize(destFolder) {
                continue
            }
            return OrganizationMove(
                sourceRelativePath: file.relativePath,
                destinationRelativePath: dest,
                operation: .move,
                confidence: min(cat.confidence, 0.68),
                reason: "Proposition · \(cat.reason)",
                sourceFileId: file.fileId,
                sourceIsDirectory: false,
                needsReview: true,
                excluded: false
            )
        }
        guard let file = files.first else { return nil }
        let destFolder = OrganizationPathUtils.join(root, "A classer")
        let dest = OrganizationPathUtils.join(destFolder, file.name)
        if OrganizationPathUtils.normalize(dest) == OrganizationPathUtils.normalize(file.relativePath) {
            return nil
        }
        return OrganizationMove(
            sourceRelativePath: file.relativePath,
            destinationRelativePath: dest,
            operation: .move,
            confidence: 0.5,
            reason: "Proposition minimale · A classer",
            sourceFileId: file.fileId,
            sourceIsDirectory: false,
            needsReview: true,
            excluded: false
        )
    }

    private struct Category {
        let folderName: String
        let confidence: Double
        let reason: String
    }

    private static func categorize(file: OrganizationInventoryItem, hint: String) -> Category {
        let name = file.name.lowercased()
        let ext = file.extensionLower
        let stem = name.replacingOccurrences(of: ".\(ext)", with: ext.isEmpty ? "" : "")

        if matchesAny(stem, ["facture", "invoice", "receipt", "reçu", "recu", "avoir", "devis"])
            || hint.contains("facture") {
            return .init(folderName: "Factures", confidence: 0.88, reason: "Facture / reçu")
        }
        if matchesAny(stem, ["contrat", "contract", "accord", "nda", "bail", "avenant"])
            || hint.contains("contrat") {
            return .init(folderName: "Contrats", confidence: 0.86, reason: "Contrat")
        }
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp", "raw", "dng"].contains(ext)
            || hint.contains("image") || hint.contains("photo") {
            return .init(folderName: "Images", confidence: 0.9, reason: "Image")
        }
        if matchesAny(stem, ["voyage", "travel", "hotel", "vol", "flight", "billet", "boarding", "itinéraire", "itineraire", "reservation", "réservation"])
            || hint.contains("voyage") {
            return .init(folderName: "Voyages", confidence: 0.82, reason: "Voyage")
        }
        if ext == "pdf" && matchesAny(stem, ["ticket", "pass", "booking"]) {
            return .init(folderName: "Voyages", confidence: 0.75, reason: "PDF voyage")
        }
        if ["pdf", "doc", "docx", "txt", "rtf", "odt"].contains(ext) {
            return .init(folderName: "Documents", confidence: 0.7, reason: "Document")
        }
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
            return .init(folderName: "Archives", confidence: 0.78, reason: "Archive")
        }
        return .init(folderName: "A classer", confidence: 0.55, reason: "À confirmer")
    }

    private static func matchesAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func isUnderProtected(_ path: String, protected: Set<String>) -> Bool {
        let p = OrganizationPathUtils.normalize(path)
        if protected.contains(p) { return true }
        return protected.contains { p.hasPrefix($0 + "/") }
    }
}
