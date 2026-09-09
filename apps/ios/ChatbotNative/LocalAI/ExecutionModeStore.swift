import Foundation
import Combine

/// Relie la préférence d’exécution, l’état du PC et le modèle local.
/// Ne bascule **jamais** automatiquement le modèle LM Studio du PC.
@MainActor
final class ExecutionModeStore: ObservableObject {
    static let shared = ExecutionModeStore()

    @Published private(set) var preference: ExecutionModePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: ExecutionModePreference.appStorageKey)
            refreshDerived()
        }
    }

    @Published private(set) var bannerMessage: String?
    @Published private(set) var showsLocalBanner: Bool = false

    private weak var infrastructure: InfrastructureStore?
    private weak var models: LocalModelManager?

    init() {
        let raw = UserDefaults.standard.string(forKey: ExecutionModePreference.appStorageKey)
        preference = ExecutionModePreference(rawValue: raw ?? "") ?? .automatic
    }

    func setPreference(_ value: ExecutionModePreference) {
        preference = value
    }

    func bind(infrastructure: InfrastructureStore, models: LocalModelManager = .shared) {
        self.infrastructure = infrastructure
        self.models = models
        refreshDerived()
    }

    /// Mode effectif après préférence + dispo PC + modèle local.
    var effectiveMode: EffectiveExecutionMode {
        switch preference {
        case .forceRemote:
            return .remote
        case .forceLocal:
            return models?.isReady == true ? .local : .remote
        case .automatic:
            return shouldUseLocalLLM ? .local : .remote
        }
    }

    /// PC offline (confirmé) + modèle prêt → fallback local autorisé.
    var allowLocalFallback: Bool {
        guard let infra = infrastructure, let models else { return false }
        return infra.isPcConfirmedOffline && models.isReady
    }

    var shouldUseLocalLLM: Bool {
        switch preference {
        case .forceLocal:
            return models?.isReady == true
        case .forceRemote:
            return false
        case .automatic:
            return allowLocalFallback
        }
    }

    var statusLabel: String {
        let modelReady = models?.isReady == true
        let pcOnline = infrastructure?.isPcOnline == true
        let pcOffline = infrastructure?.isPcConfirmedOffline == true

        switch preference {
        case .forceLocal:
            if modelReady {
                return "Mode local — Qwen3 1.7B"
            }
            return "Mode local — installez l’IA locale"
        case .forceRemote:
            if pcOnline {
                return "PC connecté — IA distante"
            }
            return "PC indisponible — installez l’IA locale"
        case .automatic:
            if shouldUseLocalLLM {
                return "Mode local — Qwen3 1.7B"
            }
            if pcOnline {
                return "PC connecté — IA distante"
            }
            if pcOffline && !modelReady {
                return "PC indisponible — installez l’IA locale"
            }
            if modelReady {
                return "Mode local — Qwen3 1.7B"
            }
            return "PC indisponible — installez l’IA locale"
        }
    }

    func refreshDerived() {
        let local = shouldUseLocalLLM
        showsLocalBanner = local
        if local {
            bannerMessage = "IA locale active — indépendante du PC"
        } else if infrastructure?.isPcConfirmedOffline == true, models?.isReady != true {
            bannerMessage = "PC indisponible — installez l’IA locale"
            showsLocalBanner = true
        } else {
            bannerMessage = nil
            showsLocalBanner = false
        }
    }
}
