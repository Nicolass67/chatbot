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
        if value == .forceLocal {
            LocalModelManager.shared.requestAutoLoadIfNeeded(wantsLocalExecution: true)
        }
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

    /// Intention on-device (Toujours local) — **indépendante** de `isReady`.
    /// Sert au boot conversation locale / routage Chat-Mail sans exiger le PC.
    /// La génération réelle attend toujours un modèle prêt (`shouldUseLocalLLM` / load).
    var prefersOnDeviceAssistant: Bool {
        preference == .forceLocal || shouldUseLocalLLM
    }

    /// Ops réalisables en local : ne jamais router vers le PC sauf « Toujours PC ».
    /// Un modèle chargé + préférence auto compte comme local-capable.
    var routesLocalCapableOnDevice: Bool {
        if preference == .forceRemote { return false }
        if preference == .forceLocal { return true }
        if models?.isReady == true { return true }
        return shouldUseLocalLLM
    }

    var statusLabel: String {
        let modelReady = models?.isReady == true
        let pcOnline = infrastructure?.isPcOnline == true
        let pcOffline = infrastructure?.isPcConfirmedOffline == true
        let modelName = models?.activeDescriptor.displayName ?? "IA locale"

        switch preference {
        case .forceLocal:
            if modelReady {
                return "Mode local — \(modelName)"
            }
            return "Mode local — chargez un modèle"
        case .forceRemote:
            if pcOnline {
                return "PC connecté — IA distante"
            }
            return "PC indisponible — l’opération distante ne peut pas s’exécuter"
        case .automatic:
            if routesLocalCapableOnDevice && modelReady {
                return "Mode local — \(modelName)"
            }
            if pcOnline {
                return "PC connecté — IA distante"
            }
            if pcOffline && !modelReady {
                return "PC indisponible — installez l’IA locale"
            }
            if modelReady {
                return "Mode local — \(modelName)"
            }
            return "PC indisponible — installez l’IA locale"
        }
    }

    func refreshDerived() {
        let local = routesLocalCapableOnDevice && (models?.isReady == true || preference == .forceLocal)
        showsLocalBanner = local && models?.isReady == true
        if models?.isReady == true, preference != .forceRemote {
            bannerMessage = "IA locale active — indépendante du PC"
            showsLocalBanner = true
        } else if preference == .forceLocal {
            bannerMessage = "Mode local — chargez un modèle"
            showsLocalBanner = true
        } else if infrastructure?.isPcConfirmedOffline == true, models?.isReady != true {
            bannerMessage = "PC indisponible — installez l’IA locale"
            showsLocalBanner = true
        } else {
            bannerMessage = nil
            showsLocalBanner = false
        }
    }
}
