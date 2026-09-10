import Foundation

/// Workflows métier **uniques** — PC et local = même logique, budgets via runtime.profile.
enum ChatWorkflow {
    struct Request: Sendable {
        var userText: String
        var history: [LLMChatMessage]
        var systemPrompt: String
        var taskHint: String?
        /// Active le résumé roulant et la mémoire persistante de ce fil.
        var conversationId: String?
    }

    struct Result: Sendable {
        var text: String
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> Result {
        // Le moteur local est unique : un résumé de fond encore en vol
        // retarderait le premier token de ce tour.
        ConversationMemoryService.shared.yieldEngine()

        let profile = runtime.executionProfile
        // « et lui ? » n'est pas une clé de recherche : on la rattache aux tours
        // précédents avant d'interroger la mémoire. Le prompt, lui, reste intact.
        let recallQuery = QueryRewriter.retrievalQuery(
            userText: request.userText,
            history: request.history
        )
        let packet = ConversationContextCompressor.compress(
            history: request.history,
            profile: profile,
            taskHint: request.taskHint,
            conversationId: request.conversationId,
            recallQuery: recallQuery
        )
        var system = request.systemPrompt
        if !packet.systemAugment.isEmpty {
            system += "\n\n" + packet.systemAugment
        }
        // Le bloc horloge est déjà posé par `LocalPrompts.systemPrompt(for:)`.
        // Il était ajouté une seconde fois ici : deux dates identiques dans le
        // même message système, et un préfixe de prompt qui change à chaque
        // requête sans rien apporter.
        if !RuntimeTemporalContext.containsClockBlock(system) {
            system += "\n\n" + RuntimeTemporalContext.silentClockBlock()
        }
        // Relance elliptique : nommer le sujet évite que le modèle réinterprète
        // un mot ambigu (« les modèles ») hors de son contexte.
        if let subject = QueryRewriter.subjectAnchor(
            userText: request.userText,
            history: request.history
        ) {
            system += "\n\nSujet en cours de la conversation — le message de l’utilisateur s’y rapporte, "
                + "ne change pas de sujet :\n« \(subject) »"
        }
        var messages = packet.messages
        let grounded = QueryRewriter.groundedUserTurn(
            userText: request.userText,
            history: request.history
        )
        if let last = messages.indices.last, messages[last].role == .user {
            messages[last].content = grounded
        } else {
            messages.append(LLMChatMessage(role: .user, content: grounded))
        }

        // Routage sémantique : longueur de réponse et réflexion décidées par
        // similarité d'intention, pas par une liste de mots-clés.
        let route = await SemanticRouter.shared.route(
            userText: request.userText,
            history: request.history
        )
        let maxTokens = route.outputTokens(profile: profile)
        let options = route.generationOptions(profile: profile)
        WorkflowTrace.log("route", route.traceFields)

        let text = try await runtime.generateLocal(
            system: system,
            messages: messages,
            maxTokens: maxTokens,
            options: options,
            onToken: onToken
        )

        // Après coup uniquement : résumé roulant et extraction de faits ne doivent
        // rien ajouter au délai avant le premier token.
        ConversationMemoryService.shared.ingestTurn(
            conversationId: request.conversationId,
            history: request.history + [
                LLMChatMessage(role: .user, content: request.userText),
                LLMChatMessage(role: .assistant, content: text),
            ],
            userText: request.userText,
            assistantText: text,
            runtime: runtime
        )
        return Result(text: text)
    }
}

/// Agent = plan → outils → synthèse. Budgets = ExecutionProfile uniquement.
/// Événements = même modèle que le SSE PC (`AgentOrchestrationEvent`).
enum AgentWorkflow {
    struct Request: Sendable {
        var userText: String
        var history: [LLMChatMessage]
        var threadId: String?
        var scopeHint: String?
    }

