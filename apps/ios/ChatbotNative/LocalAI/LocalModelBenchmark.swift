import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Résultat d’un micro-benchmark local (stocké / comparable entre modèles).
struct LocalModelBenchmarkResult: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(modelId)-\(ranAt.timeIntervalSince1970)" }
    var modelId: String
    var quant: String
    var appVersion: String
    var deviceModel: String
    var ranAt: Date
    var promptLabel: String
    var timeToFirstTokenMs: Double?
    var tokensPerSecond: Double?
    var promptTokensPerSecond: Double?
    var promptEvalMs: Double?
    var promptTokens: Int
    var generatedTokens: Int
    var totalMs: Double?
    var backendEffective: String?
    var nGpuLayersConfigured: Int32?
    var nCtx: UInt32?
    var nBatch: UInt32?
    var nThreads: Int32?
    var flashAttention: String?
    var outputPreview: String
    var success: Bool
    var errorMessage: String?
}

/// Suite de prompts pour comparer modèles / ExecutionProfiles.
enum LocalModelBenchmarkSuite {
    static let prompts: [(id: String, text: String)] = [
        ("hello", "Bonjour"),
        ("fact", "Quelle est la capitale de la France ? Réponds en une phrase."),
        ("french", "Écris une phrase polie pour remercier un collègue."),
        ("summary", "Résume en une phrase : Le projet avance, la revue est jeudi, préparer les slides."),
        ("reason", "Si tous les A sont B et X est A, X est-il B ? Réponds oui ou non puis justifie en une ligne."),
        ("struct", "Donne exactement 3 puces : avantages du mode avion."),
        ("medium", "Explique en 5 phrases ce qu’est un KV cache dans un LLM."),
        ("long_prompt", String(repeating: "Contexte historique. ", count: 80) + "Question : résume en une phrase."),
    ]

    static var appVersionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    static var deviceModelLabel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce("") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return partial }
            return partial + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "iPhone" : identifier
    }
}

/// Exécute un prompt de test sur le modèle **déjà chargé** (pas d’auto-switch).
@MainActor
enum LocalModelBenchmarkRunner {
    static func runPrompt(
        label: String,
        prompt: String,
        maxTokens: Int = 128
    ) async -> LocalModelBenchmarkResult {
        let models = LocalModelManager.shared
        let desc = models.activeDescriptor
        let infer = desc.executionProfile.inference
        let started = Date()
        let threads = LlamaInferenceConfig.resolvedThreads(explicit: infer.nThreads)

        func base(
            success: Bool,
            error: String?,
            preview: String,
            metrics: LocalInferenceMetrics,
            diag: LlamaLoadDiagnostics?
        ) -> LocalModelBenchmarkResult {
            LocalModelBenchmarkResult(
                modelId: desc.id,
                quant: desc.quant,
                appVersion: LocalModelBenchmarkSuite.appVersionLabel,
                deviceModel: LocalModelBenchmarkSuite.deviceModelLabel,
                ranAt: started,
                promptLabel: label,
                timeToFirstTokenMs: metrics.timeToFirstToken.map { $0 * 1000 },
                tokensPerSecond: metrics.tokensPerSecond,
                promptTokensPerSecond: metrics.promptTokensPerSecond,
                promptEvalMs: metrics.promptEvalSeconds.map { $0 * 1000 },
                promptTokens: metrics.promptTokens,
                generatedTokens: metrics.generatedTokens,
                totalMs: metrics.totalSeconds.map { $0 * 1000 },
                backendEffective: diag?.backendEffective ?? metrics.backendEffective,
                nGpuLayersConfigured: diag?.nGpuLayersConfigured ?? metrics.nGpuLayersConfigured,
                nCtx: diag?.nCtx ?? infer.nCtx,
                nBatch: diag?.nBatch ?? infer.nBatch,
                nThreads: diag?.nThreads ?? threads,
                flashAttention: diag?.flashAttention ?? infer.flashAttention.rawValue,
                outputPreview: preview,
                success: success,
                errorMessage: error
            )
        }

        guard models.isReady else {
            return base(
                success: false,
                error: "Modèle non chargé.",
                preview: "",
                metrics: .empty,
                diag: nil
            )
        }

        let profile = desc.runtimeProfile
        let chatPrompt = LocalChatTemplate.buildPrompt(
            system: "Tu es un assistant concis. Réponds brièvement.",
            user: prompt,
            profile: profile
        )
        var output = ""
        do {
            try await LocalInferenceEngine.shared.generate(prompt: chatPrompt, maxTokens: maxTokens) { piece in
                output += piece
                let cut = LocalChatTemplate.truncateAssistantOutput(output, profile: profile)
                output = cut.text
                if cut.hitStop {
                    await LocalInferenceEngine.shared.cancel()
                }
            }
        } catch {
            let metrics = await LocalInferenceEngine.shared.lastMetrics
            let diag = await LocalInferenceEngine.shared.lastLoadDiagnostics
            return base(
                success: false,
                error: error.localizedDescription,
                preview: String(LocalChatTemplate.truncateAssistantOutput(output, profile: profile).text.prefix(240)),
                metrics: metrics,
                diag: diag
            )
        }

        let clean = LocalChatTemplate.truncateAssistantOutput(output, profile: profile).text
        let metrics = await LocalInferenceEngine.shared.lastMetrics
        let diag = await LocalInferenceEngine.shared.lastLoadDiagnostics
        return base(
            success: !clean.isEmpty,
            error: clean.isEmpty ? "Sortie vide" : nil,
            preview: String(clean.prefix(240)),
            metrics: metrics,
            diag: diag
        )
    }
}
