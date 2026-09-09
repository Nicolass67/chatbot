import Foundation

/// Template / stop / sanitisation de sortie — **par profil de modèle**, pas hardcodé Qwen-only.
struct LocalModelRuntimeProfile: Equatable, Hashable, Sendable {
    enum ChatTemplateKind: String, Sendable, Hashable {
        case chatml
        case gemma
        case gemma4
        case granite
        case phi
        case generic
    }

    var templateKind: ChatTemplateKind
    /// Tokens de contrôle à ne jamais afficher (ChatML, etc.).
    var controlTokens: [String]
    /// Séquences qui terminent la génération assistant.
    var stopSequences: [String]
    /// Suffixe optionnel pour désactiver le « thinking » (ex. Qwen3 `/no_think`).
    var disableThinkingSuffix: String?
    /// Texte déjà « généré » après le header assistant (Qwen3 : think vide).
    var assistantGenerationPrefill: String
    var defaultContextLength: Int
    var defaultMaxOutputTokens: Int
    var defaultTemperature: Double
    /// Gemma 4 : canal thought optionnel. Défaut Hugging Face = false.
    var enableThinking: Bool

    static let chatmlQwen = LocalModelRuntimeProfile(
        templateKind: .chatml,
        controlTokens: [
            "<|im_start|>",
            "<|im_end|>",
            "<|endoftext|>",
            "<think>",
            "</think>",
        ],
        stopSequences: [
            "<|im_end|>",
            "<|im_start|>",
            "<|endoftext|>",
        ],
        disableThinkingSuffix: " /no_think",
        assistantGenerationPrefill: "<think>\n\n</think>\n\n",
        defaultContextLength: 2048,
        defaultMaxOutputTokens: 512,
        defaultTemperature: 0.7,
        enableThinking: false
    )

    static let gemma = LocalModelRuntimeProfile(
        templateKind: .gemma,
        controlTokens: [
            "<start_of_turn>",
            "<end_of_turn>",
            "<|turn>",
            "<turn|>",
            "<eos>",
        ],
        stopSequences: [
            "<end_of_turn>",
            "<turn|>",
            "<start_of_turn>",
        ],
        disableThinkingSuffix: nil,
        assistantGenerationPrefill: "",
        defaultContextLength: 2048,
        defaultMaxOutputTokens: 512,
        defaultTemperature: 0.7,
        enableThinking: false
    )

    static let gemma4E2B = LocalModelRuntimeProfile(
        templateKind: .gemma4,
        controlTokens: [
            "<|turn>",
            "<turn|>",
            "<bos>",
            "<eos>",
            "<|channel>thought",
            "<channel|>",
            "<|image|>",
        ],
        stopSequences: [
            "<turn|>",
            "<|turn>",
            "<eos>",
        ],
        disableThinkingSuffix: nil,
        assistantGenerationPrefill: "",
        defaultContextLength: 1536,
        defaultMaxOutputTokens: 512,
        defaultTemperature: 0.7,
        enableThinking: false
    )

    static let chatmlInstruct = LocalModelRuntimeProfile(
        templateKind: .chatml,
        controlTokens: [
            "<|im_start|>",
            "<|im_end|>",
            "<|endoftext|>",
        ],
        stopSequences: [
            "<|im_end|>",
            "<|im_start|>",
            "<|endoftext|>",
        ],
        disableThinkingSuffix: nil,
        assistantGenerationPrefill: "",
        defaultContextLength: 2048,
        defaultMaxOutputTokens: 512,
        defaultTemperature: 0.7,
        enableThinking: false
    )

    static let granite = LocalModelRuntimeProfile(
        templateKind: .granite,
        controlTokens: [
            "<|start_of_role|>",
            "<|end_of_role|>",
            "<|end_of_text|>",
        ],
        stopSequences: [
            "<|end_of_text|>",
            "<|start_of_role|>",
        ],
        disableThinkingSuffix: nil,
        assistantGenerationPrefill: "",
        defaultContextLength: 2048,
        defaultMaxOutputTokens: 512,
        defaultTemperature: 0.7,
        enableThinking: false
    )

    static let phi = LocalModelRuntimeProfile(
        templateKind: .phi,
        controlTokens: [
            "<|user|>",
            "<|assistant|>",
            "<|system|>",
            "<|end|>",
        ],
        stopSequences: [
            "<|end|>",
            "<|user|>",
        ],
        disableThinkingSuffix: nil,
        assistantGenerationPrefill: "",
        defaultContextLength: 2048,
        defaultMaxOutputTokens: 512,
        defaultTemperature: 0.7,
        enableThinking: false
    )