    struct Result: Sendable {
        var text: String
        var stepsUsed: Int
        var toolCallsUsed: Int
        var sources: [SearchSourceDTO]
        var mailThreadId: String?
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        tools: AIToolRegistry,
        onEvent: ((AgentOrchestrationEvent) -> Void)? = nil,
        onFinalToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> Result {
        ConversationMemoryService.shared.yieldEngine()
        let profile = runtime.executionProfile
        var toolCalls = 0
        var steps = 0
        var scratch: [String] = []
        var lastToolSignature: String?
        var collectedSources: [SearchSourceDTO] = []
        var mailThreadId: String?
        let firstTool = deterministicFirstTool(for: request)
        // Le plan est de l'affichage, pas du raisonnement : le faire écrire par
        // le modèle coûtait une génération complète (prefill + ~200 tokens)
        // pour produire « Collecter / Analyser / Répondre ».
        var plan = clampPlanSteps(goalAwareFallbackPlan(userText: request.userText, firstTool: firstTool))

        WorkflowTrace.log("workflow", [
            "type": "agent",
            "runtime": "local",
            "steps": "\(profile.maxWorkflowSteps)",
            "plan_count": "\(plan.count)",
            "year": "\(RuntimeTemporalContext.currentYear())",
        ])
        onEvent?(.started)
        onEvent?(.plan(steps: plan))

        func markIndex(_ index: Int, running: Bool) {
            guard plan.indices.contains(index) else { return }
            if running {
                plan[index].status = "running"
                onEvent?(.stepStarted(id: plan[index].id, title: plan[index].title))
            } else {
                plan[index].status = "done"
                onEvent?(.stepCompleted(id: plan[index].id))
            }
        }

        let synthIndex = synthesisStepIndex(in: plan)
        /// La collecte déterministe a-t-elle déjà rassemblé la matière ?
        /// Dans ce cas la boucle de décision n'apporte rien : le modèle relit
        /// les mêmes observations pour conclure « je peux répondre ».
        var evidenceIsSufficient = false

        // Étape 0 = vrai travail (outil déterministe), plus de done cosmétique.
        if let deterministic = firstTool {
            let step0 = 0
            markIndex(step0, running: true)
            lastToolSignature = toolSignature(deterministic)
            let enriched = try await executeToolWithFollowUp(
                deterministic,
                tools: tools,
                profile: profile,
                history: request.history,
                onEvent: onEvent
            )
            scratch.append("Résultat \(deterministic.action):\n\(enriched.text)")
            mergeSources(enriched.sources, into: &collectedSources)
            if let tid = enriched.mailThreadId { mailThreadId = tid }
            toolCalls += 1
            steps += 1
            markIndex(step0, running: false)

            // Les anciennes étapes « réflexion » et « révision du plan » étaient
            // deux à trois générations par tour dont la sortie n'était jamais
            // montrée : elles ne servaient qu'à réinjecter une paraphrase des
            // observations dans le prompt suivant.
            evidenceIsSufficient = isSelfSufficient(
                action: deterministic.action,
                observation: enriched.text
            )
            if evidenceIsSufficient, synthIndex > 1 {
                for idx in 1..<synthIndex {
                    markIndex(idx, running: true)
                    markIndex(idx, running: false)
                }
            }
        }

        // La synthèse n'a pas besoin de tout l'historique : les preuves d'outil
        // portent le contenu, et relire 14 tours avant de rédiger double le
        // prefill. On garde au plus le dernier échange pour les anaphores.
        let packet = ConversationContextCompressor.compress(
            history: Array(request.history.suffix(2)),
            profile: profile,
            taskHint: request.userText,
            conversationId: request.threadId,
            recallQuery: QueryRewriter.retrievalQuery(
                userText: request.userText,
                history: request.history
            )
        )
        let clock = RuntimeTemporalContext.silentClockBlock()

        while !evidenceIsSufficient, steps < profile.maxWorkflowSteps {
            try Task.checkCancellation()
            steps += 1
            var shouldSynthesize = false

            let activeOp = firstOpenOperationalIndex(in: plan, synthesisIndex: synthesisStepIndex(in: plan))

            // La grammaire impose du JSON valide : plus de troisième option
            // « texte libre », qu'elle interdit de toute façon.
            let system = """
            Tu es l’agent Chatbot. Tu disposes d’outils. Réponds par un seul objet JSON :
            1) {"type":"tool","action":"<nom>","arguments":{...}} pour appeler un outil
            2) {"type":"final","content":"<réponse utilisateur>"} quand tu as assez d’information
            Outils :
            \(tools.catalogSummary)
            Budgets : max \(profile.maxToolCalls) appels outils.
            N’invente pas de données mail/web/fichiers : utilise un outil.
            Les arguments sont toujours des chaînes de caractères.
            Formate la réponse finale en Markdown. Ne récite pas les sources. Cite (web_N) seulement après un fait.
            Exécute l’étape active du plan avant de conclure. Ne saute pas l’analyse.
            \(clock)
            """

            var messages = packet.messages
            var userBlob = request.userText
            if let scope = request.scopeHint, !scope.isEmpty {
                userBlob += "\n[Contexte: \(scope)]"
            }
            if let threadId = request.threadId, !threadId.isEmpty {
                userBlob += "\n[threadId=\(threadId)]"
            }
            if let activeOp, plan.indices.contains(activeOp) {
                userBlob += "\n[Étape active: \(plan[activeOp].title)]"
            }
            if !scratch.isEmpty {
                let obs = scratch.suffix(3).joined(separator: "\n---\n")
                userBlob += "\n\nObservations:\n" + GenerationContextBudget.clip(
                    obs,
                    maxChars: profile.toolResultCharBudget
                )
            }
            messages.append(LLMChatMessage(role: .user, content: userBlob))

            let raw = try await runtime.generateLocal(
                system: system,
                messages: messages,
                maxTokens: profile.outputTokens(for: .agentStep),
                options: LocalGenerationOptions(
                    sampling: .structured,
                    grammar: ToolCallGrammar.agentStep(toolNames: tools.toolNames),
                    timeout: profile.generationTimeoutSeconds
                )
            )

            switch StructuredActionParser.parse(raw) {
            case .final(let text):
                if scratch.isEmpty {
                    markIndex(synthesisStepIndex(in: plan), running: true)
                    onEvent?(.synthesizing)
                    markIndex(synthesisStepIndex(in: plan), running: false)
                    onEvent?(.completed)
                    return Result(
                        text: text,
                        stepsUsed: steps,
                        toolCallsUsed: toolCalls,
                        sources: collectedSources,
                        mailThreadId: mailThreadId
                    )
                }
                scratch.append("Brouillon interne (ne pas réciter):\n\(String(text.prefix(400)))")
                shouldSynthesize = true
            case .invalid:
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if scratch.isEmpty, !cleaned.isEmpty, !cleaned.hasPrefix("{") {
                    markIndex(synthesisStepIndex(in: plan), running: true)
                    onEvent?(.synthesizing)
                    markIndex(synthesisStepIndex(in: plan), running: false)
                    onEvent?(.completed)
                    return Result(
                        text: cleaned,
                        stepsUsed: steps,
                        toolCallsUsed: toolCalls,
                        sources: collectedSources,
                        mailThreadId: mailThreadId
                    )
                }
                scratch.append("Parse invalide, reformuler.")
                continue
            case .tool(let call):
                if toolCalls >= profile.maxToolCalls {
                    shouldSynthesize = true
                    break
                }
                let signature = toolSignature(call)
                if signature == lastToolSignature {
                    WorkflowTrace.log("agent", ["anti_loop": call.action])
                    shouldSynthesize = true
                    break
                }
                lastToolSignature = signature
                let stepIdx = activeOp ?? max(0, synthesisStepIndex(in: plan) - 1)
                markIndex(stepIdx, running: true)
                do {
                    let enriched = try await executeToolWithFollowUp(
                        call,
                        tools: tools,
                        profile: profile,
                        history: request.history,
                        onEvent: onEvent
                    )
                    scratch.append("Résultat \(call.action):\n\(enriched.text)")
                    mergeSources(enriched.sources, into: &collectedSources)
                    if let tid = enriched.mailThreadId { mailThreadId = tid }
                    toolCalls += 1
                    markIndex(stepIdx, running: false)
                    if isSelfSufficient(action: call.action, observation: enriched.text) {
                        shouldSynthesize = true
                    }
                } catch is CancellationError {
                    onEvent?(.cancelled)
                    throw CancellationError()
                } catch {
                    scratch.append("Erreur \(call.action): \(error.localizedDescription)")
                    toolCalls += 1
                    if plan.indices.contains(stepIdx) {
                        plan[stepIdx].status = "error"
                    }
                    let failId = plan.indices.contains(stepIdx) ? plan[stepIdx].id : "s-error"
                    onEvent?(.stepFailed(id: failId, message: error.localizedDescription))
                }
            }
            if shouldSynthesize { break }
        }

        let answerIndex = synthesisStepIndex(in: plan)
        markIndex(answerIndex, running: true)
        onEvent?(.synthesizing)
        let synthSystem = AgentWorkflow.synthesisSystem(hasSources: !collectedSources.isEmpty)
            + "\n\n" + clock
        var synthMessages = packet.messages
        // La synthèse est le seul endroit où les preuves web doivent tenir en
        // entier : les couper au budget d'un résultat d'outil brut revenait à
        // répondre sur deux sources au lieu de cinq.
        let observationBudget = collectedSources.isEmpty
            ? profile.toolResultCharBudget
            : profile.resolvedWebEvidenceCharBudget
        let obs = scratch.isEmpty
            ? "(aucune observation outil)"
            : GenerationContextBudget.clip(scratch.joined(separator: "\n---\n"), maxChars: observationBudget)
        let groundedRequest = QueryRewriter.groundedUserTurn(
            userText: request.userText,
            history: request.history
        )
        let userContent = """
        USER REQUEST
        \(groundedRequest)

        INTERNAL NOTES (travail interne, ne pas réciter) :
        \(obs)
        """
        synthMessages.append(LLMChatMessage(role: .user, content: userContent))
        WorkflowTrace.log("agent", [
            "generations": "\(evidenceIsSufficient ? 1 : steps + 1)",
            "tool_calls": "\(toolCalls)",
            "shortcut": evidenceIsSufficient ? "1" : "0",
        ])
        let finalText: String
        if let onFinalToken {
            finalText = try await runtime.generateStream(
                system: synthSystem,
                messages: synthMessages,
                maxTokens: profile.outputTokens(for: .agentFinal),
                onToken: onFinalToken
            )
        } else {
            finalText = try await runtime.generate(
                system: synthSystem,
                messages: synthMessages,
                maxTokens: profile.outputTokens(for: .agentFinal)
            )
        }
        markIndex(answerIndex, running: false)
        // Clôture honnête : pending sans action → skipped via statut done seulement si déjà done/error
        for i in plan.indices where plan[i].status == "pending" || plan[i].status == "running" {
            if i == answerIndex {
                plan[i].status = "done"
            } else {
                plan[i].status = "done"
                onEvent?(.stepCompleted(id: plan[i].id))
            }
        }
        onEvent?(.completed)
        return Result(
            text: finalText,
            stepsUsed: steps,
            toolCallsUsed: toolCalls,
            sources: collectedSources,
            mailThreadId: mailThreadId
        )
    }

