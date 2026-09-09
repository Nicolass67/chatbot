import Foundation

// MARK: - Application capabilities (identiques PC / local / tous modèles)

/// Fonctionnalités que **l’application** expose. Indépendantes du modèle.
/// Ne pas utiliser pour masquer Agent/Web/Mail selon la taille du GGUF.
struct ApplicationCapabilities: Equatable, Sendable {
    var chat: Bool = true
    var agent: Bool = true
    var web: Bool = true
    var mail: Bool = true
    var files: Bool = true
    var memory: Bool = true
    var search: Bool = true
    var documents: Bool = true
    var structuredOutput: Bool = true
    var toolCalling: Bool = true
    var attachments: Bool = true
    var visionWorkflow: Bool = true // le workflow existe ; le runtime décide du chemin

    static let full = ApplicationCapabilities()
}

// MARK: - Native model/runtime capabilities (vraies absences techniques)

/// Capacités intrinsèques du modèle / runtime — seules différences « impossibles » légitimes.
struct ModelNativeCapabilities: Equatable, Sendable, Hashable {
    var supportsVision: Bool
    var supportsAudio: Bool
    var supportsNativeToolCalling: Bool
    var supportsStructuredOutput: Bool
    var supportsReasoning: Bool
    var supportsMultilingual: Bool
    /// OCR / Vision framework peuvent fournir un fallback texte même sans vision native.
    var supportsSystemOCRFallback: Bool

    static func from(descriptor: LocalModelDescriptor) -> ModelNativeCapabilities {
        ModelNativeCapabilities(
            supportsVision: descriptor.capabilities.vision,
            supportsAudio: descriptor.capabilities.audio,
            supportsNativeToolCalling: false, // llama local : tool calling via JSON applicatif
            supportsStructuredOutput: true,
            supportsReasoning: descriptor.capabilities.reasoning,
            supportsMultilingual: descriptor.capabilities.multilingual,
            supportsSystemOCRFallback: true
        )
    }
}

// MARK: - Execution profile (budgets — pas de feature flags)

/// Budgets d’exécution pour **le même** workflow. Varie selon le modèle, pas les features.
struct LocalModelExecutionProfile: Equatable, Sendable, Hashable {
    var contextCharBudget: Int
    /// Autorité en **tokens** pour le contexte de génération.
    ///
    /// Les budgets en caractères ne sont qu'une approximation grossière : en
    /// français Qwen tokenise autour de 3,1 caractères par token, mais un corps
    /// de mail HTML ou du JSON d'outil tombe sous 2,0. Compter en caractères
    /// fait donc soit dépasser `n_ctx` (et déclencher un re-prefill complet en
    /// boucle de repli), soit gaspiller un tiers de la fenêtre.
    ///
    /// `0` = dériver de `contextCharBudget` (profils historiques non migrés).
    var contextTokenBudget: Int = 0
    var historyMessageBudget: Int
    var maxOutputTokens: Int
    var temperature: Double
    var topP: Double
    var maxWorkflowSteps: Int
    var maxToolCalls: Int
    var maxWebResults: Int
    var maxFetchedPages: Int
    var maxEvidencePerSource: Int
    var maxWebSnippetChars: Int
    var maxMailMessages: Int
    var maxMailBodyChars: Int
    var maxDocumentChunks: Int
    var maxChunkChars: Int
    var toolResultCharBudget: Int
    var generationTimeoutSeconds: Double
    var performanceClass: PerformanceClass
    /// Paramètres llama.cpp / Metal — ne changent pas les features applicatives.
    var inference: LlamaInferenceConfig
    /// Réflexion Gemma 4 : off par défaut (qualité vs temps à mesurer, jamais forcée).
    var thinkingEnabled: Bool
    var thinkingTokenBudget: Int
    /// Le routeur peut activer la réflexion pour les seules tâches qui en profitent
    /// (raisonnement, comparaison, calcul) au lieu de la subir sur « salut ».
    var adaptiveThinking: Bool = false

    enum PerformanceClass: String, Sendable, Hashable {
        case compact
        case balanced
        case ample
    }

    /// Budget contexte effectif en tokens.
    /// Conversion prudente 3,0 car/token pour les profils encore en caractères.
    var resolvedContextTokenBudget: Int {
        if contextTokenBudget > 0 { return contextTokenBudget }
        return max(512, contextCharBudget / 3)
    }

