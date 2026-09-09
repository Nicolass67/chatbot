import Foundation

/// Cycle de vie d’un modèle local (téléchargement → chargement → génération).
enum LocalModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double)
    case verifying
    case installed
    case loading
    case ready
    case generating
    case unloading
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .loading, .generating, .unloading:
            return true
        default:
            return false
        }
    }

    var statusLabel: String {
        switch self {
        case .notInstalled:
            return "Non installé"
        case .downloading(let progress):
            return String(format: "Téléchargement… %.0f %%", progress * 100)
        case .verifying:
            return "Vérification…"
        case .installed:
            return "Installé"
        case .loading:
            return "Chargement…"
        case .ready:
            return "Prêt"
        case .generating:
            return "Génération…"
        case .unloading:
            return "Déchargement…"
        case .failed(let message):
            return "Erreur — \(message)"
        }
    }
}

/// Préférence utilisateur pour le routage PC distant vs IA locale.
/// Ne bascule **jamais** automatiquement le modèle LM Studio du PC.
enum ExecutionModePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case forceRemote
    case forceLocal

    var id: String { rawValue }

    static let appStorageKey = "localAI.executionModePreference"

    var title: String {
        switch self {
        case .automatic: return "Automatique"
        case .forceRemote: return "Toujours distant (PC)"
        case .forceLocal: return "Toujours local"
        }
    }

    var helpText: String {
        switch self {
        case .automatic:
            return "Utilise le PC quand il est joignable ; bascule sur l’IA locale uniquement si le PC est indisponible et le modèle prêt."
        case .forceRemote:
            return "Force l’assistant distant (LM Studio sur le PC). Aucune génération locale."
        case .forceLocal:
            return "Force l’IA locale sur l’iPhone. Indépendant du modèle chargé sur le PC."
        }
    }
}

/// Mode effectif résolu (après préférence + état PC + modèle).
enum EffectiveExecutionMode: String, Sendable {
    case remote
    case local
}
