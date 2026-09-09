import Foundation

/// Message unifié pour les providers LLM (local / distant).
struct LLMChatMessage: Sendable, Hashable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    var role: Role
    var content: String
}

/// Contrat commun — le chat distant continue d’utiliser `ChatStreamingService` dans `ChatScreen`.
protocol LLMProvider: Sendable {
    func stream(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - Remote (thin)

/// Enveloppe documentaire : le flux distant reste dans `ChatStreamingService` /
/// `APIClient` (SSE `/api/chat`). Ce provider ne remplace pas encore le chemin ChatScreen ;
/// il expose le même protocole pour un routage futur via `ExecutionModeStore`.
struct RemoteLLMProvider: LLMProvider {
    /// Réservé — le streaming distant productif passe toujours par `ChatStreamingService`.
    var note: String {
        "ChatScreen utilise ChatStreamingService pour le mode distant (PC / LM Studio)."
    }

    func stream(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: NSError(
                    domain: "RemoteLLMProvider",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Utilisez ChatStreamingService pour le chat distant. \(note)",
                    ]
                )
            )
            _ = messages
            _ = systemPrompt
            _ = maxTokens
        }
    }
}

// MARK: - Local

/// Provider local : `LocalInferenceEngine` + `LocalPrompts` + troncature d’historique (~3k chars).
struct LocalLLMProvider: LLMProvider {
    var engine: LocalInferenceEngine = .shared
    var promptKind: LocalPromptKind = .conversation
    /// Heuristique caractères ≈ budget tokens (~3k pour laisser de la marge sous n_ctx 4096).
    var historyCharBudget: Int = 3_000

    func stream(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        let system = systemPrompt ?? LocalPrompts.systemPrompt(for: promptKind)
        let prompt = Self.buildPrompt(
            system: system,
            messages: messages,
            charBudget: historyCharBudget
        )
        let engine = self.engine
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = await engine.generate(prompt: prompt, maxTokens: maxTokens)
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await engine.cancel() }
            }
        }
    }

    /// Construit un prompt chat simple (Qwen-style) avec troncature depuis les messages les plus anciens.
    static func buildPrompt(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int
    ) -> String {
        var lines: [String] = []
        lines.append("System: \(system)")

        var selected: [LLMChatMessage] = []
        var used = system.count + 16
        for message in messages.reversed() {
            let cost = message.content.count + 24
            if used + cost > charBudget, !selected.isEmpty {
                break
            }
            selected.insert(message, at: 0)
            used += cost
        }

        for message in selected {
            switch message.role {
            case .system:
                lines.append("System: \(message.content)")
            case .user:
                lines.append("User: \(message.content)")
            case .assistant:
                lines.append("Assistant: \(message.content)")
            }
        }
        lines.append("Assistant:")
        return lines.joined(separator: "\n")
    }
}
