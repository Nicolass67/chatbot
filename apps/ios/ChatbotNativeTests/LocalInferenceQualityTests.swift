import XCTest
@testable import ChatbotNative

// MARK: - Échantillonnage

final class LlamaSamplingConfigTests: XCTestCase {
    /// Valeurs publiées par Qwen pour Qwen3 / Qwen3.5 en mode non-thinking.
    func testInstructPresetMatchesQwenRecommendations() {
        let s = LlamaSamplingConfig.qwenInstruct
        XCTAssertEqual(s.temperature, 0.7, accuracy: 0.0001)
        XCTAssertEqual(s.topP, 0.8, accuracy: 0.0001)
        XCTAssertEqual(s.topK, 20)
        XCTAssertEqual(s.minP, 0.0, accuracy: 0.0001)
    }

    /// Mode thinking : température plus basse, top_p plus large, et surtout
    /// pas de presence penalty (elle hache les chaînes de raisonnement).
    func testThinkingPresetMatchesQwenRecommendations() {
        let s = LlamaSamplingConfig.qwenThinking
        XCTAssertEqual(s.temperature, 0.6, accuracy: 0.0001)
        XCTAssertEqual(s.topP, 0.95, accuracy: 0.0001)
        XCTAssertEqual(s.topK, 20)
        XCTAssertEqual(s.presencePenalty, 0.0, accuracy: 0.0001)
    }

    /// Un seed fixe rendait « régénérer » strictement identique à chaque appel.
    func testAllPresetsUseRandomSeed() {
        for preset in [
            LlamaSamplingConfig.qwenInstruct,
            .qwenThinking,
            .structured,
            .factual,
        ] {
            XCTAssertEqual(preset.seed, LlamaSamplingConfig.randomSeed)
        }
    }

    func testStructuredPresetDisablesPenaltiesForJSON() {
        // Les pénalités de répétition cassent le JSON : `{`, `"`, `:` reviennent
        // légitimement des dizaines de fois.
        XCTAssertFalse(LlamaSamplingConfig.structured.usesPenalties)
        XCTAssertTrue(LlamaSamplingConfig.qwenInstruct.usesPenalties)
    }
}

// MARK: - Configuration du contexte

final class LlamaContextConfigTests: XCTestCase {
    func testQuantizedKVForcesFlashAttention() {
        var config = LlamaInferenceConfig.a15Default
        config.kvCacheTypeK = .q8_0
        config.kvCacheTypeV = .q8_0
        config.flashAttention = .disabled
        // Metal refuse un KV quantifié sans Flash Attention : la config doit se
        // corriger elle-même plutôt que d'échouer à l'ouverture du contexte.
        XCTAssertEqual(config.effectiveFlashAttention, .enabled)

        config.kvCacheTypeK = .f16
        config.kvCacheTypeV = .f16
        XCTAssertEqual(config.effectiveFlashAttention, .disabled)
    }

    func testContextLadderIsDescendingAndDeduplicated() {
        var config = LlamaInferenceConfig.a15Default
        config.nCtx = 6144
        config.contextLadder = [6144, 4096, 4096, 256, 2048]
        // `nCtx` en tête, doublons retirés, valeurs inutilisables écartées.
        XCTAssertEqual(config.resolvedContextLadder, [6144, 4096, 2048])
    }

    func testKVCacheSizingShrinksWithQuantization() {
        let sizing = KVCacheSizing.qwen35Dense2B
        let f16 = sizing.bytes(context: 4096, typeK: .f16, typeV: .f16)
        let q8 = sizing.bytes(context: 4096, typeK: .q8_0, typeV: .q8_0)
        XCTAssertGreaterThan(f16, q8)
        // q8_0 ≈ 1,0625 octet/élément contre 2 en f16 : un peu plus de la moitié.
        XCTAssertEqual(Double(q8) / Double(f16), 0.53, accuracy: 0.02)
    }

    func testKVCacheSizingUsesConservativeProfileForUnknownModels() {
        let known = KVCacheSizing.profile(for: "qwen35-2b-q4_k_m")
        let unknown = KVCacheSizing.profile(for: "un-modele-inconnu")
        XCTAssertEqual(known, .qwen35Dense2B)
        XCTAssertGreaterThan(
            unknown.bytes(context: 4096, typeK: .q8_0, typeV: .q8_0),
            known.bytes(context: 4096, typeK: .q8_0, typeV: .q8_0)
        )
    }
}

// MARK: - Réécriture de requête

final class QueryRewriterTests: XCTestCase {
    private let history = [
        LLMChatMessage(role: .user, content: "Quelles sont les spécificités du moteur A15 Bionic ?"),
        LLMChatMessage(role: .assistant, content: "L’A15 Bionic embarque 6 cœurs CPU et 5 cœurs GPU, gravé en 5 nm."),
    ]

