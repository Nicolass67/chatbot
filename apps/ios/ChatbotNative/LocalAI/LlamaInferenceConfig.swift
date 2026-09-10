import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Inference performance config (paramétrique, pas de gating features)

enum LlamaFlashAttentionMode: String, Sendable, Codable, Hashable, CaseIterable {
    case auto
    case enabled
    case disabled
}

/// Type du cache KV. `q8_0` divise la mémoire par deux pour un delta de
/// perplexité négligeable, mais impose Flash Attention : si le noyau Metal
/// correspondant manque, la création du contexte échoue et tout le modèle
/// retombe sur le CPU. En f16, un contexte de 4096 tient déjà en ~470 Mo pour
/// un 2B — la quantification n'achète rien qui vaille ce risque.
enum LlamaKVCacheType: String, Sendable, Codable, Hashable, CaseIterable {
    case f16
    case q8_0
    case q5_1
    case q4_0

    /// Octets par élément stocké (approx, hors overhead de bloc).
    var bytesPerElement: Double {
        switch self {
        case .f16: return 2.0
        case .q8_0: return 1.0625      // 32 poids q8 + scale f16
        case .q5_1: return 0.75
        case .q4_0: return 0.5625
        }
    }

    /// Quantifier le KV exige Flash Attention côté Metal.
    var requiresFlashAttention: Bool { self != .f16 }
}

/// Paramètres d'échantillonnage. Valeurs de référence : recommandations
/// officielles Qwen3 / Qwen3.5 en mode non-thinking.
///
/// L'ordre d'application est imposé par `LlamaContext` et n'est pas configurable :
/// `penalties → top_k → top_p → min_p → temp → dist`. Appliquer la température
/// avant les troncatures change leur sémantique et sort de la calibration du modèle.
struct LlamaSamplingConfig: Equatable, Sendable, Hashable, Codable {
    var temperature: Float
    var topP: Float
    /// 0 = désactivé. Qwen recommande 20.
    var topK: Int32
    /// 0 = désactivé. Qwen recommande 0 explicitement.
    var minP: Float
    /// Fenêtre des pénalités (tokens récents). 0 = pénalités désactivées.
    var penaltyLastN: Int32
    /// 1.0 = désactivé.
    var repeatPenalty: Float
    var frequencyPenalty: Float
    /// Qwen : « régler presence_penalty à 1.5 pour les modèles quantifiés ».
    /// 1.0 est le compromis retenu ici : au-delà, risque documenté de mélange
    /// de langues, rédhibitoire pour un assistant francophone.
    var presencePenalty: Float
    /// `LlamaSamplingConfig.randomSeed` = seed aléatoire à chaque génération,
    /// indispensable pour que « régénérer » produise une réponse différente.
    var seed: UInt32

    static let randomSeed: UInt32 = 0xFFFF_FFFF

    /// Qwen3.5 non-thinking : temp 0.7 / top_p 0.8 / top_k 20 / min_p 0.
    static let qwenInstruct = LlamaSamplingConfig(
        temperature: 0.7,
        topP: 0.8,
        topK: 20,
        minP: 0.0,
        penaltyLastN: 128,
        repeatPenalty: 1.05,
        frequencyPenalty: 0.0,
        presencePenalty: 1.0,
        seed: randomSeed
    )

    /// Qwen3.5 thinking : temp 0.6 / top_p 0.95 / top_k 20, sans presence penalty
    /// (elle dégrade les chaînes de raisonnement longues).
    static let qwenThinking = LlamaSamplingConfig(
        temperature: 0.6,
        topP: 0.95,
        topK: 20,
        minP: 0.0,
        penaltyLastN: 128,
        repeatPenalty: 1.05,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0,
        seed: randomSeed
    )

    /// Extraction structurée / JSON : quasi déterministe, la grammaire fait le reste.
    static let structured = LlamaSamplingConfig(
        temperature: 0.2,
        topP: 0.9,
        topK: 20,
        minP: 0.0,
        penaltyLastN: 0,
        repeatPenalty: 1.0,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0,
        seed: randomSeed
    )

