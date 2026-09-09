import Foundation

/// Ajuste le prompt au budget **en tokens** du moteur, en une seule passe.
///
/// Remplace la boucle « construire avec un budget en caractères → tokeniser →
/// si ça dépasse, tronquer et tout recommencer ». Cette boucle tokenisait le
/// prompt jusqu'à quatre fois et, à chaque reprise, invalidait le préfixe du
/// cache KV : le tour entier était réencodé depuis le prompt système.
///
/// Ici le budget est respecté par construction : deux tokenisations au total,
/// et le préfixe conservé est celui du tour précédent.
enum LocalPromptFitter {
    struct Result: Sendable {
        var prompt: String
        var promptTokens: Int
        var keptMessages: Int
        var droppedMessages: Int
        var truncatedOldest: Bool

        var traceFields: [String: String] {
            [
                "prompt_tokens": "\(promptTokens)",
                "kept_messages": "\(keptMessages)",
                "dropped_messages": "\(droppedMessages)",
                "truncated": truncatedOldest ? "yes" : "no",
            ]
        }
    }

    /// - Parameter tokenBudget: plafond **prompt seul**, sortie déjà déduite.
    static func fit(
        system: String,
        messages: [LLMChatMessage],
        profile: LocalModelRuntimeProfile,
        tokenBudget: Int,
        engine: LocalInferenceEngine
    ) async -> Result {
        let budget = max(128, tokenBudget)

        // Templates non-ChatML : rendu bloc par bloc non exposé, on garde la
        // sélection par caractères puis on mesure le résultat.
        guard profile.templateKind == .chatml || profile.templateKind == .generic else {
            let prompt = LocalChatTemplate.buildPrompt(
                system: system,
                messages: messages,
                charBudget: max(400, budget * 3),
                profile: profile
            )
            let tokens = await engine.countTokens(prompt)
                ?? GenerationContextBudget.estimateTokens(prompt)
            return Result(
                prompt: prompt,
                promptTokens: tokens,
                keptMessages: messages.count,
                droppedMessages: 0,
                truncatedOldest: false
            )
        }

        // Le BOS est compté avec le bloc système : `assembleChatML` le préfixe
        // au prompt final, l'oublier fait sortir du budget d'un token.
        let systemBlock = profile.bosPrefix + LocalChatTemplate.renderChatMLSystemBlock(system)
        let assistantHeader = LocalChatTemplate.renderChatMLAssistantHeader(profile)
        let messageBlocks = messages.map(LocalChatTemplate.renderChatMLBlock)

        let counts = await engine.countTokens(batch: [systemBlock, assistantHeader] + messageBlocks)
        let systemTokens = counts[0]
        let headerTokens = counts[1]
        let blockTokens = Array(counts.dropFirst(2))

        // Chaque bloc est joint par un `\n`, soit un token supplémentaire.
        let joinCost = 1
        var used = systemTokens + headerTokens + joinCost
        var keptIndices: [Int] = []

        for index in messages.indices.reversed() {
            let cost = blockTokens[index] + joinCost
            if used + cost > budget { break }
            used += cost
            keptIndices.append(index)
        }
        keptIndices.reverse()

        var selected = keptIndices.map { messages[$0] }
        var truncatedOldest = false

        if selected.isEmpty, let newest = messages.last {
            // Même seul, le dernier message dépasse : on le rogne au ratio mesuré
            // plutôt que de rendre un prompt vide.
            let available = max(64, budget - systemTokens - headerTokens - joinCost)
            let measured = max(1, blockTokens[messages.count - 1])
            let ratio = min(1.0, Double(available) / Double(measured)) * 0.9
            let keepChars = max(80, Int(Double(newest.content.count) * ratio))
            selected = [LLMChatMessage(
                role: newest.role,
                content: String(newest.content.prefix(keepChars))
            )]
            truncatedOldest = true
        }

        // Un historique qui commence par un tour assistant n'a pas de question à
        // laquelle il répond : le modèle l'interprète comme un monologue.
        while selected.count > 1, selected.first?.role == .assistant {
            selected.removeFirst()
        }

        let prompt = LocalChatTemplate.assembleChatML(
            system: system,
            messages: selected,
            profile: profile
        )
        let exactTokens = await engine.countTokens(prompt)
            ?? GenerationContextBudget.estimateTokens(prompt)

        return Result(
            prompt: prompt,
            promptTokens: exactTokens,
            keptMessages: selected.count,
            droppedMessages: max(0, messages.count - selected.count),
            truncatedOldest: truncatedOldest
        )
    }
}
