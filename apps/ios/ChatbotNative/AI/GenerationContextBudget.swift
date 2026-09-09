import Foundation

/// Budget réel llama : `promptTokens + reservedOutput <= n_ctx`.
/// `n_ctx` n’est **pas** un budget de prompt ; une partie est réservée à la génération.
struct GenerationContextBudget: Equatable, Sendable {
    var nCtx: Int
    var reservedOutputTokens: Int
    var safetyTokens: Int

    var promptBudget: Int {
        max(128, nCtx - reservedOutputTokens - safetyTokens)
    }

    static func make(
        profile: LocalModelExecutionProfile,
        requestedOutput: Int
    ) -> GenerationContextBudget {
        let nCtx = max(256, Int(profile.inference.nCtx))
        let minPrompt = 384
        let requested = max(32, requestedOutput)
        let reserved = min(max(32, requested), max(32, nCtx - minPrompt))
        return GenerationContextBudget(
            nCtx: nCtx,
            reservedOutputTokens: reserved,
            safetyTokens: 8
        )
    }

    /// Estimation conservatrice (UTF-8 / 3) si le tokenizer llama n’est pas disponible.
    static func estimateTokens(_ text: String) -> Int {
        max(1, (text.utf8.count + 2) / 3)
    }

    static func clip(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars))
    }

    /// Réduit l’historique / le dernier message outil sans second modèle.
    static func shrinkMessages(
        _ messages: [LLMChatMessage],
        attempt: Int,
        toolResultCharBudget: Int
    ) -> [LLMChatMessage] {
        guard !messages.isEmpty else { return messages }
        let keep = attempt >= 2 ? 1 : max(1, messages.count - attempt * 2)
        var slice = Array(messages.suffix(keep))
        let cap = max(240, toolResultCharBudget / max(attempt, 1))
        if var last = slice.last, last.content.count > cap {
            last.content = clip(last.content, maxChars: cap)
            slice[slice.count - 1] = last
        }
        return slice
    }
}

enum GenerationRunPhase: String, Equatable, Sendable {
    case started
    case planning
    case searching
    case analyzing
    case generating
    case completed
    case failed
    case cancelled
}

/// Isolation d’une génération (sources / tools / stream ne fuient pas vers le tour suivant).
/// Les sources appartiennent au run, jamais au « dernier assistant » de la conversation.
struct GenerationRunState: Equatable, Sendable {
    var id: String
    var messageId: String?
    var startedAt: Date
    var workflow: String
    var phase: GenerationRunPhase
    var query: String?
    var discoveredSources: [SearchSourceDTO]
    var finalSources: [SearchSourceDTO]
    var mailContext: Bool
    var webContext: Bool
    var mailThreadId: String?

    /// Compat lecture : finales si le run est clos, sinon découvertes.
    var sources: [SearchSourceDTO] {
        get { finalSources.isEmpty ? discoveredSources : finalSources }
        set { discoveredSources = newValue }
    }

    static func start(workflow: String = "chat") -> GenerationRunState {
        GenerationRunState(
            id: UUID().uuidString,
            messageId: nil,
            startedAt: Date(),
            workflow: workflow,
            phase: .started,
            query: nil,
            discoveredSources: [],
            finalSources: [],
            mailContext: false,
            webContext: false,
            mailThreadId: nil
        )
    }

    func log(_ event: String, extra: [String: String] = [:]) {
        var fields = extra
        fields["id"] = id
        if fields["workflow"] == nil { fields["workflow"] = workflow }
        WorkflowTrace.log("run:\(event)", fields)
    }
}