    /// Réécriture de mail / résumé : factuel, peu créatif, sans répétition.
    static let factual = LlamaSamplingConfig(
        temperature: 0.4,
        topP: 0.85,
        topK: 20,
        minP: 0.0,
        penaltyLastN: 128,
        repeatPenalty: 1.05,
        frequencyPenalty: 0.0,
        presencePenalty: 0.6,
        seed: randomSeed
    )

    var usesPenalties: Bool {
        penaltyLastN > 0 && (repeatPenalty != 1.0 || frequencyPenalty != 0.0 || presencePenalty != 0.0)
    }
}

/// Paramètres llama.cpp / moteur — branchés via ExecutionProfile, pas via if Qwen/Gemma métier.
struct LlamaInferenceConfig: Equatable, Sendable, Hashable, Codable {
    /// -1 = toutes les couches GPU possibles ; 0 = CPU only.
    var nGpuLayers: Int32
    var preferMetal: Bool
    var nCtx: UInt32
    var nBatch: UInt32
    var nUbatch: UInt32
    /// `nil` = dérivé de `processorCount` (A15 ≈ 4 threads utiles).
    var nThreads: Int32?
    var nThreadsBatch: Int32?
    var flashAttention: LlamaFlashAttentionMode
    var useMmap: Bool
    /// Échantillonnage par défaut du profil. Surchargeable par génération.
    var sampling: LlamaSamplingConfig
    var kvCacheTypeK: LlamaKVCacheType
    var kvCacheTypeV: LlamaKVCacheType
    /// Contextes tentés dans l'ordre si l'allocation échoue (OOM / init nil).
    var contextLadder: [UInt32]
    /// Réutilisation du préfixe KV entre deux tours. Sans elle, chaque message
    /// re-préfille le prompt système + tout l'historique depuis zéro.
    var prefixReuseEnabled: Bool
    /// Décodage à vide après load : sort la compilation des pipelines Metal et
    /// le page-in des poids mmapés du chemin utilisateur.
    var warmupOnLoad: Bool
    /// Callback ggml d'observation GDN. Installe un eval callback sur tout le
    /// graphe → casse le batching. Diagnostic uniquement, jamais en release.
    var evalCallbackEnabled: Bool
    /// Plafond tokens image mtmd. Qwen conserve 192 via `a15Default`.
    var imageMaxTokens: Int32

    // Compat : anciens accès directs aux paramètres d'échantillonnage.
    var temperature: Float {
        get { sampling.temperature }
        set { sampling.temperature = newValue }
    }
    var topP: Float {
        get { sampling.topP }
        set { sampling.topP = newValue }
    }
    var topK: Int32 {
        get { sampling.topK }
        set { sampling.topK = newValue }
    }

    /// Flash Attention effective : forcée si le KV est quantifié.
    var effectiveFlashAttention: LlamaFlashAttentionMode {
        if kvCacheTypeK.requiresFlashAttention || kvCacheTypeV.requiresFlashAttention {
            return flashAttention == .disabled ? .enabled : flashAttention
        }
        return flashAttention
    }

    /// Profil sûr pour A15 / 6 Go — Metal tenté, fallback CPU côté loader.
    static let a15Default = LlamaInferenceConfig(
        nGpuLayers: -1,
        preferMetal: true,
        nCtx: 2048,
        nBatch: 512,
        nUbatch: 256,
        nThreads: nil,
        nThreadsBatch: nil,
        flashAttention: .auto,
        useMmap: true,
        sampling: .qwenInstruct,
        kvCacheTypeK: .q8_0,
        kvCacheTypeV: .q8_0,
        contextLadder: [2048, 1536, 1024],
        prefixReuseEnabled: true,
        warmupOnLoad: true,
        evalCallbackEnabled: false,
        imageMaxTokens: 192
    )

    static func resolvedThreads(explicit: Int32?) -> Int32 {
        if let explicit, explicit > 0 { return explicit }
        // A15 : 2P+4E — laisser 2 cœurs au système / UI.
        let count = ProcessInfo.processInfo.processorCount
        return Int32(max(1, min(4, count - 2)))
    }

    /// Contextes candidats, du plus grand au plus petit, `nCtx` d'abord.
    var resolvedContextLadder: [UInt32] {
        var seen = Set<UInt32>()
        var out: [UInt32] = []
        for value in [nCtx] + contextLadder where value >= 512 {
            if seen.insert(value).inserted { out.append(value) }
        }
        return out.isEmpty ? [nCtx] : out
    }

