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

struct RemoteLLMProvider: LLMProvider {
    var note: String {
        "ChatScreen utilise ChatStreamingService pour le chat distant (PC / LM Studio)."
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

/// Provider local : moteur + template du **modèle actif** (pas Qwen hardcodé partout).
struct LocalLLMProvider: LLMProvider {
    var engine: LocalInferenceEngine = .shared
    var promptKind: LocalPromptKind = .conversation
    var historyCharBudget: Int = 3_000
    /// Profil runtime du modèle chargé (ChatML Qwen, Gemma, …).
    var runtimeProfile: LocalModelRuntimeProfile = .chatmlQwen

    func stream(
        messages: [LLMChatMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        let system = systemPrompt ?? LocalPrompts.systemPrompt(for: promptKind)
        let profile = runtimeProfile
        let prompt = Self.buildPrompt(
            system: system,
            messages: messages,
            charBudget: historyCharBudget,
            profile: profile
        )
        let engine = self.engine
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = await engine.generate(prompt: prompt, maxTokens: maxTokens)
                    var accumulated = ""
                    var emittedCount = 0
                    for try await token in stream {
                        accumulated += token
                        let step = LocalChatTemplate.streamingSafeEmit(
                            accumulated: accumulated,
                            alreadyEmittedCount: emittedCount,
                            profile: profile
                        )
                        if !step.emit.isEmpty {
                            continuation.yield(step.emit)
                        }
                        emittedCount = step.newEmittedCount
                        if step.hitStop {
                            await engine.cancel()
                            break
                        }
                    }
                    // Flush final sanitised (défense en profondeur).
                    let final = LocalChatTemplate.truncateAssistantOutput(accumulated, profile: profile)
                    if final.text.count > emittedCount {
                        let start = final.text.index(final.text.startIndex, offsetBy: emittedCount)
                        let tail = String(final.text[start...])
                        if !tail.isEmpty { continuation.yield(tail) }
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

    static func buildPrompt(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int,
        profile: LocalModelRuntimeProfile = .chatmlQwen
    ) -> String {
        LocalChatTemplate.buildPrompt(
            system: system,
            messages: messages,
            charBudget: charBudget,
            profile: profile
        )
    }

    /// Raccourci compat tests / anciens appels.
    static func buildPrompt(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int
    ) -> String {
        buildPrompt(system: system, messages: messages, charBudget: charBudget, profile: .chatmlQwen)
    }
}