    /// Plafond dur imposé par le moteur, marge de sortie déduite.
    func hardPromptTokenCeiling(outputTokens: Int) -> Int {
        let engineCeiling = Int(inference.nCtx) - outputTokens - GenerationContextBudget.safetyTokens
        return max(256, min(resolvedContextTokenBudget, engineCeiling))
    }

    /// Profil dérivé du descripteur — **mêmes features**, budgets + inference différents.
    static func profile(for model: LocalModelDescriptor) -> LocalModelExecutionProfile {
        switch model.id {
        case "qwen3-1.7b-q4_k_m", "lfm25-1.2b-instruct-q4_k_m":
            return .compact
        case "qwen35-2b-q4_k_m":
            return .qwen35Dense2B
        case "lfm25-vl-3b-q4_k_m":
            return .lfm25VL3BExperimental
        case "minicpm-v46-thinking-q4_k_m":
            return .miniCPMV46ThinkingExperimental
        case "north-micro-vision-instruct":
            return .balanced
        case "granite4-micro-q4_k_m":
            return .balanced
        case "qwen3-4b-q4_k_m":
            return .ample
        case "gemma4-e2b-it-q4_0":
            return .gemma4E2BExperimental
        case "phi4-mini-3.8b":
            // Modèles plus lourds : même workflows, contexte moteur un peu plus bas + GPU layers plafonnés à tester.
            var p = LocalModelExecutionProfile.ample
            p.contextCharBudget = 10_000
            p.maxWorkflowSteps = 8
            p.maxToolCalls = 8
            p.inference.nCtx = 1536
            p.inference.nGpuLayers = 28 // benchmark requis ; -1 peut OOM sur 6 Go
            p.inference.nBatch = 256
            p.inference.nUbatch = 128
            return p
        default:
            return .compact
        }
    }

    static let compact = LocalModelExecutionProfile(
        contextCharBudget: 3_500,
        historyMessageBudget: 8,
        maxOutputTokens: 768,
        temperature: 0.7,
        topP: 0.9,
        maxWorkflowSteps: 4,
        maxToolCalls: 4,
        maxWebResults: 4,
        maxFetchedPages: 2,
        maxEvidencePerSource: 2,
        maxWebSnippetChars: 280,
        maxMailMessages: 4,
        maxMailBodyChars: 3_500,
        maxDocumentChunks: 4,
        maxChunkChars: 700,
        toolResultCharBudget: 1_400,
        generationTimeoutSeconds: 90,
        performanceClass: .compact,
        inference: {
            var c = LlamaInferenceConfig.a15Default
            c.nCtx = 2048
            c.nGpuLayers = -1
            c.nBatch = 512
            c.nUbatch = 256
            c.temperature = 0.7
            return c
        }(),
        thinkingEnabled: false,
        thinkingTokenBudget: 0
    )

    static let balanced = LocalModelExecutionProfile(
        contextCharBudget: 5_500,
        historyMessageBudget: 12,
        maxOutputTokens: 512,
        temperature: 0.7,
        topP: 0.9,
        maxWorkflowSteps: 6,
        maxToolCalls: 6,
        maxWebResults: 5,
        maxFetchedPages: 2,
        maxEvidencePerSource: 2,
        maxWebSnippetChars: 360,
        maxMailMessages: 6,
        maxMailBodyChars: 5_000,
        maxDocumentChunks: 6,
        maxChunkChars: 1_600,
        toolResultCharBudget: 2_500,
        generationTimeoutSeconds: 120,
        performanceClass: .balanced,
        inference: {
            var c = LlamaInferenceConfig.a15Default
            c.nCtx = 2048
            c.nGpuLayers = -1
            c.nBatch = 384
            c.nUbatch = 192
            c.temperature = 0.7
            return c
        }(),
        thinkingEnabled: false,
        thinkingTokenBudget: 0
    )

    static let ample = LocalModelExecutionProfile(
        contextCharBudget: 8_000,
        historyMessageBudget: 16,
        maxOutputTokens: 768,
        temperature: 0.65,
        topP: 0.9,
        maxWorkflowSteps: 8,
        maxToolCalls: 8,
        maxWebResults: 6,
        maxFetchedPages: 3,
        maxEvidencePerSource: 2,
        maxWebSnippetChars: 420,
        maxMailMessages: 8,
        maxMailBodyChars: 6_000,
        maxDocumentChunks: 8,
        maxChunkChars: 2_000,
        toolResultCharBudget: 3_500,
        generationTimeoutSeconds: 180,
        performanceClass: .ample,
        inference: {
            var c = LlamaInferenceConfig.a15Default
            c.nCtx = 2048
            c.nGpuLayers = -1
            c.nBatch = 256
            c.nUbatch = 128
            c.temperature = 0.65
            return c
        }(),
        thinkingEnabled: false,
        thinkingTokenBudget: 0
    )

