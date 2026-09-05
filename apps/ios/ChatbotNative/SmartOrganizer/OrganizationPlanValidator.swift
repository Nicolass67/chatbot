import Foundation

enum OrganizationPlanValidator {
    static func validate(
        plan: OrganizationPlan,
        inventory: OrganizationInventory,
        existingRelativePaths: Set<String>
    ) -> Result<OrganizationPlan, OrganizationValidationFailure> {
        var errors: [OrganizationValidationError] = []
        let root = OrganizationPathUtils.normalize(plan.rootRelativePath)
        let protected = Set(
            plan.protectedStructures
                .filter { $0.level == .protected }
                .map { OrganizationPathUtils.normalize($0.relativePath) }
        )
        let inventoryByPath = Dictionary(uniqueKeysWithValues: inventory.items.map {
            (OrganizationPathUtils.normalize($0.relativePath), $0)
        })

        var sourcesSeen = Set<String>()
        var destinationsSeen = Set<String>()
        var normalizedMoves: [OrganizationMove] = []
        let parentNormalized = normalizeParentChild(moves: plan.moves)

        for raw in parentNormalized {
            if raw.operation != .move {
                errors.append(.unknownOperation(String(describing: raw.operation)))
                continue
            }
            let source = OrganizationPathUtils.normalize(raw.sourceRelativePath)
            let dest = OrganizationPathUtils.normalize(raw.destinationRelativePath)

            if OrganizationPathUtils.containsTraversal(raw.sourceRelativePath)
                || OrganizationPathUtils.containsTraversal(raw.destinationRelativePath) {
                errors.append(.pathTraversal(raw.sourceRelativePath))
                continue
            }
            if !OrganizationPathUtils.isWithin(root: root, path: source) {
                errors.append(.sourceOutsideRoot(source))
                continue
            }
            if !OrganizationPathUtils.isWithin(root: root, path: dest) {
                errors.append(.destinationOutsideRoot(dest))
                continue
            }
            if source.isEmpty || dest.isEmpty {
                errors.append(.invalidPath(source.isEmpty ? dest : source))
                continue
            }
            if source == dest {
                errors.append(.sourceEqualsDestination(source))
                continue
            }
            if sourcesSeen.contains(source) {
                errors.append(.duplicateSource(source))
                continue
            }
            if destinationsSeen.contains(dest) {
                errors.append(.conflictingDestinations(dest))
                continue
            }
            if inventoryByPath[source] == nil && !existingRelativePaths.contains(source) {
                errors.append(.missingSource(source))
                continue
            }
            if isProtected(source, protected: protected) {
                errors.append(.protectedSource(source))
                continue
            }
            if existingRelativePaths.contains(dest) {
                let destIsBeingMoved = parentNormalized.contains {
                    OrganizationPathUtils.normalize($0.sourceRelativePath) == dest
                }
                if !destIsBeingMoved {
                    errors.append(.collision(dest))
                    continue
                }
            }

            sourcesSeen.insert(source)
            destinationsSeen.insert(dest)
            var move = raw
            move.sourceRelativePath = source
            move.destinationRelativePath = dest
            move.sourceFileId = raw.sourceFileId ?? inventoryByPath[source]?.fileId
            move.sourceIsDirectory = raw.sourceIsDirectory || (inventoryByPath[source]?.isDirectory ?? false)
            move.needsReview = raw.needsReview || raw.confidence < OrganizationConfidence.autoExecuteMinimum
            normalizedMoves.append(move)
        }

        for m in normalizedMoves where normalizedMoves.contains(where: {
            $0.sourceRelativePath == m.destinationRelativePath
                && $0.destinationRelativePath == m.sourceRelativePath
        }) {
            errors.append(.contradictoryMoves(m.sourceRelativePath))
        }

        guard errors.isEmpty else { return .failure(OrganizationValidationFailure(errors: errors)) }

        var next = plan
        next.moves = normalizedMoves
        if next.executableMoves.isEmpty && next.reviewMoves.isEmpty {
            return .failure(OrganizationValidationFailure(errors: [.emptyPlan]))
        }
        return .success(next)
    }

    private static func isProtected(_ path: String, protected: Set<String>) -> Bool {
        let p = OrganizationPathUtils.normalize(path)
        if protected.contains(p) { return true }
        return protected.contains { p.hasPrefix($0 + "/") }
    }

    static func normalizeParentChild(moves: [OrganizationMove]) -> [OrganizationMove] {
        let dirMoves = moves.filter(\.sourceIsDirectory).map {
            OrganizationPathUtils.normalize($0.sourceRelativePath)
        }
        return moves.filter { move in
            let src = OrganizationPathUtils.normalize(move.sourceRelativePath)
            return !dirMoves.contains { parent in
                src != parent && src.hasPrefix(parent + "/")
            }
        }
    }
}
