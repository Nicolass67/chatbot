import Foundation

/// Runtime abstrait : PC ou Local exposent la **même** surface aux workflows.
@MainActor
protocol AIRuntime: AnyObject {
    var applicationCapabilities: ApplicationCapabilities { get }
    var nativeCapabilities: ModelNativeCapabilities { get }
    var executionProfile: LocalModelExecutionProfile { get }
    var chatTemplateProfile: LocalModelRuntimeProfile { get }
    var isReady: Bool { get }

    func generate(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int?
    ) async throws -> String

    /// Streaming commun Chat / Mail / Agent / Web / Files.
    func generateStream(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int?,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String

    func cancel() async
}

extension AIRuntime {
    /// Point d'entrée unique des workflows : options d'échantillonnage,
    /// grammaire et réflexion quand le runtime les supporte, sinon repli sur la
    /// surface commune. Évite de dupliquer partout le `if let onToken`.
    @MainActor
    func generateLocal(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int?,
        options: LocalGenerationOptions = .default,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        if let local = self as? LocalAIRuntime {
            return try await local.generateStream(
                system: system,
                messages: messages,
                maxTokens: maxTokens,
                images: [],
                options: options,
                onToken: onToken ?? { _ in }
            )
        }
        if let onToken {
            return try await generateStream(
                system: system,
                messages: messages,
                maxTokens: maxTokens,
                onToken: onToken
            )
        }
        return try await generate(system: system, messages: messages, maxTokens: maxTokens)
    }
}

/// Erreurs runtime partagées (pas de logique métier).
enum AIRuntimeError: Error, LocalizedError, Sendable {
    case notReady
    case cancelled
    case emptyGeneration
    case toolUnknown(String)
    case toolInvalidArguments(String)
    case toolFailed(String)
    case timeout
    case inference(String)
    case contextOverflow

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Le moteur IA n’est pas prêt. Charge un modèle local ou connecte le PC."
        case .cancelled:
            return "Génération annulée."
        case .emptyGeneration:
            return "Aucune réponse exploitable du modèle."
        case .toolUnknown(let name):
            return "Outil inconnu : \(name)."
        case .toolInvalidArguments(let detail):
            return "Arguments d’outil invalides : \(detail)"
        case .toolFailed(let detail):
            return detail
        case .timeout:
            return "Délai d’exécution dépassé."
        case .inference(let detail):
            return detail
        case .contextOverflow:
            return "Le contexte de cette recherche est trop volumineux. Je réduis automatiquement les résultats."
        }
    }
}

/// Runtime local : modèle GGUF sélectionné + ExecutionProfile.
@MainActor
final class LocalAIRuntime: AIRuntime {
    static let shared = LocalAIRuntime()

    private let models: LocalModelManager
    private let engine: LocalInferenceEngine

    init(
        models: LocalModelManager = .shared,
        engine: LocalInferenceEngine = .shared
    ) {
        self.models = models
        self.engine = engine
    }

    var applicationCapabilities: ApplicationCapabilities { .full }

    var nativeCapabilities: ModelNativeCapabilities {
        var caps = models.activeDescriptor.nativeCapabilities
        caps.supportsVision = models.activeDescriptor.capabilities.vision
            && models.isVisionProjectorInstalled
        return caps
    }

    var executionProfile: LocalModelExecutionProfile {
        models.activeDescriptor.executionProfile
    }

    var chatTemplateProfile: LocalModelRuntimeProfile {
        var profile = models.activeDescriptor.runtimeProfile
        if models.activeDescriptor.executionProfile.thinkingEnabled {
            profile.enableThinking = true
        }
        return profile
    }

    var isReady: Bool { models.isReady }

    func generate(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int? = nil
    ) async throws -> String {
        try await generateStream(system: system, messages: messages, maxTokens: maxTokens, onToken: { _ in })
    }

    func generateStream(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int?,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await generateStream(
            system: system,
            messages: messages,
            maxTokens: maxTokens,
            images: [],
            onToken: onToken
        )
    }

    func generateStream(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int?,
        images: [Data],
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if !models.isReady {
            await models.loadIntoEngine()
        }
        guard models.isReady else { throw AIRuntimeError.notReady }

        return try await generateStream(
            system: system,
            messages: messages,
            maxTokens: maxTokens,
            images: images,
            options: .default,
            onToken: onToken
        )
    }

