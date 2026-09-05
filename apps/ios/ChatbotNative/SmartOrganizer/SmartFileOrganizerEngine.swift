import Foundation
import Observation

@MainActor
@Observable
final class SmartFileOrganizerEngine {
    var phase: OrganizationPhase = .idle
    var progressText: String = ""
    var progressValue: Double = 0
    var inventory: OrganizationInventory?
    var plan: OrganizationPlan?
    var executionResult: OrganizationExecutionResult?
    var lastError: String?
    var cancelRequested = false

    private var analysisTask: Task<Void, Never>?
    private var activeScope: OrganizationScope?

    func startAnalysis(scope: OrganizationScope, client: APIClient) {
        cancelRequested = false
        activeScope = scope
        plan = nil
        executionResult = nil
        lastError = nil
        inventory = nil
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.runAnalysis(scope: scope, client: client, instruction: nil)
        }
    }

    func refine(instruction: String, client: APIClient) {
        guard let scope = activeScope ?? inventory?.scope else { return }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancelRequested = false
        lastError = nil
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.runAnalysis(scope: scope, client: client, instruction: trimmed)
        }
    }

    func toggleExclude(moveId: String) {
        guard var plan else { return }
        if let idx = plan.moves.firstIndex(where: { $0.id == moveId }) {
            plan.moves[idx].excluded.toggle()
            self.plan = plan
            if phase == .readyForApproval || phase == .editingProposal {
                phase = .editingProposal
            }
        }
    }

    func protectCurrentFolder(rootId: String, path: String, always: Bool) {
        OrganizationProtectionStore.shared.protect(rootId: rootId, path: path, always: always)
        progressText = always ? "Dossier toujours protégé." : "Dossier protégé pour cette session."
    }

    func requestCancel() {
        cancelRequested = true
        if phase == .inventorying || phase == .analyzing || phase == .proposing || phase == .validating {
            phase = .failed
            lastError = OrganizationEngineError.cancelled.errorDescription
        }
    }

    func approveAndExecute(client: APIClient) async {
        guard let plan, phase == .readyForApproval || phase == .editingProposal else { return }
        cancelRequested = false
        phase = .executing
        progressText = "Exécution…"
        progressValue = 0
        lastError = nil

        let started = Date()
        let executionId = UUID().uuidString
        var itemResults: [OrganizationExecutionItemResult] = []
        var rollbackPairs: [OrganizationRollbackManifest.MovePair] = []
        var cancelled = false

        let dirs = plan.proposedDirectories.sorted {
            OrganizationPathUtils.depth(of: $0) < OrganizationPathUtils.depth(of: $1)
        }
        for (i, dir) in dirs.enumerated() {
            if cancelRequested {
                cancelled = true
                break
            }
            progressText = "Création du dossier \(OrganizationPathUtils.basename(of: dir))…"
            progressValue = Double(i) / Double(max(dirs.count + plan.executableMoves.count, 1))
            do {
                let proposal = try await client.proposeCreateDirectory(
                    rootId: plan.rootId,
                    destRelativePath: dir
                )
                try await client.confirmFilesAction(
                    actionId: proposal.actionId,
                    confirmationToken: proposal.confirmationToken,
                    confirm: true
                )
            } catch {
                // Dossier peut déjà exister — on continue.
                let msg = error.localizedDescription.lowercased()
                if !(msg.contains("existe") || msg.contains("already") || msg.contains("eexist")) {
                    lastError = "Création dossier « \(dir) » : \(error.localizedDescription)"
                }
            }
        }

        let moves = plan.executableMoves
        for (i, move) in moves.enumerated() {
            if cancelRequested {
                cancelled = true
                break
            }
            progressText = "Déplacement \(i + 1)/\(moves.count)…"
            progressValue = Double(dirs.count + i) / Double(max(dirs.count + moves.count, 1))

            guard let fileId = move.sourceFileId, !fileId.isEmpty else {
                itemResults.append(.init(
                    sourceRelativePath: move.sourceRelativePath,
                    destinationRelativePath: move.destinationRelativePath,
                    success: false,
                    errorMessage: "Identifiant fichier manquant"
                ))
                continue
            }

            do {
                let proposal = try await client.proposeMoveFile(
                    sourceFileId: fileId,
                    destRootId: plan.rootId,
                    destRelativePath: move.destinationRelativePath
                )
                try await client.confirmFilesAction(
                    actionId: proposal.actionId,
                    confirmationToken: proposal.confirmationToken,
                    confirm: true
                )
                itemResults.append(.init(
                    sourceRelativePath: move.sourceRelativePath,
                    destinationRelativePath: move.destinationRelativePath,
                    success: true,
                    errorMessage: nil
                ))
                // Rollback : destination → source
                rollbackPairs.append(.init(from: move.destinationRelativePath, to: move.sourceRelativePath))
            } catch {
                itemResults.append(.init(
                    sourceRelativePath: move.sourceRelativePath,
                    destinationRelativePath: move.destinationRelativePath,
                    success: false,
                    errorMessage: error.localizedDescription
                ))
            }
        }

        let finished = Date()
        let result = OrganizationExecutionResult(
            id: executionId,
            planId: plan.id,
            rootId: plan.rootId,
            rootRelativePath: plan.rootRelativePath,
            startedAt: started,
            finishedAt: finished,
            items: itemResults,
            cancelled: cancelled
        )
        executionResult = result
        progressValue = 1

        if !rollbackPairs.isEmpty {
            let manifest = OrganizationRollbackManifest(
                executionId: executionId,
                planId: plan.id,
                rootId: plan.rootId,
                rootRelativePath: plan.rootRelativePath,
                timestamp: finished,
                moves: rollbackPairs
            )
            OrganizationHistoryStore.shared.save(manifest)
        }

        if cancelled {
            phase = .partiallyCompleted
            progressText = "Réorganisation interrompue (\(result.succeededCount) effectué\(result.succeededCount > 1 ? "s" : ""))."
        } else if result.isFullSuccess {
            phase = .completed
            progressText = "Réorganisation terminée."
        } else if result.succeededCount > 0 {
            phase = .partiallyCompleted
            progressText = "Réorganisation partielle."
        } else {
            phase = .failed
            lastError = result.items.first(where: { !$0.success })?.errorMessage
                ?? OrganizationEngineError.executionFailed("Aucun déplacement réussi.").errorDescription
            progressText = "Échec de l’exécution."
        }
    }

    func undoLast(client: APIClient) async {
        guard let manifest = OrganizationHistoryStore.shared.last else {
            lastError = "Aucun historique d’annulation."
            return
        }
        phase = .executing
        progressText = "Annulation…"
        progressValue = 0
        cancelRequested = false
        var ok = 0
        let total = max(manifest.moves.count, 1)

        for (i, pair) in manifest.moves.enumerated() {
            if cancelRequested { break }
            progressText = "Annulation \(i + 1)/\(manifest.moves.count)…"
            progressValue = Double(i) / Double(total)
            do {
                let fileId = try await resolveFileId(
                    client: client,
                    rootId: manifest.rootId,
                    relativePath: pair.from
                )
                let proposal = try await client.proposeMoveFile(
                    sourceFileId: fileId,
                    destRootId: manifest.rootId,
                    destRelativePath: pair.to
                )
                try await client.confirmFilesAction(
                    actionId: proposal.actionId,
                    confirmationToken: proposal.confirmationToken,
                    confirm: true
                )
                ok += 1
            } catch {
                lastError = "Annulation « \(pair.from) » : \(error.localizedDescription)"
            }
        }

        OrganizationHistoryStore.shared.remove(manifest.executionId)
        progressValue = 1
        if ok == manifest.moves.count {
            phase = .rolledBack
            progressText = "Annulation terminée."
        } else if ok > 0 {
            phase = .partiallyCompleted
            progressText = "Annulation partielle (\(ok)/\(manifest.moves.count))."
        } else {
            phase = .failed
            progressText = "Échec de l’annulation."
        }
    }

    // MARK: - Analysis pipeline

    private func runAnalysis(scope: OrganizationScope, client: APIClient, instruction: String?) async {
        do {
            phase = .inventorying
            progressText = "Inventaire…"
            progressValue = 0.05
            let inv = try await OrganizationInventoryService.build(
                client: client,
                scope: scope,
                cancelRequested: { [weak self] in self?.cancelRequested == true },
                onProgress: { [weak self] text, value in
                    self?.progressText = text
                    self?.progressValue = value * 0.35
                }
            )
            if cancelRequested { throw OrganizationEngineError.cancelled }
            inventory = inv

            phase = .analyzing
            progressText = "Détection des structures protégées…"
            progressValue = 0.4
            let manual = OrganizationProtectionStore.shared.manualSet(rootId: scope.rootId)
            let protected = ProtectedStructureDetector.detect(in: inv, manualProtected: manual)

            phase = .proposing
            progressText = "Analyse IA…"
            progressValue = 0.55
            var draft: OrganizationPlan
            do {
                draft = try await OrganizationAIPlanner.propose(
                    client: client,
                    inventory: inv,
                    protected: protected,
                    instruction: instruction
                )
            } catch let aiError as OrganizationEngineError {
                switch aiError {
                case .modelUnavailable, .invalidAIResponse:
                    progressText = "Analyse heuristique (repli)…"
                    progressValue = 0.65
                    draft = try OrganizationHeuristicPlanner.propose(
                        inventory: inv,
                        protected: protected,
                        instruction: instruction
                    )
                default:
                    throw aiError
                }
            }

            if cancelRequested { throw OrganizationEngineError.cancelled }

            phase = .validating
            progressText = "Validation du plan…"
            progressValue = 0.85
            let existing = Set(inv.items.map { OrganizationPathUtils.normalize($0.relativePath) })
            switch OrganizationPlanValidator.validate(
                plan: draft,
                inventory: inv,
                existingRelativePaths: existing
            ) {
            case .success(let validated):
                plan = validated
                phase = .readyForApproval
                progressText = "Prêt pour validation"
                progressValue = 1
            case .failure(let failure):
                // Si l’IA a produit un plan invalide, retenter l’heuristique une fois.
                if instruction == nil || plan == nil {
                    let heuristic = try OrganizationHeuristicPlanner.propose(
                        inventory: inv,
                        protected: protected,
                        instruction: instruction
                    )
                    switch OrganizationPlanValidator.validate(
                        plan: heuristic,
                        inventory: inv,
                        existingRelativePaths: existing
                    ) {
                    case .success(let validated):
                        plan = validated
                        phase = .readyForApproval
                        progressText = "Prêt pour validation (heuristique)"
                        progressValue = 1
                    case .failure(let failure2):
                        throw OrganizationEngineError.validationFailed(failure2.errors)
                    }
                } else {
                    throw OrganizationEngineError.validationFailed(failure.errors)
                }
            }
        } catch let error as OrganizationEngineError {
            if case .cancelled = error {
                phase = .failed
            } else if case .alreadyOrganized = error {
                phase = .failed
            } else if case .emptyFolder = error {
                phase = .failed
            } else {
                phase = .failed
            }
            lastError = error.errorDescription
            progressText = lastError ?? "Échec"
        } catch is CancellationError {
            phase = .failed
            lastError = OrganizationEngineError.cancelled.errorDescription
            progressText = lastError ?? "Annulé"
        } catch {
            phase = .failed
            lastError = error.localizedDescription
            progressText = lastError ?? "Échec"
        }
    }

    private func resolveFileId(client: APIClient, rootId: String, relativePath: String) async throws -> String {
        let parent = OrganizationPathUtils.parent(of: relativePath)
        let name = OrganizationPathUtils.basename(of: relativePath)
        let list = try await client.listFiles(rootId: rootId, path: parent)
        if let hit = list.entries.first(where: {
            OrganizationPathUtils.normalize($0.relativePath) == OrganizationPathUtils.normalize(relativePath)
                || ($0.name ?? "") == name
        }), let fileId = hit.fileId, !fileId.isEmpty {
            return fileId
        }
        throw OrganizationEngineError.executionFailed("Fichier introuvable pour annulation : \(relativePath)")
    }
}

// MARK: - Notification bridge (assistant → browser)

extension Notification.Name {
    static let smartOrganizerRequest = Notification.Name("SmartOrganizerRequest")
}

enum SmartOrganizerRequestKeys {
    static let rootId = "rootId"
    static let path = "path"
    static let title = "title"
}
