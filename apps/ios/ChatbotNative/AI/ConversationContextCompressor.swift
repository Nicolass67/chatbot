import Foundation

/// Compression de contexte réutilisable (Chat / Mail / Agent / Web / Files).
/// Pas de `prefix(N)` aveugle : récents + résumé des anciens + faits mémorisés.
enum ConversationContextCompressor {
    struct Packet: Equatable, Sendable {
        var systemAugment: String
        var messages: [LLMChatMessage]
        var approximateChars: Int
    }

    /// - Parameters:
    ///   - conversationId: active le résumé roulant produit par le modèle.
    ///     `nil` ⇒ repli sur le résumé extractif déterministe.
    ///   - recallQuery: requête de rappel de la mémoire long terme.
    @MainActor
    static func compress(
        history: [LLMChatMessage],
        profile: LocalModelExecutionProfile,
        taskHint: String? = nil,
        conversationId: String? = nil,
        recallQuery: String? = nil
    ) -> Packet {
        let budget = profile.contextCharBudget
        let keepRecent = max(2, profile.historyMessageBudget)

        var augmentBlocks: [String] = []

        // Faits durables : ils viennent avant le résumé car ils survivent aux
        // conversations, alors que le résumé n'en couvre qu'une seule.
        if let recallQuery, !recallQuery.isEmpty {
            let facts = LocalMemoryStore.shared.recall(
                matching: recallQuery,
                budget: min(600, budget / 6)
            )
            if !facts.isEmpty {
                augmentBlocks.append(
                    "Ce que tu sais déjà de l’utilisateur (mémoire persistante, ne le récite pas) :\n\(facts)"
                )
            }
        }

        guard !history.isEmpty else {
            let augment = augmentBlocks.joined(separator: "\n\n")
            return Packet(systemAugment: augment, messages: [], approximateChars: augment.count)
        }

        if history.count <= keepRecent {
            let trimmed = trimToBudget(history, budget: budget)
            let augment = augmentBlocks.joined(separator: "\n\n")
            return Packet(
                systemAugment: augment,
                messages: trimmed,
                approximateChars: augment.count + trimmed.reduce(0) { $0 + $1.content.count }
            )
        }

        let older = Array(history.dropLast(keepRecent))
        let recent = Array(history.suffix(keepRecent))

        // Résumé produit par le modèle si disponible et suffisamment à jour ;
        // sinon extraction déterministe, qui reste meilleure que rien.
        let rolling = ConversationMemoryService.shared.summary(for: conversationId)
        if let rolling, rolling.coveredMessageCount >= older.count / 2, !rolling.summary.isEmpty {
            var block = "Résumé des échanges précédents :\n\(rolling.summary)"
            // Les messages anciens que le résumé ne couvre pas encore.
            if rolling.coveredMessageCount < older.count {
                let uncovered = Array(older[rolling.coveredMessageCount...])
                let extra = summarizeDeterministic(
                    uncovered,
                    maxChars: min(500, budget / 8),
                    taskHint: nil
                )
                if !extra.isEmpty {
                    block += "\n\nÉchanges plus récents non encore résumés :\n\(extra)"
                }
            }
            augmentBlocks.append(block)
        } else {
            let summary = summarizeDeterministic(
                older,
                maxChars: min(800, budget / 4),
                taskHint: taskHint
            )
            if !summary.isEmpty {
                augmentBlocks.append("Résumé des échanges précédents :\n\(summary)")
            }
        }

        let augment = augmentBlocks.joined(separator: "\n\n")
        let trimmed = trimToBudget(recent, budget: max(400, budget - augment.count))
        return Packet(
            systemAugment: augment,
            messages: trimmed,
            approximateChars: augment.count + trimmed.reduce(0) { $0 + $1.content.count }
        )
    }

    /// Résumé extractif déterministe (sans LLM) : derniers contenus tronqués.
    /// Repli uniquement — le résumé de qualité vient de `ConversationMemoryService`.
    private static func summarizeDeterministic(
        _ older: [LLMChatMessage],
        maxChars: Int,
        taskHint: String?
    ) -> String {
        var parts: [String] = []
        if let taskHint, !taskHint.isEmpty {
            parts.append("Tâche en cours : \(taskHint)")
        }
        // Prendre les derniers messages anciens (plus pertinents que les tout premiers).
        for msg in older.suffix(6) {
            let role = msg.role == .user ? "U" : (msg.role == .assistant ? "A" : "S")
            let clip = String(msg.content.prefix(160))
                .replacingOccurrences(of: "\n", with: " ")
            parts.append("\(role): \(clip)")
        }
        var text = parts.joined(separator: "\n")
        if text.count > maxChars {
            text = String(text.suffix(maxChars))
        }
        return text
    }

    private static func trimToBudget(_ messages: [LLMChatMessage], budget: Int) -> [LLMChatMessage] {
        var selected: [LLMChatMessage] = []
        var used = 0
        for msg in messages.reversed() {
            var content = msg.content
            let cost = content.count + 24
            if used + cost > budget {
                if selected.isEmpty {
                    content = GenerationContextBudget.clip(content, maxChars: max(80, budget - 24))
                    selected.insert(LLMChatMessage(role: msg.role, content: content), at: 0)
                }
                break
            }
            selected.insert(msg, at: 0)
            used += cost
        }
        return selected
    }
}