    /// Chemin unique de génération locale.
    ///
    /// Le budget contexte est respecté **par construction** via `LocalPromptFitter` :
    /// plus de boucle « je tente, ça dépasse, je réduis, je recommence », qui
    /// tokenisait le prompt jusqu'à quatre fois et jetait le préfixe KV à chaque
    /// reprise. Une seule reprise défensive subsiste, si le moteur refuse malgré tout.
    func generateStream(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int?,
        images: [Data],
        options: LocalGenerationOptions,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if !models.isReady {
            await models.loadIntoEngine()
        }
        guard models.isReady else { throw AIRuntimeError.notReady }

        let profile = executionProfile
        var template = chatTemplateProfile
        // Réflexion décidée par tour : elle change le préremplissage de l'en-tête
        // assistant (`<think>\n` au lieu d'un bloc think vide).
        if let thinking = options.enableThinking {
            template.enableThinking = thinking
        }
        let requested = max(32, maxTokens ?? profile.maxOutputTokens)
        var working = messages
        let visionImages = Array(images.prefix(LocalVision.maxImagesPerTurn))
        if !visionImages.isEmpty, let idx = working.lastIndex(where: { $0.role == .user }) {
            working[idx].content = LocalVision.userContent(working[idx].content, imageCount: visionImages.count)
        }
        let mmprojPath: String? = {
            guard !visionImages.isEmpty else { return nil }
            return models.visionProjectorURL(for: models.activeDescriptor)?
                .path(percentEncoded: false)
        }()

        var resolvedOptions = options
        if resolvedOptions.timeout == nil {
            resolvedOptions.timeout = profile.generationTimeoutSeconds
        }

        // Budgéter sur la fenêtre réellement ouverte, pas sur celle demandée :
        // l'échelle de repli a pu dégrader `n_ctx` au chargement.
        let nCtx = await engine.activeContextTokens
        var promptCeiling = min(
            profile.hardPromptTokenCeiling(outputTokens: requested),
            max(256, nCtx - requested - GenerationContextBudget.safetyTokens)
        )
        var lastError: Error?

        // Deux passes au maximum : la seconde uniquement si le moteur signale un
        // dépassement que le budget calculé n'avait pas anticipé.
        for attempt in 0..<2 {
            try Task.checkCancellation()
            if attempt > 0 {
                promptCeiling = max(256, promptCeiling / 2)
            }

            let fitted = await LocalPromptFitter.fit(
                system: system,
                messages: working,
                profile: template,
                tokenBudget: promptCeiling,
                engine: engine
            )
            let output = min(
                requested,
                max(32, nCtx - fitted.promptTokens - GenerationContextBudget.safetyTokens)
            )

            var contextFields = fitted.traceFields
            contextFields["attempt"] = "\(attempt)"
            contextFields["prompt_ceiling"] = "\(promptCeiling)"
            contextFields["reserved_output"] = "\(output)"
            contextFields["n_ctx"] = "\(nCtx)"
            WorkflowTrace.log("context", contextFields)

            let accumulator = RuntimeStringAccumulator()
            let engineRef = engine
            let emitted = StreamEmitCounter()
            do {
                try await engineRef.generate(
                    prompt: fitted.prompt,
                    maxTokens: output,
                    images: visionImages,
                    mmprojPath: mmprojPath,
                    options: resolvedOptions
                ) { piece in
                    accumulator.append(piece)
                    let step = LocalChatTemplate.streamingSafeEmit(
                        accumulated: accumulator.value,
                        alreadyEmittedCount: emitted.count,
                        profile: template
                    )
                    emitted.count = step.newEmittedCount
                    if !step.emit.isEmpty {
                        await onToken(step.emit)
                    }
                    if step.hitStop {
                        accumulator.replace(with: step.displayText)
                        await engineRef.cancel()
                    }
                }
            } catch let error as LocalInferenceError {
                if case .cancelled = error {
                    let partial = LocalChatTemplate.truncateAssistantOutput(accumulator.value, profile: template).text
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !partial.isEmpty { return partial }
                    throw AIRuntimeError.cancelled
                }
                if case .contextTooLarge = error {
                    lastError = AIRuntimeError.contextOverflow
                    continue
                }
                throw AIRuntimeError.inference(error.localizedDescription)
            } catch is CancellationError {
                throw AIRuntimeError.cancelled
            } catch {
                throw AIRuntimeError.inference(error.localizedDescription)
            }

            let text = LocalChatTemplate.truncateAssistantOutput(accumulator.value, profile: template).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIRuntimeError.emptyGeneration }
            return text
        }

        throw lastError ?? AIRuntimeError.contextOverflow
    }

    func cancel() async {
        await engine.cancel()
    }
}

/// Sélection runtime : PC connecté + mode distant → futur PCRuntime ; sinon Local.
@MainActor
enum AIRuntimeResolver {
    static func current(
        sessionLocalOnly: Bool,
        execution: ExecutionModeStore = .shared
    ) -> any AIRuntime {
        // Mode local / offline → toujours runtime local.
        if sessionLocalOnly || execution.routesLocalCapableOnDevice {
            return LocalAIRuntime.shared
        }
        // PC : les workflows lourds restent sur SSE `/api/chat` (non dupliqués ici).
        // Ce resolver sert aux chemins unifiés locaux ; le Chat remote continue via ChatStreamingService.
        return LocalAIRuntime.shared
    }
}

private final class RuntimeStringAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    var value: String {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    func append(_ piece: String) {
        lock.lock(); defer { lock.unlock() }
        buffer += piece
    }

    func replace(with text: String) {
        lock.lock(); defer { lock.unlock() }
        buffer = text
    }
}

private final class StreamEmitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}