    static let generic = LocalModelRuntimeProfile(
        templateKind: .generic,
        controlTokens: ["<|im_start|>", "<|im_end|>", "<|endoftext|>"],
        stopSequences: ["<|im_end|>", "<|im_start|>", "\nUser:", "\nAssistant:"],
        disableThinkingSuffix: nil,
        assistantGenerationPrefill: "",
        defaultContextLength: 2048,
        defaultMaxOutputTokens: 512,
        defaultTemperature: 0.7,
        enableThinking: false
    )
}

/// Construction de prompt + troncature / sanitisation de sortie assistant.
enum LocalChatTemplate {
    /// Prompt multi-tours selon le profil runtime.
    static func buildPrompt(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int,
        profile: LocalModelRuntimeProfile
    ) -> String {
        switch profile.templateKind {
        case .chatml, .generic:
            return buildChatML(system: system, messages: messages, charBudget: charBudget, profile: profile)
        case .gemma:
            return buildGemma(system: system, messages: messages, charBudget: charBudget)
        case .gemma4:
            return buildGemma4(system: system, messages: messages, charBudget: charBudget, profile: profile)
        case .granite:
            return buildGranite(system: system, messages: messages, charBudget: charBudget)
        case .phi:
            return buildPhi(system: system, messages: messages, charBudget: charBudget)
        }
    }

    static func buildPrompt(
        system: String,
        user: String,
        profile: LocalModelRuntimeProfile
    ) -> String {
        var userText = user
        if let suffix = profile.disableThinkingSuffix, !userText.contains(suffix) {
            userText += suffix
        }
        return buildPrompt(
            system: system,
            messages: [LLMChatMessage(role: .user, content: userText)],
            charBudget: Int.max,
            profile: profile
        )
    }

    // MARK: - ChatML

    private static func buildChatML(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int,
        profile: LocalModelRuntimeProfile
    ) -> String {
        let imStart = "<|im_start|>"
        let imEnd = "<|im_end|>"
        var blocks: [String] = []
        blocks.append("\(imStart)system\n\(system)\n\(imEnd)")

        var selected: [LLMChatMessage] = []
        var used = system.count + 32
        for message in messages.reversed() {
            var content = message.content
            if message.role == .user, let suffix = profile.disableThinkingSuffix,
               !content.contains("/no_think") {
                content += suffix
            }
            let cost = content.count + 40
            if used + cost > charBudget {
                if selected.isEmpty {
                    let remain = max(80, charBudget - used - 40)
                    content = String(content.prefix(remain))
                    selected.insert(LLMChatMessage(role: message.role, content: content), at: 0)
                    used += content.count + 40
                }
                break
            }
            selected.insert(LLMChatMessage(role: message.role, content: content), at: 0)
            used += cost
        }

        for message in selected {
            blocks.append("\(imStart)\(message.role.rawValue)\n\(message.content)\n\(imEnd)")
        }
        blocks.append("\(imStart)assistant\n\(profile.assistantGenerationPrefill)")
        return blocks.joined(separator: "\n")
    }

    private static func buildGemma(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int
    ) -> String {
        // Format Gemma 2/3 style (Gemma 4 peut différer — profil dédié plus tard).
        var parts: [String] = []
        if !system.isEmpty {
            parts.append("<start_of_turn>user\n\(system)<end_of_turn>")
        }
        var selected: [LLMChatMessage] = []
        var used = system.count + 32
        for message in messages.reversed() {
            var content = message.content
            let cost = content.count + 40
            if used + cost > charBudget {
                if selected.isEmpty {
                    content = String(content.prefix(max(80, charBudget - used - 40)))
                    selected.insert(LLMChatMessage(role: message.role, content: content), at: 0)
                }
                break
            }
            selected.insert(message, at: 0)
            used += cost
        }
        for message in selected {
            let role = message.role == .assistant ? "model" : "user"
            parts.append("<start_of_turn>\(role)\n\(message.content)<end_of_turn>")
        }
        parts.append("<start_of_turn>model\n")
        return parts.joined(separator: "\n")
    }

