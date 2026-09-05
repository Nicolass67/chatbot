import Foundation

enum OrganizationHeuristicPlanner {
    /// Plan métadonnées-first : factures, contrats, images, voyages, A classer.
    /// Ne déplace que les fichiers à la racine du scope (depth 1), hors structures protégées.
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

        let rootFiles = inventory.items.filter { item in
            guard !item.isDirectory else { return false }
            guard item.depth == 1 || (root.isEmpty && item.depth == 1) || item.parentRelativePath == root
            else { return false }
            // Uniquement les fichiers directement sous le scope (pas déjà imbriqués).
            return OrganizationPathUtils.normalize(item.parentRelativePath) == root
                && !isUnderProtected(item.relativePath, protected: protectedPaths)
        }

        if rootFiles.isEmpty {
            let anyFiles = inventory.items.contains { !$0.isDirectory }
            if !anyFiles {
                throw OrganizationEngineError.emptyFolder
            }
            throw OrganizationEngineError.alreadyOrganized
        }

        var moves: [OrganizationMove] = []
        var dirs = Set<String>()
        let hint = (instruction ?? "").lowercased()

        for file in rootFiles {
            let cat = categorize(file: file, instructionHint: hint)
            let destFolder = OrganizationPathUtils.join(root, cat.folderName)
            let dest = OrganizationPathUtils.join(destFolder, file.name)
            dirs.insert(destFolder)

            let needsReview = cat.confidence < OrganizationConfidence.autoExecuteMinimum
            moves.append(
                OrganizationMove(
                    sourceRelativePath: file.relativePath,
                    destinationRelativePath: dest,
                    operation: .move,
                    confidence: cat.confidence,
                    reason: cat.reason,
                    sourceFileId: file.fileId,
                    sourceIsDirectory: false,
                    needsReview: needsReview,
                    excluded: false
                )
            )
        }

        let autoCount = moves.filter { !$0.needsReview }.count
        let reviewCount = moves.filter(\.needsReview).count
        let avgConf = moves.isEmpty
            ? 0
            : moves.map(\.confidence).reduce(0, +) / Double(moves.count)

        var warnings: [String] = []
        if reviewCount > 0 {
            warnings.append("\(reviewCount) fichier\(reviewCount > 1 ? "s" : "") à revoir avant exécution automatique.")
        }
        if !protected.isEmpty {
            warnings.append("\(protected.filter { $0.level == .protected }.count) structure(s) protégée(s) laissée(s) intacte(s).")
        }
        warnings.append("Aucune suppression : seuls des déplacements et créations de dossiers.")

        let summary = "Proposition heuristique : \(autoCount) déplacement\(autoCount > 1 ? "s" : "") automatique\(autoCount > 1 ? "s" : ""), \(reviewCount) à revoir. Dossiers : \(dirs.sorted().map { OrganizationPathUtils.basename(of: $0) }.joined(separator: ", "))."

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
            confidence: avgConf,
            userInstruction: instruction
        )
    }

    private struct Category {
        let folderName: String
        let confidence: Double
        let reason: String
    }

    private static func categorize(file: OrganizationInventoryItem, instructionHint: String) -> Category {
        let name = file.name.lowercased()
        let ext = file.extensionLower
        let stem = name.replacingOccurrences(of: ".\(ext)", with: ext.isEmpty ? "" : "")

        if matchesAny(stem, ["facture", "invoice", "receipt", "reçu", "recu", "avoir", "devis"])
            || instructionHint.contains("facture") {
            return .init(folderName: "Factures", confidence: 0.88, reason: "Nom évoquant une facture / reçu")
        }
        if matchesAny(stem, ["contrat", "contract", "accord", "nda", "bail", "avenant"])
            || instructionHint.contains("contrat") {
            return .init(folderName: "Contrats", confidence: 0.86, reason: "Nom évoquant un contrat")
        }
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp", "raw", "dng"].contains(ext)
            || instructionHint.contains("image") || instructionHint.contains("photo") {
            return .init(folderName: "Images", confidence: 0.9, reason: "Extension image")
        }
        if matchesAny(stem, ["voyage", "travel", "hotel", "vol", "flight", "billet", "boarding", "itinéraire", "itineraire", "reservation", "réservation"])
            || instructionHint.contains("voyage") {
            return .init(folderName: "Voyages", confidence: 0.82, reason: "Nom évoquant un voyage")
        }
        if ["pdf"].contains(ext) && matchesAny(stem, ["ticket", "pass", "booking"]) {
            return .init(folderName: "Voyages", confidence: 0.75, reason: "PDF de voyage probable")
        }

        return .init(
            folderName: "A classer",
            confidence: 0.55,
            reason: "Catégorie incertaine — revue recommandée"
        )
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