    // MARK: Codable tolérant

    private enum CodingKeys: String, CodingKey {
        case nGpuLayers, preferMetal, nCtx, nBatch, nUbatch, nThreads, nThreadsBatch
        case flashAttention, useMmap, sampling, kvCacheTypeK, kvCacheTypeV
        case contextLadder, prefixReuseEnabled, warmupOnLoad, evalCallbackEnabled, imageMaxTokens
    }

    init(
        nGpuLayers: Int32,
        preferMetal: Bool,
        nCtx: UInt32,
        nBatch: UInt32,
        nUbatch: UInt32,
        nThreads: Int32?,
        nThreadsBatch: Int32?,
        flashAttention: LlamaFlashAttentionMode,
        useMmap: Bool,
        sampling: LlamaSamplingConfig,
        kvCacheTypeK: LlamaKVCacheType,
        kvCacheTypeV: LlamaKVCacheType,
        contextLadder: [UInt32],
        prefixReuseEnabled: Bool,
        warmupOnLoad: Bool,
        evalCallbackEnabled: Bool,
        imageMaxTokens: Int32
    ) {
        self.nGpuLayers = nGpuLayers
        self.preferMetal = preferMetal
        self.nCtx = nCtx
        self.nBatch = nBatch
        self.nUbatch = nUbatch
        self.nThreads = nThreads
        self.nThreadsBatch = nThreadsBatch
        self.flashAttention = flashAttention
        self.useMmap = useMmap
        self.sampling = sampling
        self.kvCacheTypeK = kvCacheTypeK
        self.kvCacheTypeV = kvCacheTypeV
        self.contextLadder = contextLadder
        self.prefixReuseEnabled = prefixReuseEnabled
        self.warmupOnLoad = warmupOnLoad
        self.evalCallbackEnabled = evalCallbackEnabled
        self.imageMaxTokens = imageMaxTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = LlamaInferenceConfig.a15Default
        nGpuLayers = try c.decodeIfPresent(Int32.self, forKey: .nGpuLayers) ?? fallback.nGpuLayers
        preferMetal = try c.decodeIfPresent(Bool.self, forKey: .preferMetal) ?? fallback.preferMetal
        nCtx = try c.decodeIfPresent(UInt32.self, forKey: .nCtx) ?? fallback.nCtx
        nBatch = try c.decodeIfPresent(UInt32.self, forKey: .nBatch) ?? fallback.nBatch
        nUbatch = try c.decodeIfPresent(UInt32.self, forKey: .nUbatch) ?? fallback.nUbatch
        nThreads = try c.decodeIfPresent(Int32.self, forKey: .nThreads)
        nThreadsBatch = try c.decodeIfPresent(Int32.self, forKey: .nThreadsBatch)
        flashAttention = try c.decodeIfPresent(LlamaFlashAttentionMode.self, forKey: .flashAttention) ?? fallback.flashAttention
        useMmap = try c.decodeIfPresent(Bool.self, forKey: .useMmap) ?? fallback.useMmap
        sampling = try c.decodeIfPresent(LlamaSamplingConfig.self, forKey: .sampling) ?? fallback.sampling
        kvCacheTypeK = try c.decodeIfPresent(LlamaKVCacheType.self, forKey: .kvCacheTypeK) ?? fallback.kvCacheTypeK
        kvCacheTypeV = try c.decodeIfPresent(LlamaKVCacheType.self, forKey: .kvCacheTypeV) ?? fallback.kvCacheTypeV
        contextLadder = try c.decodeIfPresent([UInt32].self, forKey: .contextLadder) ?? fallback.contextLadder
        prefixReuseEnabled = try c.decodeIfPresent(Bool.self, forKey: .prefixReuseEnabled) ?? fallback.prefixReuseEnabled
        warmupOnLoad = try c.decodeIfPresent(Bool.self, forKey: .warmupOnLoad) ?? fallback.warmupOnLoad
        evalCallbackEnabled = try c.decodeIfPresent(Bool.self, forKey: .evalCallbackEnabled) ?? fallback.evalCallbackEnabled
        imageMaxTokens = try c.decodeIfPresent(Int32.self, forKey: .imageMaxTokens) ?? fallback.imageMaxTokens
    }
}