    private static func buildGemma4(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int,
        profile: LocalModelRuntimeProfile
    ) -> String {
        var parts: [String] = ["<bos>"]
        if !system.isEmpty {
            parts.append("<|turn>system\n\(system)<turn|>")
        }
        var selected: [LLMChatMessage] = []
        var used = system.count + 32
        for message in messages.reversed() {
            var content = message.content
            let cost = content.count + 40
            if used + cost > charBudget {
                if selected.isEmpty {
                    content = String(content.prefix(max(80, charBudget - used - 40)))
                    selected.insert(LLMChatMessage(role: message.role, content: content), at: 0)
                }
                break
            }
            selected.insert(message, at: 0)
            used += cost
        }
        for message in selected {
            let role = message.role == .assistant ? "model" : "user"
            parts.append("<|turn>\(role)\n\(message.content)<turn|>")
        }
        if profile.enableThinking {
            parts.append("<|turn>model\n<|channel>thought\n")
        } else {
            parts.append("<|turn>model\n")
        }
        return parts.joined(separator: "\n")
    }

    private static func buildGranite(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int
    ) -> String {
        var parts: [String] = []
        if !system.isEmpty {
            parts.append("<|start_of_role|>system<|end_of_role|>\n\(system)<|end_of_text|>")
        }
        var selected: [LLMChatMessage] = []
        var used = system.count + 32
        for message in messages.reversed() {
            var content = message.content
            let cost = content.count + 48
            if used + cost > charBudget {
                if selected.isEmpty {
                    content = String(content.prefix(max(80, charBudget - used - 48)))
                    selected.insert(LLMChatMessage(role: message.role, content: content), at: 0)
                }
                break
            }
            selected.insert(message, at: 0)
            used += cost
        }
        for message in selected {
            let role = message.role == .assistant ? "assistant" : "user"
            parts.append("<|start_of_role|>\(role)<|end_of_role|>\n\(message.content)<|end_of_text|>")
        }
        parts.append("<|start_of_role|>assistant<|end_of_role|>\n")
        return parts.joined(separator: "\n")
    }

    private static func buildPhi(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int
    ) -> String {
        var parts: [String] = []
        if !system.isEmpty {
            parts.append("<|system|>\n\(system)<|end|>")
        }
        var selected: [LLMChatMessage] = []
        var used = system.count + 32
        for message in messages.reversed() {
            var content = message.content
            let cost = content.count + 32
            if used + cost > charBudget {
                if selected.isEmpty {
                    content = String(content.prefix(max(80, charBudget - used - 32)))
                    selected.insert(LLMChatMessage(role: message.role, content: content), at: 0)
                }
                break
            }
            selected.insert(message, at: 0)
            used += cost
        }
        for message in selected {
            if message.role == .assistant {
                parts.append("<|assistant|>\n\(message.content)<|end|>")
            } else {
                parts.append("<|user|>\n\(message.content)<|end|>")
            }
        }
        parts.append("<|assistant|>\n")
        return parts.joined(separator: "\n")
    }

    // MARK: - Sanitisation / stop

    struct TruncationResult: Equatable, Sendable {
        var text: String
        var hitStop: Bool
    }

