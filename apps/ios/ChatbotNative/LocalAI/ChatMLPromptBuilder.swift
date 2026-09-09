import Foundation

/// Construction ChatML (Qwen / ChatML) partagée Chat + Mail Assistant.
/// Ne dépend pas du backend PC.
enum ChatMLPromptBuilder {
    static let imStart = "<|im_start|>"
    static let imEnd = "<|im_end|>"

    /// Prompt multi-tours + amorce `assistant` (génération).
    static func buildPrompt(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int
    ) -> String {
        var blocks: [String] = []
        blocks.append(block(role: "system", content: system))

        var selected: [LLMChatMessage] = []
        var used = system.count + 32
        for message in messages.reversed() {
            let cost = message.content.count + 40
            if used + cost > charBudget, !selected.isEmpty {
                break
            }
            selected.insert(message, at: 0)
            used += cost
        }

        for message in selected {
            // Les messages `system` additionnels restent dans le fil (rare).
            blocks.append(block(role: message.role.rawValue, content: message.content))
        }
        // Generation prompt — le modèle complète à partir d’ici.
        blocks.append("\(imStart)assistant\n")
        return blocks.joined(separator: "\n")
    }

    /// Variante 1 tour user (Mail Assistant).
    static func buildPrompt(system: String, user: String) -> String {
        buildPrompt(
            system: system,
            messages: [LLMChatMessage(role: .user, content: user)],
            charBudget: Int.max
        )
    }

    private static func block(role: String, content: String) -> String {
        "\(imStart)\(role)\n\(content)\n\(imEnd)"
    }

    // MARK: - Stop / troncature sortie assistant

    struct TruncationResult: Equatable, Sendable {
        var text: String
        var hitStop: Bool
    }

    /// Coupe la sortie assistant avant un nouveau tour (ChatML ou transcript legacy).
    /// Ne coupe pas un simple mot « User: » au milieu d’une phrase : uniquement
    /// séparateurs de tour en début de ligne / marqueurs ChatML.
    static func truncateAssistantOutput(_ raw: String) -> TruncationResult {
        var text = raw
        var hit = false

        if let range = text.range(of: imEnd) {
            text = String(text[..<range.lowerBound])
            hit = true
        }

        if let range = text.range(of: imStart) {
            text = String(text[..<range.lowerBound])
            hit = true
        }

        if let idx = firstLegacyTurnBoundary(in: text) {
            text = String(text[..<idx])
            hit = true
        }

        // Nettoyage espaces / newlines trainants après coupe.
        while text.hasSuffix("\n") || text.hasSuffix(" ") {
            text.removeLast()
        }

        return TruncationResult(text: text, hitStop: hit)
    }

    /// Index du premier `\nUser:` / `\nAssistant:` / `\nSystem:` en début de ligne
    /// (après le début du buffer — un faux tour suivant).
    private static func firstLegacyTurnBoundary(in text: String) -> String.Index? {
        let markers = ["\nUser:", "\nAssistant:", "\nSystem:"]
        var earliest: String.Index?
        for marker in markers {
            if let range = text.range(of: marker) {
                // Exiger que ce soit bien un rôle de tour : "User:" suivi d’espace ou fin.
                let after = range.upperBound
                let okSuffix: Bool
                if after == text.endIndex {
                    okSuffix = true
                } else {
                    let ch = text[after]
                    okSuffix = ch == " " || ch == "\n" || ch == "\t"
                }
                guard okSuffix else { continue }
                if earliest == nil || range.lowerBound < earliest! {
                    earliest = range.lowerBound
                }
            }
        }
        return earliest
    }
}
