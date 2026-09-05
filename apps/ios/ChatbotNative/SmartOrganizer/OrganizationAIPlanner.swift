import Foundation

enum OrganizationAIPlanner {
    /// Appelle `POST api/files/organize/plan` et parse la réponse en `OrganizationPlan`.
    static func propose(
        client: APIClient,
        inventory: OrganizationInventory,
        protected: [ProtectedStructure],
        instruction: String?
    ) async throws -> OrganizationPlan {
        let root = OrganizationPathUtils.normalize(inventory.scope.relativePath)
        let itemsPayload: [[String: Any]] = inventory.items.prefix(800).map { item in
            var dict: [String: Any] = [
                "name": item.name,
                "relativePath": item.relativePath,
                "isDirectory": item.isDirectory,
                "extension": item.extensionLower,
                "sizeBytes": item.sizeBytes,
                "parentRelativePath": item.parentRelativePath,
                "depth": item.depth,
            ]
            if let fileId = item.fileId { dict["fileId"] = fileId }
            if let mtime = item.mtimeMs { dict["mtimeMs"] = mtime }
            return dict
        }
        let protectedPaths = protected
            .filter { $0.level == .protected }
            .map(\.relativePath)

        let data: Data
        do {
            data = try await client.proposeOrganizationPlan(
                rootId: inventory.scope.rootId,
                rootRelativePath: root,
                items: itemsPayload,
                protectedPaths: protectedPaths,
                instruction: instruction
            )
        } catch let error as APIClientError {
            switch error {
            case .http(let code, _) where code == 503 || code == 502:
                throw OrganizationEngineError.modelUnavailable
            default:
                throw OrganizationEngineError.invalidAIResponse(error.localizedDescription)
            }
        } catch {
            throw OrganizationEngineError.invalidAIResponse(error.localizedDescription)
        }

        return try parsePlan(
            data: data,
            inventory: inventory,
            protected: protected,
            instruction: instruction
        )
    }

    static func parsePlan(
        data: Data,
        inventory: OrganizationInventory,
        protected: [ProtectedStructure],
        instruction: String?
    ) throws -> OrganizationPlan {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OrganizationEngineError.invalidAIResponse("JSON racine invalide")
        }

        let summary = (obj["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let proposedDirectories = (obj["proposedDirectories"] as? [String]) ?? []
        let warnings = (obj["warnings"] as? [String]) ?? []
        let rawMoves = (obj["moves"] as? [[String: Any]]) ?? []

        if summary.isEmpty && rawMoves.isEmpty {
            throw OrganizationEngineError.invalidAIResponse("Réponse vide")
        }

        let byPath = Dictionary(uniqueKeysWithValues: inventory.items.map {
            (OrganizationPathUtils.normalize($0.relativePath), $0)
        })

        var moves: [OrganizationMove] = []
        for raw in rawMoves {
            guard let source = raw["source"] as? String ?? raw["sourceRelativePath"] as? String,
                  let dest = raw["destination"] as? String ?? raw["destinationRelativePath"] as? String
            else { continue }
            let confidence = (raw["confidence"] as? Double)
                ?? (raw["confidence"] as? NSNumber)?.doubleValue
                ?? 0.5
            let reason = (raw["reason"] as? String) ?? "Proposition IA"
            let srcNorm = OrganizationPathUtils.normalize(source)
            let destNorm = OrganizationPathUtils.normalize(dest)
            let item = byPath[srcNorm]
            moves.append(
                OrganizationMove(
                    sourceRelativePath: srcNorm,
                    destinationRelativePath: destNorm,
                    operation: .move,
                    confidence: confidence,
                    reason: reason,
                    sourceFileId: (raw["sourceFileId"] as? String) ?? item?.fileId,
                    sourceIsDirectory: (raw["sourceIsDirectory"] as? Bool) ?? (item?.isDirectory ?? false),
                    needsReview: confidence < OrganizationConfidence.autoExecuteMinimum,
                    excluded: false
                )
            )
        }

        if moves.isEmpty {
            throw OrganizationEngineError.invalidAIResponse("Aucun déplacement dans la réponse IA")
        }

        let avg = moves.map(\.confidence).reduce(0, +) / Double(moves.count)
        return OrganizationPlan(
            id: UUID().uuidString,
            rootId: inventory.scope.rootId,
            rootRelativePath: OrganizationPathUtils.normalize(inventory.scope.relativePath),
            createdAt: Date(),
            summary: summary.isEmpty ? "Proposition IA (\(moves.count) déplacements)" : summary,
            protectedStructures: protected,
            proposedDirectories: proposedDirectories.map(OrganizationPathUtils.normalize),
            moves: moves,
            warnings: warnings,
            conflicts: [],
            confidence: avg,
            userInstruction: instruction
        )
    }
}