    /// Search puis fetch des pages pertinentes — même logique Chat/Agent.
    @MainActor
    private static func executeToolWithFollowUp(
        _ call: AIToolCall,
        tools: AIToolRegistry,
        profile: LocalModelExecutionProfile,
        history: [LLMChatMessage] = [],
        onEvent: ((AgentOrchestrationEvent) -> Void)?
    ) async throws -> AIToolResult {
        if call.action == "web_search" {
            let rawQ = call.arguments["query"] ?? call.arguments["q"] ?? ""
            // L'ancrage temporel et la compaction sont faits par le planificateur :
            // les appliquer ici en plus produisait « … 2026 2026 ».
            let packet = try await WebEvidencePipeline.gather(
                query: rawQ,
                history: history,
                profile: profile,
                onEvent: onEvent
            )
            return AIToolResult(
                action: "web_search",
                ok: true,
                text: packet.promptBlock,
                truncated: true,
                sources: packet.sources
            )
        }

        onEvent?(.toolStarted(tool: call.action, query: call.arguments["query"]))
        let result = try await tools.execute(call, profile: profile)
        if !result.sources.isEmpty {
            onEvent?(.sources(result.sources))
            onEvent?(.toolCompleted(tool: call.action, sourceCount: result.sources.count))
        } else {
            onEvent?(.toolCompleted(tool: call.action, sourceCount: 0))
        }
        return result
    }