/// Options d'une génération précise. Portées par le workflow appelant, pas par
/// le profil du modèle : un même modèle chatte, résume et appelle des outils avec
/// trois réglages différents.
struct LocalGenerationOptions: Equatable, Sendable {
    /// `nil` = échantillonnage par défaut du profil.
    var sampling: LlamaSamplingConfig?
    /// Grammaire GBNF contraignant la sortie (tool calling, JSON structuré).
    var grammar: String?
    /// Budget mural. Dépassé, on rend le texte déjà produit plutôt qu'une erreur.
    var timeout: TimeInterval?
    /// Réflexion pour ce tour précis. Consommé par le **runtime** (il change le
    /// préremplissage du template), pas par le moteur : le moteur ne connaît que
    /// des tokens. `nil` = garder le réglage du profil.
    var enableThinking: Bool?

    static let `default` = LocalGenerationOptions()

    init(
        sampling: LlamaSamplingConfig? = nil,
        grammar: String? = nil,
        timeout: TimeInterval? = nil,
        enableThinking: Bool? = nil
    ) {
        self.sampling = sampling
        self.grammar = grammar
        self.timeout = timeout
        self.enableThinking = enableThinking
    }
}

/// Snapshot diagnostic après load — pour confirmer Metal / GPU layers sur appareil.
struct LlamaLoadDiagnostics: Equatable, Sendable, Codable {
    var modelPath: String
    var modelId: String?
    var quant: String?
    var fileBytes: Int64
    var backendRequested: String
    var backendEffective: String
    var metalAvailable: Bool
    var metalDeviceName: String?
    var cpuDeviceName: String?
    var nGpuLayersConfigured: Int32
    var nLayerModel: Int32?
    var nCtx: UInt32
    /// `n_ctx` demandé avant repli éventuel via `contextLadder`.
    var nCtxRequested: UInt32
    var nBatch: UInt32
    var nUbatch: UInt32
    var nThreads: Int32
    var nThreadsBatch: Int32
    var flashAttention: String
    var kvCacheTypeK: String
    var kvCacheTypeV: String
    var usedMmap: Bool
    var loadDurationMs: Double
    var warmupDurationMs: Double?
    var fellBackToCPU: Bool
    var fallbackReason: String?
    var llamaLogTail: String
    var estimatedKVBytesHint: Int64?
    var availableMemoryAtLoad: Int64?
    /// Chemin GDN observé (logs sched_reserve + cb_eval). Pas une déduction « logs vides = UNKNOWN ».
    var gdn: LlamaGdnProbeObservation = .unknown

    var summaryLine: String {
        let layers: String
        if let nLayerModel {
            layers = "layers=\(nLayerModel) gpuCfg=\(nGpuLayersConfigured)"
        } else {
            layers = "gpuCfg=\(nGpuLayersConfigured)"
        }
        var parts = [
            "backend=\(backendEffective)",
            metalAvailable ? "metal=yes(\(metalDeviceName ?? "?"))" : "metal=no",
            layers,
            "ctx=\(nCtx)\(nCtx == nCtxRequested ? "" : "(demandé \(nCtxRequested))") batch=\(nBatch)/\(nUbatch)",
            "kv=\(kvCacheTypeK)/\(kvCacheTypeV)",
            "threads=\(nThreads)/\(nThreadsBatch)",
            "fa=\(flashAttention)",
            "gdn=\(gdn.probe)/ar=\(gdn.fusedAR)/ch=\(gdn.fusedCH)/auto=\(gdn.autoFgdn)",
            fellBackToCPU ? "FALLBACK_CPU" : "as_requested",
            String(format: "load=%.0fms", loadDurationMs),
        ]
        if let warmupDurationMs {
            parts.append(String(format: "warmup=%.0fms", warmupDurationMs))
        }
        if let availableMemoryAtLoad {
            parts.append("mem=\(DeviceMemoryGuard.mb(availableMemoryAtLoad))")
        }
        return parts.joined(separator: " ")
    }
}

/// Probe backends ggml sans charger de modèle.
struct LlamaBackendProbe: Equatable, Sendable {
    var metalAvailable: Bool
    var metalName: String?
    var cpuAvailable: Bool
    var cpuName: String?
    var deviceCount: Int
    var deviceSummaries: [String]
}