    /// **Profil principal** — Qwen3.5 2B Q4_K_M sur iPhone 14 Plus (A15, 6 Go).
    /// Réglé qualité d'abord : c'est le seul modèle réellement utilisé.
    ///
    /// Budget mémoire visé (`increased-memory-limit` actif) :
    /// poids ≈ 1,27 Go + KV q8_0 6144 tokens ≈ 360 Mo + compute ≈ 300 Mo ≈ 1,95 Go.
    /// `contextLadder` dégrade proprement si la marge jetsam est plus serrée.
    ///
    /// La réutilisation du préfixe KV rend le contexte long quasi gratuit après
    /// le premier tour : seul le delta du message est préfillé.
    static let qwen35Dense2B = LocalModelExecutionProfile(
        contextCharBudget: 14_000,
        contextTokenBudget: 4_608,
        historyMessageBudget: 24,
        maxOutputTokens: 1_024,
        temperature: 0.7,
        topP: 0.8,
        maxWorkflowSteps: 8,
        maxToolCalls: 8,
        maxWebResults: 6,
        maxFetchedPages: 3,
        maxEvidencePerSource: 3,
        maxWebSnippetChars: 480,
        maxMailMessages: 8,
        maxMailBodyChars: 7_000,
        maxDocumentChunks: 8,
        maxChunkChars: 2_000,
        toolResultCharBudget: 4_000,
        generationTimeoutSeconds: 240,
        performanceClass: .ample,
        inference: {
            var c = LlamaInferenceConfig.a15Default
            c.nCtx = 6144
            c.contextLadder = [4096, 3072, 2048]
            c.nGpuLayers = -1
            // Prefill : gros batch logique, ubatch modéré pour borner le buffer Metal.
            c.nBatch = 512
            c.nUbatch = 256
            c.nThreads = 4
            c.nThreadsBatch = 4
            c.sampling = .qwenInstruct
            c.kvCacheTypeK = .q8_0
            c.kvCacheTypeV = .q8_0
            c.flashAttention = .enabled
            c.prefixReuseEnabled = true
            c.warmupOnLoad = true
            c.evalCallbackEnabled = false
            return c
        }(),
        thinkingEnabled: false,
        thinkingTokenBudget: 1_024,
        adaptiveThinking: true
    )

    /// iPhone 14 Plus / 6 Go — prudent. Qualité avant vitesse. Pas 128K de contexte.
    static let gemma4E2BExperimental = LocalModelExecutionProfile(
        contextCharBudget: 4_000,
        historyMessageBudget: 10,
        maxOutputTokens: 512,
        temperature: 0.7,
        topP: 0.95,
        maxWorkflowSteps: 5,
        maxToolCalls: 5,
        maxWebResults: 4,
        maxFetchedPages: 2,
        maxEvidencePerSource: 2,
        maxWebSnippetChars: 320,
        maxMailMessages: 5,
        maxMailBodyChars: 4_000,
        maxDocumentChunks: 5,
        maxChunkChars: 1_200,
        toolResultCharBudget: 2_000,
        generationTimeoutSeconds: 240,
        performanceClass: .balanced,
        inference: {
            var c = LlamaInferenceConfig.a15Default
            c.nCtx = 1536
            c.nGpuLayers = -1
            c.nBatch = 192
            c.nUbatch = 96
            c.temperature = 0.7
            c.topP = 0.95
            c.imageMaxTokens = 128
            return c
        }(),
        thinkingEnabled: false,
        thinkingTokenBudget: 256
    )