    func testAnaphoricFollowUpIsExpanded() {
        let rewritten = QueryRewriter.retrievalQuery(userText: "et lui ?", history: history)
        XCTAssertNotEqual(rewritten, "et lui ?")
        XCTAssertTrue(rewritten.hasPrefix("et lui ?"))
        XCTAssertTrue(rewritten.contains("A15 Bionic"))
    }

    func testSelfContainedQuestionIsUntouched() {
        let question = "Quelle est la différence entre la mémoire unifiée et la mémoire dédiée sur Mac ?"
        XCTAssertEqual(QueryRewriter.retrievalQuery(userText: question, history: history), question)
    }

    func testNoHistoryLeavesQueryUnchanged() {
        XCTAssertEqual(QueryRewriter.retrievalQuery(userText: "et lui ?", history: []), "et lui ?")
    }

    func testContinuationVerbsNeedContext() {
        XCTAssertTrue(QueryRewriter.needsContext("développe"))
        XCTAssertTrue(QueryRewriter.needsContext("et pour Berlin ?"))
        XCTAssertTrue(QueryRewriter.needsContext("pourquoi ?"))
        XCTAssertFalse(QueryRewriter.needsContext("Donne-moi la recette complète des lasagnes vegan maison"))
    }

    /// Un tour précédent lui-même elliptique n'ancre rien : il faut remonter.
    func testAnchorSkipsElliptiqueUserTurns() {
        let chained = history + [
            LLMChatMessage(role: .user, content: "et ça ?"),
        ]
        let rewritten = QueryRewriter.retrievalQuery(userText: "et lui ?", history: chained)
        XCTAssertTrue(rewritten.contains("A15 Bionic"))
    }
}

// MARK: - Routage sémantique

final class SemanticRouterTests: XCTestCase {
    func testExplicitDetailRequestGetsDetailedBudget() async {
        let route = await SemanticRouter.shared.route(
            userText: "Explique-moi la photosynthèse en détail",
            history: []
        )
        XCTAssertEqual(route.task, .detailed)
        XCTAssertEqual(route.intent, .explanation)
    }

    func testComparisonEnablesThinking() async {
        let route = await SemanticRouter.shared.route(
            userText: "Compare Swift et Kotlin pour une app mobile",
            history: []
        )
        XCTAssertEqual(route.intent, .reasoning)
        XCTAssertTrue(route.useThinking)
    }

    func testGreetingStaysShortWithoutThinking() async {
        let route = await SemanticRouter.shared.route(userText: "Bonjour", history: [])
        XCTAssertEqual(route.task, .short)
        XCTAssertEqual(route.intent, .smalltalk)
        XCTAssertFalse(route.useThinking)
    }

    /// Un suivi elliptique ne doit jamais déclencher réflexion ni format long :
    /// le sujet vient du contexte, pas d'une demande d'approfondissement.
    func testFollowUpNeverEnablesThinking() async {
        let history = [
            LLMChatMessage(role: .user, content: "Compare les avantages et les inconvénients du diesel et de l’électrique"),
            LLMChatMessage(role: .assistant, content: "L’électrique coûte plus cher à l’achat mais moins à l’usage."),
        ]
        let route = await SemanticRouter.shared.route(userText: "et lui ?", history: history)
        XCTAssertFalse(route.useThinking)
        XCTAssertNotEqual(route.task, .detailed)
    }

    func testThinkingBudgetAddsToOutputTokensOnlyWhenAdaptive() {
        let profile = LocalModelExecutionProfile.qwen35Dense2B
        let thinking = SemanticRouter.Route(
            task: .detailed,
            intent: .reasoning,
            useThinking: true,
            confidence: 1,
            source: "test"
        )
        XCTAssertEqual(
            thinking.outputTokens(profile: profile),
            profile.outputTokens(for: .detailed) + profile.thinkingTokenBudget
        )

        var nonAdaptive = profile
        nonAdaptive.adaptiveThinking = false
        XCTAssertEqual(
            thinking.outputTokens(profile: nonAdaptive),
            nonAdaptive.outputTokens(for: .detailed)
        )
    }

    func testFactualIntentTightensSamplingTail() {
        let route = SemanticRouter.Route(
            task: .short,
            intent: .factual,
            useThinking: false,
            confidence: 1,
            source: "test"
        )
        let options = route.generationOptions(profile: .qwen35Dense2B)
        guard let sampling = options.sampling else {
            return XCTFail("le routeur doit fournir un échantillonnage explicite")
        }
        XCTAssertLessThan(sampling.topP, LlamaSamplingConfig.qwenInstruct.topP)
        XCTAssertLessThan(sampling.temperature, LlamaSamplingConfig.qwenInstruct.temperature)
    }
}

// MARK: - Grammaires GBNF

