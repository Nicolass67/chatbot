import Foundation

// MARK: - Scope

enum OrganizationScope: Hashable, Sendable, Codable {
    case root(rootId: String, relativePath: String, displayName: String)
    case selectedFiles(rootId: String, relativePath: String, fileIds: [String], displayName: String)

    var rootId: String {
        switch self {
        case .root(let id, _, _), .selectedFiles(let id, _, _, _): return id
        }
    }

    var relativePath: String {
        switch self {
        case .root(_, let path, _), .selectedFiles(_, let path, _, _): return path
        }
    }

    var displayName: String {
        switch self {
        case .root(_, _, let name), .selectedFiles(_, _, _, let name): return name
        }
    }
}

extension OrganizationScope: Identifiable {
    var id: String {
        switch self {
        case .root(let rootId, let path, let name):
            return "root|\(rootId)|\(path)|\(name)"
        case .selectedFiles(let rootId, let path, let ids, let name):
            return "sel|\(rootId)|\(path)|\(ids.joined(separator: ","))|\(name)"
        }
    }
}

// MARK: - Inventory

struct OrganizationInventoryItem: Hashable, Sendable, Codable, Identifiable {
    var id: String { relativePath }
    let fileId: String?
    let name: String
    let relativePath: String
    let isDirectory: Bool
    let extensionLower: String
    let sizeBytes: Int
    let mtimeMs: Int?
    let parentRelativePath: String
    let depth: Int
}

struct OrganizationInventory: Sendable {
    let scope: OrganizationScope
    let items: [OrganizationInventoryItem]
    let scannedAt: Date

    var fileCount: Int { items.filter { !$0.isDirectory }.count }
    var folderCount: Int { items.filter(\.isDirectory).count }
}

// MARK: - Protection

enum OrganizationProtectionLevel: String, Sendable, Codable, Hashable {
    case normal
    case review
    case protected
}

struct ProtectedStructure: Hashable, Sendable, Codable, Identifiable {
    var id: String { relativePath }
    let relativePath: String
    let name: String
    let level: OrganizationProtectionLevel
    let reason: String
    let manual: Bool
}

// MARK: - Plan

enum OrganizationOperation: String, Sendable, Codable, Hashable {
    case move
}

struct OrganizationMove: Hashable, Sendable, Codable, Identifiable {
    var id: String { sourceRelativePath }
    var sourceRelativePath: String
    var destinationRelativePath: String
    var operation: OrganizationOperation
    var confidence: Double
    var reason: String
    var sourceFileId: String?
    var sourceIsDirectory: Bool
    var needsReview: Bool
    var excluded: Bool
}

struct OrganizationConflict: Hashable, Sendable, Codable, Identifiable {
    var id: String { "\(sourceRelativePath)->\(destinationRelativePath)" }
    let sourceRelativePath: String
    let destinationRelativePath: String
    let message: String
}

struct OrganizationPlan: Hashable, Sendable, Codable, Identifiable {
    var id: String
    var rootId: String
    var rootRelativePath: String
    var createdAt: Date
    var summary: String
    var protectedStructures: [ProtectedStructure]
    var proposedDirectories: [String]
    var moves: [OrganizationMove]
    var warnings: [String]
    var conflicts: [OrganizationConflict]
    var confidence: Double
    var userInstruction: String?

    var executableMoves: [OrganizationMove] {
        moves.filter { !$0.excluded && !$0.needsReview && $0.operation == .move }
    }

    var reviewMoves: [OrganizationMove] {
        moves.filter { $0.needsReview && !$0.excluded }
    }
}

enum OrganizationConfidence {
    static let autoExecuteMinimum: Double = 0.72
}

// MARK: - Workflow

enum OrganizationPhase: String, Sendable, Hashable {
    case idle
    case inventorying
    case analyzing
    case proposing
    case editingProposal
    case validating
    case readyForApproval
    case executing
    case completed
    case partiallyCompleted
    case failed
    case rolledBack
}