    private static func mergeSources(_ incoming: [SearchSourceDTO], into bag: inout [SearchSourceDTO]) {
        var seen = Set(bag.map { $0.url.lowercased() })
        for src in incoming {
            let key = src.url.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            bag.append(
                SearchSourceDTO(
                    id: "web_\(bag.count + 1)",
                    title: src.title,
                    url: src.url,
                    domain: src.domain,
                    snippet: src.snippet
                )
            )
        }
    }

    static func goalAwareFallbackPlan(userText: String, firstTool: AIToolCall?) -> [AgentPlanStep] {
        let lower = userText.lowercased()
        let snippet = taskSnippet(userText)
        var steps: [AgentPlanStep] = []
        if lower.contains("compar") || lower.contains("vs") || lower.contains("quelle est la meilleure")
            || lower.contains("lequel") || lower.contains("laquelle") {
            steps = [
                AgentPlanStep(id: "s1", title: "Rechercher des sources sur \(snippet)", status: "pending"),
                AgentPlanStep(id: "s2", title: "Comparer les options", status: "pending"),
                AgentPlanStep(id: "s3", title: "Recommander l’option la plus adaptée", status: "pending"),
            ]
        } else if firstTool?.action == "web_search" || lower.contains("internet") || lower.contains("recherche") {
            steps = [
                AgentPlanStep(id: "s1", title: "Rechercher des sources sur \(snippet)", status: "pending"),
                AgentPlanStep(id: "s2", title: "Lire les résultats pertinents", status: "pending"),
                AgentPlanStep(id: "s3", title: "Synthétiser une réponse", status: "pending"),
            ]
        } else if firstTool?.action.hasPrefix("mail") == true || (lower.contains("mail") && !MailIntentDetector.isMailAdvice(userText)) {
            steps = [
                AgentPlanStep(id: "s1", title: "Trouver les messages concernés", status: "pending"),
                AgentPlanStep(id: "s2", title: "Lire le contenu utile", status: "pending"),
                AgentPlanStep(id: "s3", title: "Préparer la réponse", status: "pending"),
            ]
        } else if firstTool?.action.hasPrefix("files") == true {
            steps = [
                AgentPlanStep(id: "s1", title: "Localiser les fichiers utiles", status: "pending"),
                AgentPlanStep(id: "s2", title: "Lire le contenu pertinent", status: "pending"),
                AgentPlanStep(id: "s3", title: "Répondre à partir des fichiers", status: "pending"),
            ]
        } else if userText.count < 80, !lower.contains("explique"), !lower.contains("analyse") {
            steps = [
                AgentPlanStep(id: "s1", title: "Répondre à \(snippet)", status: "pending"),
            ]
        } else {
            steps = [
                AgentPlanStep(id: "s1", title: "Comprendre \(snippet)", status: "pending"),
                AgentPlanStep(id: "s2", title: "Rassembler les éléments utiles", status: "pending"),
                AgentPlanStep(id: "s3", title: "Rédiger la réponse", status: "pending"),
            ]
        }
        return steps
    }

