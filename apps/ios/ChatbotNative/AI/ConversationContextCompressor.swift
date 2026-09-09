import Foundation

/// Compression de contexte réutilisable (Chat / Mail / Agent / Web / Files).
/// Pas de `prefix(N)` aveugle : récents + résumé des anciens.
enum ConversationContextCompressor {
    struct Packet: Equatable, Sendable {
        var systemAugment: String
        var messages: [LLMChatMessage]
        var approximateChars: Int
    }

    static func compress(
        history: [LLMChatMessage],
        profile: LocalModelExecutionProfile,
        taskHint: String? = nil
    ) -> Packet {
        let budget = profile.contextCharBudget
        let keepRecent = max(2, profile.historyMessageBudget)

        guard !history.isEmpty else {
            return Packet(systemAugment: "", messages: [], approximateChars: 0)
        }

        if history.count <= keepRecent {
            let trimmed = trimToBudget(history, budget: budget)
            return Packet(
                systemAugment: "",
                messages: trimmed,
                approximateChars: trimmed.reduce(0) { $0 + $1.content.count }
            )
        }

        let older = Array(history.dropLast(keepRecent))
        let recent = Array(history.suffix(keepRecent))
        let summary = summarizeDeterministic(older, maxChars: min(800, budget / 4), taskHint: taskHint)
        var messages = recent
        var augment = ""
        if !summary.isEmpty {
            augment = "Résumé des échanges précédents :\n\(summary)"
        }
        let trimmed = trimToBudget(messages, budget: max(400, budget - augment.count))
        return Packet(
            systemAugment: augment,
            messages: trimmed,
            approximateChars: augment.count + trimmed.reduce(0) { $0 + $1.content.count }
        )
    }

    /// Résumé extractif déterministe (pas de LLM) : derniers contenus user/assistant tronqués.
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
            var cost = content.count + 24
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