struct OrganizationExecutionItemResult: Hashable, Sendable, Codable, Identifiable {
    var id: String { sourceRelativePath }
    let sourceRelativePath: String
    let destinationRelativePath: String
    let success: Bool
    let errorMessage: String?
}

struct OrganizationExecutionResult: Hashable, Sendable, Codable, Identifiable {
    let id: String
    let planId: String
    let rootId: String
    let rootRelativePath: String
    let startedAt: Date
    let finishedAt: Date
    let items: [OrganizationExecutionItemResult]
    let cancelled: Bool

    var succeededCount: Int { items.filter(\.success).count }
    var failedCount: Int { items.filter { !$0.success }.count }
    var isPartial: Bool { succeededCount > 0 && failedCount > 0 }
    var isFullSuccess: Bool { failedCount == 0 && succeededCount > 0 && !cancelled }
}

struct OrganizationRollbackManifest: Hashable, Sendable, Codable, Identifiable {
    var id: String { executionId }
    let executionId: String
    let planId: String
    let rootId: String
    let rootRelativePath: String
    let timestamp: Date
    let moves: [MovePair]

    struct MovePair: Codable, Hashable {
        let from: String
        let to: String
    }
}

enum OrganizationValidationError: Error, LocalizedError, Equatable, Hashable {
    case emptyPlan
    case unknownOperation(String)
    case sourceOutsideRoot(String)
    case destinationOutsideRoot(String)
    case pathTraversal(String)
    case protectedSource(String)
    case sourceEqualsDestination(String)
    case duplicateSource(String)
    case conflictingDestinations(String)
    case collision(String)
    case contradictoryMoves(String)
    case missingSource(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .emptyPlan: return "Aucun déplacement à valider."
        case .unknownOperation(let o): return "Opération non autorisée : \(o)."
        case .sourceOutsideRoot(let p): return "Source hors périmètre : \(p)."
        case .destinationOutsideRoot(let p): return "Destination hors périmètre : \(p)."
        case .pathTraversal(let p): return "Chemin non sécurisé : \(p)."
        case .protectedSource(let p): return "Structure protégée : \(p)."
        case .sourceEqualsDestination(let p): return "Source et destination identiques : \(p)."
        case .duplicateSource(let p): return "Source dupliquée dans le plan : \(p)."
        case .conflictingDestinations(let p): return "Plusieurs sources vers la même destination : \(p)."
        case .collision(let p): return "Collision à destination : \(p)."
        case .contradictoryMoves(let p): return "Déplacements contradictoires : \(p)."
        case .missingSource(let p): return "Source introuvable : \(p)."
        case .invalidPath(let p): return "Chemin invalide : \(p)."
        }
    }
}

/// Wrapper `Error` pour `Result` — `[OrganizationValidationError]` seul ne conforme pas à `Error`.
struct OrganizationValidationFailure: Error, Equatable, Hashable, LocalizedError {
    let errors: [OrganizationValidationError]

    var errorDescription: String? {
        errors.first?.errorDescription ?? "Plan rejeté par le validateur."
    }
}

enum OrganizationEngineError: Error, LocalizedError {
    case emptyFolder
    case alreadyOrganized
    case modelUnavailable
    case invalidAIResponse(String)
    case validationFailed([OrganizationValidationError])
    case cancelled
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyFolder: return "Ce dossier est déjà vide."
        case .alreadyOrganized: return "Cette organisation semble déjà cohérente. Aucun déplacement recommandé."
        case .modelUnavailable: return "Aucun modèle utilisable pour l’analyse. Réessaie quand l’assistant est prêt."
        case .invalidAIResponse(let m): return "Proposition IA invalide : \(m)"
        case .validationFailed(let errs):
            return errs.first?.errorDescription ?? "Plan rejeté par le validateur."
        case .cancelled: return "Réorganisation arrêtée."
        case .executionFailed(let m): return m
        }
    }
}