    static func taskSnippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= 42 { return trimmed }
        return String(trimmed.prefix(39)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func parsePlanJSON(_ raw: String) -> [AgentPlanStep]? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") {
            t = String(t[start...end])
        }
        guard let data = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["steps"] as? [[String: Any]] else {
            return nil
        }
        if arr.isEmpty { return [] }
        var steps: [AgentPlanStep] = []
        for (i, item) in arr.prefix(4).enumerated() {
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard title.count >= 4 else { continue }
            if looksLikeChainOfThought(title) { continue }
            let id = (item["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "s\(i + 1)"
            steps.append(AgentPlanStep(id: id, title: String(title.prefix(96)), status: "pending"))
        }
        return clampPlanSteps(steps)
    }

    static func looksLikeChainOfThought(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.hasPrefix("je pense") || lower.hasPrefix("je me demande")
            || lower.contains("mon raisonnement") || lower.hasPrefix("je vais probablement")
    }

    static func isLikelySynthesisTitle(_ title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("synth") || t.contains("rédig") || t.contains("repond") || t.contains("répond")
            || t.contains("recommand") || t.contains("réponse") || t.contains("reponse")
            || t.contains("final") || t.contains("conclu") || t.contains("préparer la réponse")
            || t.contains("preparer la reponse")
    }

    static func synthesisStepIndex(in plan: [AgentPlanStep]) -> Int {
        if let idx = plan.lastIndex(where: { isLikelySynthesisTitle($0.title) }) {
            return idx
        }
        return max(0, plan.count - 1)
    }

    static func firstOpenOperationalIndex(in plan: [AgentPlanStep], synthesisIndex: Int) -> Int? {
        for i in plan.indices where i < synthesisIndex {
            let st = plan[i].status
            if st == "pending" || st == "running" { return i }
        }
        return nil
    }

    static func clampPlanSteps(_ steps: [AgentPlanStep]) -> [AgentPlanStep] {
        guard !steps.isEmpty else { return steps }
        if steps.count <= 4 { return steps }
        var head = Array(steps.prefix(3))
        if let last = steps.last {
            head[2] = AgentPlanStep(id: "s3", title: last.title, status: "pending")
        }
        return head.enumerated().map { i, s in
            AgentPlanStep(id: "s\(i + 1)", title: s.title, status: i == 0 ? "pending" : "pending")
        }
    }

    /// Une observation d'outil se suffit-elle à elle-même pour rédiger ?
    ///
    /// Les outils de collecte (web, mail, fichiers) rendent déjà un bloc de
    /// preuves structuré. Repasser par le modèle pour qu'il décide s'il a
    /// « assez d'information » coûte une génération complète et se termine, dans
    /// la quasi-totalité des cas, par la même conclusion.
    static func isSelfSufficient(action: String, observation: String) -> Bool {
        let selfSufficient: Set<String> = [
            "web_search", "web_fetch", "mail_summarize", "mail_read",
            "files_read", "files_search", "memory_recall",
        ]
        guard selfSufficient.contains(action) else { return false }
        return observation.trimmingCharacters(in: .whitespacesAndNewlines).count >= 200
    }

    static func synthesisSystem(hasSources: Bool) -> String {
        let cites = hasSources
            ? "Cite (web_N) uniquement après un fait précis, jamais comme plan de la réponse."
            : "Pas de fausses citations."
        return """
        Tu rédiges la réponse finale à USER REQUEST.
        Les notes internes sont un travail INTERNE : ne les récite pas source par source.
        Interdit : « Source 1 dit », « Les sources indiquent », « Voici les informations extraites », « Selon la source ».
        Réponds naturellement à la question. Adapte la structure (réponse courte, comparaison, étapes, analyse).
        \(cites)
        Signale les contradictions. N’invente rien. Markdown autorisé. Pas de JSON.
        """
    }

    /// Heuristiques déterministes : évite de demander au petit modèle de “deviner” l’outil évident.
    private static func deterministicFirstTool(for request: Request) -> AIToolCall? {
        let lower = request.userText.lowercased()
        if lower.contains("http://") || lower.contains("https://") {
            if let url = extractURL(from: request.userText) {
                return AIToolCall(action: "web_fetch", arguments: ["url": url])
            }
        }
        if looksLikeLiveWeb(request.userText) {
            return AIToolCall(action: "web_search", arguments: ["query": request.userText])
        }
        let mailIntent = MailIntentDetector.detect(
            request.userText,
            hasOpenThread: !(request.threadId ?? "").isEmpty
        )
        if mailIntent.needsGmailSearch {
            let q = MailIntentDetector.gmailQuery(for: mailIntent, userText: request.userText)
            return AIToolCall(
                action: "mail_search",
                arguments: ["query": request.userText, "gmailQuery": q]
            )
        }
        if let threadId = request.threadId, !threadId.isEmpty {
            if lower.contains("résum") || lower.contains("resum") {
                return AIToolCall(action: "mail_summarize", arguments: ["threadId": threadId])
            }
            if lower.contains("répond") || lower.contains("repond") || lower.contains("draft") {
                return AIToolCall(
                    action: "mail_draft_reply",
                    arguments: ["threadId": threadId, "instruction": request.userText]
                )
            }
        }
        if lower.contains("fichier") || lower.contains("files") || lower.contains("document") {
            if lower.contains("cherche") || lower.contains("trouve") || lower.contains("recherche") {
                return AIToolCall(action: "files_search", arguments: ["query": request.userText])
            }
            return AIToolCall(action: "files_list", arguments: ["path": ""])
        }
        if lower.contains("souviens") || lower.contains("mémoire") || lower.contains("memoire") {
            return AIToolCall(action: "memory_recall", arguments: ["query": request.userText])
        }
        return nil
    }

    /// Question qui exige des faits à jour. Sans ça, « les meilleures souris
    /// gamer » en mode Agent faisait d'abord écrire un JSON d'outil au modèle
    /// (~une minute) avant d'aller sur le web.
    static func looksLikeLiveWeb(_ text: String) -> Bool {
        let lower = text.lowercased()
        let explicit = [
            "cherche sur le web", "recherche web", "sur internet", "google",
            "dernières informations", "dernieres informations",
            "actualité", "actualite", "rapport qualité", "rapport qualite",
        ]
        if explicit.contains(where: { lower.contains($0) }) { return true }
        if lower.contains("recherche"), lower.contains("web") || lower.contains("internet") || lower.contains("en ligne") {
            return true
        }
        if lower.contains("web"), lower.contains("cherche") || lower.contains("recherche") {
            return true
        }
        let live = [
            "meilleur", "meilleure", "meilleures", "meilleurs",
            "prix", "tarif", "coût", "cout", "pas cher",
            "comparatif", "compare", "vs ", " versus ",
            "avis", "test de", "en ce moment", "aujourd'hui", "aujourd hui",
            "disponible", "sortie", "recommande", "recommandation",
            "top 5", "top 10", "quel gpu", "quelle carte",
        ]
        return live.contains(where: { lower.contains($0) })
    }

    /// Requête SERP à partir d'une demande — délègue au planificateur, qui gère
    /// les mots vides, les guillemets et l'ancrage sur l'année en cours.
    static func compactWebQuery(_ text: String) -> String {
        WebQueryPlanner.plan(userText: text).primary
    }

    private static func extractURL(from text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?.firstMatch(in: text, options: [], range: range).flatMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    static func toolSignature(_ call: AIToolCall) -> String {
        let args = call.arguments.keys.sorted().map { "\($0)=\(call.arguments[$0] ?? "")" }.joined(separator: "&")
        return "\(call.action)|\(args)"
    }
}

enum MailSummarizeWorkflow {
    struct Request: Sendable {
        var threadId: String
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        _ = runtime
        let assistant = LocalMailAssistant()
        return try await assistant.summarizeThread(threadId: request.threadId, onToken: onToken)
    }
}

enum MailReplyWorkflow {
    struct Request: Sendable {
        var threadId: String
        var instruction: String
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> MailSendConfirmation {
        _ = runtime
        let assistant = LocalMailAssistant()
        return try await assistant.draftReply(
            threadId: request.threadId,
            instruction: request.instruction,
            onToken: onToken
        )
    }
}

/// Nouvel e-mail (pas une réponse de fil) — même contrat local / carte Mail Assistant.
enum MailComposeWorkflow {
    struct Request: Sendable {
        var instruction: String
        var recipientHint: String?
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> MailSendConfirmation {
        let profile = runtime.executionProfile
        let instruction = request.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = (request.recipientHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let user = """
        USER INSTRUCTION:
        \(instruction)

        Destinataire hint: \(hint.isEmpty ? "(à remplir)" : hint)

        TASK:
        Write the email body only.
        """
        let raw: String
        if let onToken {
            raw = try await runtime.generateStream(
                system: LocalPrompts.mailComposeDraft,
                messages: [LLMChatMessage(role: .user, content: user)],
                maxTokens: profile.outputTokens(for: .mailReply),
                onToken: onToken
            )
        } else {
            raw = try await runtime.generate(
                system: LocalPrompts.mailComposeDraft,
                messages: [LLMChatMessage(role: .user, content: user)],
                maxTokens: profile.outputTokens(for: .mailReply)
            )
        }
        let body = MailSignature.appendOnce(MailDraftRewriteWorkflow.stripMeta(raw))
        guard body.count >= 8 else {
            throw LocalMailAssistantError.inference("Brouillon vide.")
        }
        let to = hint
        let subject = Self.subjectHint(from: instruction)
        return MailSendConfirmation(
            to: to,
            subject: subject,
            proposedBody: body,
            threadId: nil,
            draftId: "local-\(UUID().uuidString)"
        )
    }

    static func subjectHint(from instruction: String) -> String {
        let clipped = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if clipped.count <= 72 { return "" }
        return ""
    }
}

/// Boîte mail (liste, pas un fil ouvert) — Gmail device, jamais le PC en mode local.
enum MailMailboxWorkflow {
    struct Request: Sendable {
        var userText: String
        var context: MailContextKind
    }

    struct Result: Sendable {
        var text: String
        var mailThreadId: String?
        var mailHandoff: MailHandoffDTO?
        var sourcesLabel: String?
        /// Si non nil : ouvrir la carte Mail Assistant, ne pas coller le corps dans le chat.
        var draft: MailSendConfirmation? = nil
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        tools: AIToolRegistry,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> Result {
        let profile = runtime.executionProfile
        let hasThread: Bool
        if case .thread = request.context { hasThread = true } else { hasThread = false }
        let intent = MailIntentDetector.detect(request.userText, hasOpenThread: hasThread)
        if case .compose(let hint) = intent {
            let confirmation = try await MailComposeWorkflow.run(
                .init(instruction: request.userText, recipientHint: hint),
                runtime: runtime,
                onToken: onToken
            )
            return Result(
                text: "Brouillon ouvert dans Mail Assistant.",
                mailThreadId: nil,
                mailHandoff: nil,
                sourcesLabel: nil,
                draft: confirmation
            )
        }
        let gmailQ = MailIntentDetector.gmailQuery(for: intent, userText: request.userText)
        WorkflowTrace.log("workflow", ["type": "mail_mailbox", "gmail_q": String(gmailQ.prefix(80))])

        let call = AIToolCall(
            action: "mail_search",
            arguments: [
                "query": request.userText,
                "gmailQuery": gmailQ,
                "fetchBodies": "true",
            ]
        )
        let result = try await tools.execute(call, profile: profile)
        let hasMessages = MailContextPrompt.containsMessages(toolText: result.text, ok: result.ok)
        WorkflowTrace.log("run:context", [
            "mailContext": hasMessages ? "true" : "false",
            "webContext": "false",
            "gmail_q": String(gmailQ.prefix(80)),
        ])

        let handoff = result.mailHandoff ?? MailReference.first(fromToolText: result.text)

        if hasMessages, MailIntentDetector.wantsReply(request.userText),
           let threadId = result.mailThreadId, !threadId.isEmpty {
            let confirmation = try await MailReplyWorkflow.run(
                .init(threadId: threadId, instruction: request.userText),
                runtime: runtime,
                onToken: onToken
            )
            return Result(
                text: "Brouillon ouvert dans Mail Assistant.",
                mailThreadId: threadId,
                mailHandoff: handoff,
                sourcesLabel: nil,
                draft: confirmation
            )
        }

        let clipped = GenerationContextBudget.clip(result.text, maxChars: profile.toolResultCharBudget)
        let messages = [
            LLMChatMessage(
                role: .user,
                content: MailContextPrompt.userMessage(
                    userRequest: request.userText,
                    toolText: clipped,
                    hasMessages: hasMessages
                )
            ),
        ]
        WorkflowTrace.log("run:llm", ["workflow": "mail", "mailContext": hasMessages ? "true" : "false"])
        let text: String
        if let onToken {
            text = try await runtime.generateStream(
                system: MailContextPrompt.system(hasMessages: hasMessages),
                messages: messages,
                maxTokens: profile.outputTokens(for: .mailSummary),
                onToken: onToken
            )
        } else {
            text = try await runtime.generate(
                system: MailContextPrompt.system(hasMessages: hasMessages),
                messages: messages,
                maxTokens: profile.outputTokens(for: .mailSummary)
            )
        }
        return Result(text: text, mailThreadId: result.mailThreadId, mailHandoff: handoff, sourcesLabel: nil)
    }
}

enum WebSearchWorkflow {
    struct Request: Sendable {
        var query: String
        var synthesize: Bool
        /// Tours précédents — servent à résoudre les anaphores de la requête
        /// (« et son prix ? ») avant d'interroger le moteur de recherche.
        var history: [LLMChatMessage] = []
    }

    struct Result: Sendable {
        var text: String
        var sources: [SearchSourceDTO]
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        tools: AIToolRegistry,
        onEvent: ((AgentOrchestrationEvent) -> Void)? = nil,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> Result {
        _ = tools
        let profile = runtime.executionProfile
        let packet = try await WebEvidencePipeline.gather(
            query: request.query,
            history: request.history,
            profile: profile,
            onEvent: onEvent
        )
        guard request.synthesize else {
            return Result(text: packet.promptBlock, sources: packet.sources)
        }
        let messages = [
            LLMChatMessage(role: .user, content: packet.promptBlock),
        ]
        WorkflowTrace.log("run:context", [
            "mailContext": "false",
            "webContext": packet.evidence.isEmpty ? "false" : "true",
        ])
        onEvent?(.synthesizing)
        WorkflowTrace.log("run:llm", ["workflow": "web"])
        let text: String
        if let onToken {
            text = try await runtime.generateStream(
                system: WebGroundingPrompt.system(),
                messages: messages,
                maxTokens: profile.outputTokens(for: .webSynthesize),
                onToken: onToken
            )
        } else {
            text = try await runtime.generate(
                system: WebGroundingPrompt.system(),
                messages: messages,
                maxTokens: profile.outputTokens(for: .webSynthesize)
            )
        }
        return Result(text: text, sources: packet.sources)
    }
}

enum FilesWorkflow {
    struct Request: Sendable {
        var path: String
        var userQuestion: String
        var fileId: String? = nil
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        tools: AIToolRegistry
    ) async throws -> String {
        let profile = runtime.executionProfile
        do {
            var extra = ""
            if let fileId = request.fileId, let extracted = LocalDocumentExtractor.extract(fileId: fileId) {
                extra = "\n\nContenu du fichier ouvert:\n\(extracted)"
            }
            let searchFirst = !request.userQuestion.isEmpty
            let data: AIToolResult
            if searchFirst {
                let q = request.userQuestion
                data = try await tools.execute(
                    AIToolCall(action: "files_search", arguments: ["query": q]),
                    profile: profile
                )
            } else {
                data = try await tools.execute(
                    AIToolCall(action: "files_list", arguments: ["path": request.path]),
                    profile: profile
                )
            }
            if request.userQuestion.isEmpty { return data.text + extra }
            return try await runtime.generate(
                system: "Aide sur les fichiers accessibles à l’app. Utilise uniquement les données fournies. Markdown autorisé.",
                messages: [
                    LLMChatMessage(
                        role: .user,
                        content: "Question: \(request.userQuestion)\n\nDonnées:\n\(data.text)\(extra)"
                    ),
                ],
                maxTokens: profile.outputTokens(for: .files)
            )
        } catch let error as AIRuntimeError {
            return error.localizedDescription
        }
    }
}

enum MailDraftRewriteWorkflow {
    struct Request: Sendable {
        var instruction: String
        var body: String
        var to: String
        var subject: String
        /// Second passage si la 1ʳᵉ sortie est trop proche de l’original.
        var forceVisibleChange: Bool = false
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        let profile = runtime.executionProfile
        let instruction = request.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsigned = MailSignature.stripTrailingComplimentaryClose(
            String(request.body.prefix(8_000)),
            name: UserDisplayName.resolved()
        )
        let user = userPrompt(
            instruction: instruction,
            body: unsigned,
            to: request.to,
            subject: request.subject,
            forceVisibleChange: request.forceVisibleChange
        )
        let raw: String
        if let onToken {
            raw = try await runtime.generateStream(
                system: LocalPrompts.mailDraftRewrite,
                messages: [LLMChatMessage(role: .user, content: user)],
                maxTokens: profile.outputTokens(for: .mailReply),
                onToken: onToken
            )
        } else {
            raw = try await runtime.generate(
                system: LocalPrompts.mailDraftRewrite,
                messages: [LLMChatMessage(role: .user, content: user)],
                maxTokens: profile.outputTokens(for: .mailReply)
            )
        }
        let cleaned = Self.stripMeta(raw)
        guard cleaned.count >= 8 else {
            throw LocalMailAssistantError.inference("Réécriture vide.")
        }
        return MailSignature.appendOnce(cleaned)
    }

    /// Réécrit et, si le texte est quasiment identique, force un 2ᵉ passage.
    @MainActor
    static func runEnsuringChange(
        _ request: Request,
        runtime: any AIRuntime,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        let first = try await run(request, runtime: runtime, onToken: onToken)
        if !isNearlyIdentical(request.body, first) {
            return first
        }
        let forced = Request(
            instruction: request.instruction,
            body: request.body,
            to: request.to,
            subject: request.subject,
            forceVisibleChange: true
        )
        let second = try await run(forced, runtime: runtime, onToken: onToken)
        if isNearlyIdentical(request.body, second) {
            throw LocalMailAssistantError.inference(
                "La réécriture n’a pas modifié le brouillon. Reformule la consigne (ex. « moins formel », « en anglais »)."
            )
        }
        return second
    }

    static func userPrompt(
        instruction: String,
        body: String,
        to: String,
        subject: String,
        forceVisibleChange: Bool = false
    ) -> String {
        let consigne = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let force = forceVisibleChange
            ? """

        CRITICAL:
        Your previous rewrite was too similar to CURRENT DRAFT.
        Apply USER INSTRUCTION aggressively so the new body is CLEARLY different
        (tone, length, wording, or language as requested). Do not return the same text.
        """
            : ""
        return """
        USER INSTRUCTION:
        \(consigne.isEmpty ? "Plus clair et naturel." : consigne)

        CURRENT DRAFT:
        \(body)

        MAIL CONTEXT:
        Destinataire (ne pas modifier): \(to.isEmpty ? "(inchangé)" : to)
        Objet (ne pas modifier): \(subject.isEmpty ? "(inchangé)" : subject)

        TASK:
        Rewrite CURRENT DRAFT according to USER INSTRUCTION only.
        The current draft is the source of truth. Do not re-apply older instructions.
        Output MUST reflect the instruction with a visible change.
        \(force)
        """
    }

    static func stripMeta(_ raw: String) -> String {
        var t = LocalChatTemplate.truncateAssistantOutput(raw).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: #"^```[a-zA-Z]*\n?"#, with: "", options: .regularExpression)
            if let end = t.range(of: "```", options: .backwards) {
                t = String(t[..<end.lowerBound])
            }
        }
        let prefixes = [
            "voici une version", "voici le mail", "voici le nouveau",
            "version moins formelle", "version plus formelle",
            "j’ai réécrit", "j'ai réécrit", "rewritten email:",
        ]
        let lower = t.lowercased()
        for p in prefixes where lower.hasPrefix(p) {
            if let nl = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: nl)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedForCompare(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func isNearlyIdentical(_ a: String, _ b: String) -> Bool {
        let na = normalizedForCompare(a)
        let nb = normalizedForCompare(b)
        if na.isEmpty || nb.isEmpty { return false }
        if na == nb { return true }
        let shorter = na.count <= nb.count ? na : nb
        let longer = na.count <= nb.count ? nb : na
        if shorter.count >= 40, longer.contains(shorter), longer.count - shorter.count < 48 {
            return true
        }
        return false
    }
}

enum MemoryWorkflow {
    struct Request: Sendable {
        var query: String
        var synthesize: Bool
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        tools: AIToolRegistry
    ) async throws -> String {
        let profile = runtime.executionProfile
        let recalled = try await tools.execute(
            AIToolCall(action: "memory_recall", arguments: ["query": request.query]),
            profile: profile
        )
        guard request.synthesize else { return recalled.text }
        return try await runtime.generate(
            system: "Utilise uniquement les faits mémorisés fournis.",
            messages: [
                LLMChatMessage(
                    role: .user,
                    content: "Question: \(request.query)\n\nFaits:\n\(recalled.text)"
                ),
            ],
            maxTokens: min(256, profile.maxOutputTokens)
        )
    }
}
