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
    var historyMessageBudget: Int
    var maxOutputTokens: Int
    var temperature: Double
    var topP: Double
    var maxWorkflowSteps: Int
    var maxToolCalls: Int
    var maxWebResults: Int
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

    enum PerformanceClass: String, Sendable, Hashable {
        case compact
        case balanced
        case ample
    }

    /// Profil dérivé du descripteur — **mêmes features**, budgets + inference différents.
    static func profile(for model: LocalModelDescriptor) -> LocalModelExecutionProfile {
        switch model.id {
        case "qwen3-1.7b-q4_k_m", "lfm25-1.2b-instruct-q4_k_m":
            return .compact
        case "qwen35-2b-q4_k_m", "granite4-micro-q4_k_m":
            return .balanced
        case "gemma4-e2b-it-q4_k_m", "qwen3-4b-q4_k_m":
            return .ample
        case "gemma4-e4b-it", "phi4-mini-3.8b":
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
        maxOutputTokens: 384,
        temperature: 0.7,
        topP: 0.9,
        maxWorkflowSteps: 4,
        maxToolCalls: 4,
        maxWebResults: 3,
        maxWebSnippetChars: 400,
        maxMailMessages: 4,
        maxMailBodyChars: 3_500,
        maxDocumentChunks: 4,
        maxChunkChars: 1_200,
        toolResultCharBudget: 1_800,
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
        }()
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
        maxWebSnippetChars: 600,
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
        }()
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
        maxWebSnippetChars: 800,
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
        }()
    )

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