    /// iPhone 14 Plus / A15 — LFM2.5-VL 3B. Ne modifie pas le profil Qwen3.5 2B.
    static let lfm25VL3BExperimental = LocalModelExecutionProfile(
        contextCharBudget: 4_000,
        historyMessageBudget: 10,
        maxOutputTokens: 512,
        temperature: 0.2,
        topP: 0.9,
        maxWorkflowSteps: 5,
        maxToolCalls: 5,
        maxWebResults: 4,
        maxFetchedPages: 2,
        maxEvidencePerSource: 2,
        maxWebSnippetChars: 320,
        maxMailMessages: 5,
        maxMailBodyChars: 4_000,
        maxDocumentChunks: 5,
        maxChunkChars: 1_200,
        toolResultCharBudget: 2_000,
        generationTimeoutSeconds: 180,
        performanceClass: .balanced,
        inference: {
            var c = LlamaInferenceConfig.a15Default
            c.nCtx = 1536
            c.nGpuLayers = -1
            c.nBatch = 256
            c.nUbatch = 128
            c.nThreads = 4
            c.nThreadsBatch = 4
            c.temperature = 0.2
            c.topP = 0.9
            c.topK = 50
            c.imageMaxTokens = 128
            return c
        }(),
        thinkingEnabled: false,
        thinkingTokenBudget: 0
    )

    /// MiniCPM-V 4.6 Thinking — plus petit LLM, mmproj F16 lourd, thinking ON.
    static let miniCPMV46ThinkingExperimental = LocalModelExecutionProfile(
        contextCharBudget: 3_800,
        historyMessageBudget: 10,
        maxOutputTokens: 768,
        temperature: 0.7,
        topP: 0.8,
        maxWorkflowSteps: 5,
        maxToolCalls: 5,
        maxWebResults: 4,
        maxFetchedPages: 2,
        maxEvidencePerSource: 2,
        maxWebSnippetChars: 320,
        maxMailMessages: 5,
        maxMailBodyChars: 4_000,
        maxDocumentChunks: 5,
        maxChunkChars: 1_200,
        toolResultCharBudget: 2_000,
        generationTimeoutSeconds: 240,
        performanceClass: .balanced,
        inference: {
            var c = LlamaInferenceConfig.a15Default
            c.nCtx = 1536
            c.nGpuLayers = -1
            c.nBatch = 192
            c.nUbatch = 96
            c.nThreads = 4
            c.nThreadsBatch = 4
            c.temperature = 0.7
            c.topP = 0.8
            c.topK = 100
            c.imageMaxTokens = 96
            return c
        }(),
        thinkingEnabled: true,
        thinkingTokenBudget: 512
    )

    /// Budget de sortie selon la tâche — pas un max unique pour tout.
    enum GenerationTask: String, Sendable {
        case short
        case explanation
        case detailed
        case mailSummary
        case mailReply
        case agentStep
        case agentFinal
        case webSynthesize
        case files
    }

    func outputTokens(for task: GenerationTask) -> Int {
        switch performanceClass {
        case .compact:
            switch task {
            case .short: return 256
            case .explanation: return 768
            case .detailed: return 1024
            case .mailSummary: return 448
            case .mailReply: return 512
            case .agentStep: return 320
            case .agentFinal: return 768
            case .webSynthesize: return 768
            case .files: return 512
            }
        case .balanced:
            switch task {
            case .short: return 320
            case .explanation: return 896
            case .detailed: return 1152
            case .mailSummary: return 512
            case .mailReply: return 640
            case .agentStep: return 384
            case .agentFinal: return 896
            case .webSynthesize: return 896
            case .files: return 640
            }
        case .ample:
            switch task {
            case .short: return 384
            case .explanation: return 1024
            case .detailed: return 1280
            case .mailSummary: return 640
            case .mailReply: return 768
            case .agentStep: return 448
            case .agentFinal: return 1024
            case .webSynthesize: return 1024
            case .files: return 768
            }
        }
    }

    func with(
        maxWorkflowSteps: Int? = nil,
        maxToolCalls: Int? = nil,
        contextCharBudget: Int? = nil
    ) -> LocalModelExecutionProfile {
        var copy = self
        if let maxWorkflowSteps { copy.maxWorkflowSteps = maxWorkflowSteps }
        if let maxToolCalls { copy.maxToolCalls = maxToolCalls }
        if let contextCharBudget { copy.contextCharBudget = contextCharBudget }
        return copy
    }
}

extension LocalModelDescriptor {
    var executionProfile: LocalModelExecutionProfile {
        LocalModelExecutionProfile.profile(for: self)
    }

    var nativeCapabilities: ModelNativeCapabilities {
        ModelNativeCapabilities.from(descriptor: self)
    }
}
