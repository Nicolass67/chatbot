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
        models.activeDescriptor.nativeCapabilities
    }

    var executionProfile: LocalModelExecutionProfile {
        models.activeDescriptor.executionProfile
    }

    var chatTemplateProfile: LocalModelRuntimeProfile {
        models.activeDescriptor.runtimeProfile
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
        if !models.isReady {
            await models.loadIntoEngine()
        }
        guard models.isReady else { throw AIRuntimeError.notReady }

        let profile = executionProfile
        let template = chatTemplateProfile
        let budget = profile.contextCharBudget
        let tokens = maxTokens ?? profile.maxOutputTokens

        let prompt = LocalChatTemplate.buildPrompt(
            system: system,
            messages: messages,
            charBudget: budget,
            profile: template
        )

        let accumulator = RuntimeStringAccumulator()
        let engineRef = engine
        let emitted = StreamEmitCounter()
        do {
            try await engineRef.generate(prompt: prompt, maxTokens: tokens) { piece in
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
        if sessionLocalOnly || execution.prefersOnDeviceAssistant {
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