    /// Retire **tous** les tokens de contrôle connus + motifs `<|...|>`.
    static func stripControlTokens(_ raw: String, profile: LocalModelRuntimeProfile) -> String {
        var text = raw
        for token in profile.controlTokens {
            text = text.replacingOccurrences(of: token, with: "")
        }
        // Défense générique : balises <|...|> restantes.
        if let regex = try? NSRegularExpression(pattern: #"<\|[^|>]*\|>"#, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return text
    }

    /// Coupe avant stop + strip contrôle. Ne laisse jamais un token spécial visible.
    ///
    /// Important : les balises think Qwen3 (open/close) **ne** doivent **pas** lever `hitStop`.
    /// Sinon le stream annule dès le premier bloc think → réponses vides quasi systématiques.
    static func truncateAssistantOutput(
        _ raw: String,
        profile: LocalModelRuntimeProfile = .chatmlQwen
    ) -> TruncationResult {
        var text = raw
        var hit = false

        // Qwen3 thinking : afficher uniquement le texte après la balise de fin ;
        // bloc ouvert → retenir (rien à montrer) mais continuer la génération.
        if let close = text.range(of: "</think>", options: .caseInsensitive) {
            text = String(text[close.upperBound...])
        } else if let open = text.range(of: "<think>", options: .caseInsensitive) {
            text = String(text[..<open.lowerBound])
        }

        if let close = text.range(of: "<channel|>") {
            text = String(text[close.upperBound...])
        } else if let open = text.range(of: "<|channel>thought") {
            text = String(text[..<open.lowerBound])
        }

        for stop in profile.stopSequences {
            if let range = text.range(of: stop) {
                text = String(text[..<range.lowerBound])
                hit = true
            }
        }

        if let idx = firstLegacyTurnBoundary(in: text) {
            text = String(text[..<idx])
            hit = true
        }

        let stripped = stripControlTokens(text, profile: profile)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Ne pas lever hitStop juste parce qu’on a retiré des balises de contrôle :
        // ça coupait le stream en plein milieu (think, im_start partiel, etc.).

        return TruncationResult(text: stripped, hitStop: hit)
    }

    /// Préfixe d’un token de contrôle / stop → ne pas encore émettre (évite `<|im_end|>` pièce par pièce).
    static func isPartialControlPrefix(_ suffix: String, profile: LocalModelRuntimeProfile) -> Bool {
        guard !suffix.isEmpty else { return false }
        let candidates = profile.controlTokens + profile.stopSequences + [
            "<|", "<start_of_turn", "<end_of_turn", "<|turn", "<turn|", "<|channel", "<channel|",
        ]
        for candidate in candidates {
            if candidate.hasPrefix(suffix), suffix.count < candidate.count {
                return true
            }
            // Suffixe qui continue un candidat (ex. "<|im_en").
            if candidate.count > 1 {
                for len in 1..<min(suffix.count, candidate.count) {
                    let end = suffix.suffix(len)
                    if candidate.hasPrefix(String(end)), end.count < candidate.count {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Streaming sûr : n’émet que du texte « gelé » (sans préfixe de token spécial).
    static func streamingSafeEmit(
        accumulated: String,
        alreadyEmittedCount: Int,
        profile: LocalModelRuntimeProfile
    ) -> (emit: String, newEmittedCount: Int, hitStop: Bool, displayText: String) {
        let cut = truncateAssistantOutput(accumulated, profile: profile)
        if cut.hitStop {
            let emit: String
            if cut.text.count > alreadyEmittedCount {
                let start = cut.text.index(cut.text.startIndex, offsetBy: alreadyEmittedCount)
                emit = String(cut.text[start...])
            } else {
                emit = ""
            }
            return (emit, cut.text.count, true, cut.text)
        }

        // Retenir un suffixe qui pourrait être un token spécial en cours.
        var frozen = cut.text
        let maxHold = 24
        if frozen.count > maxHold {
            let holdStart = frozen.index(frozen.endIndex, offsetBy: -maxHold)
            let suffix = String(frozen[holdStart...])
            if isPartialControlPrefix(suffix, profile: profile) {
                frozen = String(frozen[..<holdStart])
            } else {
                // Affiner : retenir le plus long suffixe qui est préfixe d’un contrôle.
                for len in (1...min(maxHold, frozen.count)).reversed() {
                    let idx = frozen.index(frozen.endIndex, offsetBy: -len)
                    let suf = String(frozen[idx...])
                    if isPartialControlPrefix(suf, profile: profile) {
                        frozen = String(frozen[..<idx])
                        break
                    }
                }
            }
        } else if isPartialControlPrefix(frozen, profile: profile) {
            frozen = ""
        }

        let emit: String
        if frozen.count > alreadyEmittedCount {
            let start = frozen.index(frozen.startIndex, offsetBy: alreadyEmittedCount)
            emit = String(frozen[start...])
        } else {
            emit = ""
        }
        return (emit, frozen.count, false, frozen)
    }

    private static func firstLegacyTurnBoundary(in text: String) -> String.Index? {
        let markers = ["\nUser:", "\nAssistant:", "\nSystem:"]
        var earliest: String.Index?
        for marker in markers {
            if let range = text.range(of: marker) {
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

/// Compat : ancien nom utilisé par les appels existants.
enum ChatMLPromptBuilder {
    static let imStart = "<|im_start|>"
    static let imEnd = "<|im_end|>"

    static func buildPrompt(
        system: String,
        messages: [LLMChatMessage],
        charBudget: Int
    ) -> String {
        LocalChatTemplate.buildPrompt(
            system: system,
            messages: messages,
            charBudget: charBudget,
            profile: .chatmlQwen
        )
    }

    static func buildPrompt(system: String, user: String) -> String {
        LocalChatTemplate.buildPrompt(system: system, user: user, profile: .chatmlQwen)
    }

    static func truncateAssistantOutput(_ raw: String) -> LocalChatTemplate.TruncationResult {
        LocalChatTemplate.truncateAssistantOutput(raw, profile: .chatmlQwen)
    }

    static func stripControlTokens(_ raw: String) -> String {
        LocalChatTemplate.stripControlTokens(raw, profile: .chatmlQwen)
    }
}