final class ToolCallGrammarTests: XCTestCase {
    func testAgentStepListsOnlyRegisteredTools() {
        let grammar = ToolCallGrammar.agentStep(toolNames: ["web_search", "mail_list"])
        XCTAssertNotNil(grammar)
        XCTAssertTrue(grammar!.contains("\\\"web_search\\\""))
        XCTAssertTrue(grammar!.contains("\\\"mail_list\\\""))
        XCTAssertFalse(grammar!.contains("search_web"))
        XCTAssertTrue(grammar!.hasPrefix("root      ::= toolCall | finalAnswer"))
    }

    func testAgentStepIsNilWithoutTools() {
        XCTAssertNil(ToolCallGrammar.agentStep(toolNames: []))
        XCTAssertNil(ToolCallGrammar.agentStep(toolNames: [""]))
    }

    /// Toute règle référencée doit être définie, sinon llama.cpp rejette la
    /// grammaire au chargement et on retombe silencieusement en non contraint.
    func testGrammarsDefineEveryReferencedRule() {
        let grammars = [
            ToolCallGrammar.agentPlan,
            ToolCallGrammar.memoryFacts,
            ToolCallGrammar.agentStep(toolNames: ["a_tool"])!,
        ]
        for grammar in grammars {
            let defined = Set(
                grammar
                    .split(separator: "\n")
                    .compactMap { line -> String? in
                        guard let range = line.range(of: "::=") else { return nil }
                        return line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                    }
                    .filter { !$0.isEmpty }
            )
            XCTAssertTrue(defined.contains("root"), "grammaire sans règle root")
            for rule in ["ws", "string", "char", "escape"] where grammar.contains(" \(rule)") {
                XCTAssertTrue(defined.contains(rule), "règle « \(rule) » référencée mais non définie")
            }
        }
    }
}

// MARK: - Cache de prompt disque

final class PromptPrefixCacheTests: XCTestCase {
    /// `Hasher` de Swift est réamorcé à chaque lancement : une clé bâtie dessus
    /// n'aurait jamais retrouvé son entrée après un redémarrage.
    func testStableHashIsDeterministic() {
        let a = PromptPrefixCache.stableHash("Tu es l’assistant local.")
        let b = PromptPrefixCache.stableHash("Tu es l’assistant local.")
        let c = PromptPrefixCache.stableHash("Tu es l’assistant local!")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSignatureChangesWithAnyContextParameter() {
        var config = LlamaInferenceConfig.a15Default
        let base = PromptPrefixCache.signature(modelId: "qwen35", config: config, prompt: "SYS")

        config.nCtx = 4096
        XCTAssertNotEqual(base, PromptPrefixCache.signature(modelId: "qwen35", config: config, prompt: "SYS"))

        config = .a15Default
        config.kvCacheTypeK = .f16
        config.kvCacheTypeV = .f16
        XCTAssertNotEqual(base, PromptPrefixCache.signature(modelId: "qwen35", config: config, prompt: "SYS"))

        config = .a15Default
        XCTAssertNotEqual(base, PromptPrefixCache.signature(modelId: "autre", config: config, prompt: "SYS"))
        XCTAssertNotEqual(base, PromptPrefixCache.signature(modelId: "qwen35", config: config, prompt: "AUTRE"))
    }

    /// Le préfixe mis en cache doit être un vrai préfixe du prompt assemblé,
    /// sinon l'état KV restauré décrit un texte que le modèle n'a pas reçu.
    func testStableCachePrefixIsAPrefixOfTheRealPrompt() {
        let system = LocalPrompts.conversation
        let prefix = LocalChatTemplate.stableCachePrefix(
            staticSystem: system,
            profile: .chatmlQwen
        )
        XCTAssertNotNil(prefix)

        let full = LocalChatTemplate.assembleChatML(
            system: system + "\n\nContexte temporel (interne — variable)",
            messages: [LLMChatMessage(role: .user, content: "Salut")],
            profile: .chatmlQwen
        )
        XCTAssertTrue(full.hasPrefix(prefix!))
    }

    func testStableCachePrefixUnavailableForNonChatMLTemplates() {
        XCTAssertNil(
            LocalChatTemplate.stableCachePrefix(staticSystem: "SYS", profile: .gemma4E2B)
        )
        XCTAssertNil(
            LocalChatTemplate.stableCachePrefix(staticSystem: "", profile: .chatmlQwen)
        )
    }
}

// MARK: - Mémoire long terme

@MainActor
final class LocalMemoryStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LocalMemoryStore.shared.forgetAll()
    }

    override func tearDown() {
        LocalMemoryStore.shared.forgetAll()
        super.tearDown()
    }

    func testRejectsDuplicatesRegardlessOfCaseAndAccents() {
        XCTAssertTrue(LocalMemoryStore.shared.remember("L’utilisateur est développeur Swift à Lyon."))
        XCTAssertFalse(LocalMemoryStore.shared.remember("l'utilisateur est developpeur swift a lyon"))
        XCTAssertEqual(LocalMemoryStore.shared.count, 1)
    }

    func testRejectsTooShortAndTooLongFacts() {
        XCTAssertFalse(LocalMemoryStore.shared.remember("ok"))
        XCTAssertFalse(LocalMemoryStore.shared.remember(String(repeating: "x", count: 401)))
        XCTAssertEqual(LocalMemoryStore.shared.count, 0)
    }

    func testRecallRespectsCharacterBudget() {
        for i in 0..<20 {
            LocalMemoryStore.shared.remember("L’utilisateur possède l’appareil numéro \(i) de la collection.")
        }
        let recalled = LocalMemoryStore.shared.recall(matching: "appareil", budget: 120)
        XCTAssertLessThanOrEqual(recalled.count, 120)
    }

    func testRecallOnEmptyStoreReturnsEmptyString() {
        XCTAssertEqual(LocalMemoryStore.shared.recall(matching: "quoi que ce soit", budget: 400), "")
    }

    func testRememberAllCountsOnlyInsertions() {
        let inserted = LocalMemoryStore.shared.rememberAll([
            "L’utilisateur habite à Marseille depuis 2019.",
            "L’utilisateur habite à Marseille depuis 2019.",
            "no",
        ])
        XCTAssertEqual(inserted, 1)
    }
}

// MARK: - Extraction de faits

final class ConversationMemoryParsingTests: XCTestCase {
    func testParsesFactsFromGrammarConstrainedJSON() {
        let raw = #"{"facts":["L’utilisateur est photographe.","L’utilisateur vit à Nantes."]}"#
        XCTAssertEqual(ConversationMemoryService.parseFacts(raw).count, 2)
    }

    func testToleratesSurroundingText() {
        let raw = "Voici :\n{\"facts\":[\"L’utilisateur aime le café serré.\"]}\nFin."
        XCTAssertEqual(
            ConversationMemoryService.parseFacts(raw),
            ["L’utilisateur aime le café serré."]
        )
    }

    func testEmptyAndMalformedPayloadsYieldNoFacts() {
        XCTAssertTrue(ConversationMemoryService.parseFacts(#"{"facts":[]}"#).isEmpty)
        XCTAssertTrue(ConversationMemoryService.parseFacts("pas du json").isEmpty)
        XCTAssertTrue(ConversationMemoryService.parseFacts(#"{"autre":["x"]}"#).isEmpty)
    }

    func testCapsFactCountAndFiltersNoise() {
        let many = (0..<12).map { "L’utilisateur possède l’objet numéro \($0)." }
        let payload = try! String(
            data: JSONSerialization.data(withJSONObject: ["facts": many]),
            encoding: .utf8
        )!
        XCTAssertEqual(ConversationMemoryService.parseFacts(payload).count, 5)
        XCTAssertTrue(ConversationMemoryService.parseFacts(#"{"facts":["ok","x"]}"#).isEmpty)
    }
}

// MARK: - Template Qwen

final class QwenChatTemplateFidelityTests: XCTestCase {
    /// Le template officiel Qwen ne met pas de saut de ligne avant `<|im_end|>`.
    /// Un `\n` en trop décale chaque bloc par rapport à l'entraînement.
    func testBlocksEndWithoutExtraNewline() {
        let block = LocalChatTemplate.renderChatMLBlock(
            LLMChatMessage(role: .user, content: "Bonjour")
        )
        XCTAssertEqual(block, "<|im_start|>user\nBonjour<|im_end|>")

        let system = LocalChatTemplate.renderChatMLSystemBlock("SYS")
        XCTAssertEqual(system, "<|im_start|>system\nSYS<|im_end|>")
    }

    func testNonThinkingHeaderPrefillsEmptyThinkBlock() {
        let header = LocalChatTemplate.renderChatMLAssistantHeader(.chatmlQwen)
        XCTAssertEqual(header, "<|im_start|>assistant\n<think>\n\n</think>\n\n")
    }

    func testThinkingProfileOpensThinkBlock() {
        let header = LocalChatTemplate.renderChatMLAssistantHeader(.chatmlQwenThinking)
        XCTAssertEqual(header, "<|im_start|>assistant\n<think>\n")
    }

    func testAssembledPromptIsStableAcrossCallsForIdenticalInput() {
        let messages = [LLMChatMessage(role: .user, content: "Salut")]
        let first = LocalChatTemplate.assembleChatML(system: "SYS", messages: messages, profile: .chatmlQwen)
        let second = LocalChatTemplate.assembleChatML(system: "SYS", messages: messages, profile: .chatmlQwen)
        // Toute variation ici invaliderait la réutilisation du préfixe KV.
        XCTAssertEqual(first, second)
    }
}
