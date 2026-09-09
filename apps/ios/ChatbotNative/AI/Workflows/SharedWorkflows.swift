import Foundation

/// Workflows métier **uniques** — PC et local = même logique, budgets via runtime.profile.
enum ChatWorkflow {
    struct Request: Sendable {
        var userText: String
        var history: [LLMChatMessage]
        var systemPrompt: String
        var taskHint: String?
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
        let profile = runtime.executionProfile
        let packet = ConversationContextCompressor.compress(
            history: request.history,
            profile: profile,
            taskHint: request.taskHint
        )
        var system = request.systemPrompt
        if !packet.systemAugment.isEmpty {
            system += "\n\n" + packet.systemAugment
        }
        var messages = packet.messages
        if messages.last?.role != .user {
            messages.append(LLMChatMessage(role: .user, content: request.userText))
        }
        let text: String
        if let onToken {
            text = try await runtime.generateStream(
                system: system,
                messages: messages,
                maxTokens: profile.outputTokens(for: LocalPrompts.conversationTask(for: request.userText)),
                onToken: onToken
            )
        } else {
            text = try await runtime.generate(
                system: system,
                messages: messages,
                maxTokens: profile.outputTokens(for: LocalPrompts.conversationTask(for: request.userText))
            )
        }
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
        let profile = runtime.executionProfile
        var toolCalls = 0
        var steps = 0
        var scratch: [String] = []
        var lastToolSignature: String?
        var collectedSources: [SearchSourceDTO] = []
        var mailThreadId: String?
        let firstTool = deterministicFirstTool(for: request)
        var plan = await buildPlan(
            userText: request.userText,
            firstTool: firstTool,
            runtime: runtime
        )

        WorkflowTrace.log("workflow", [
            "type": "agent",
            "runtime": "local",
            "steps": "\(profile.maxWorkflowSteps)",
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

        let actIndex = min(1, max(0, plan.count - 2))
        let answerIndex = max(0, plan.count - 1)

        markIndex(0, running: true)
        markIndex(0, running: false)

        if let deterministic = firstTool {
            markIndex(actIndex, running: true)
            lastToolSignature = toolSignature(deterministic)
            let enriched = try await executeToolWithFollowUp(
                deterministic,
                tools: tools,
                profile: profile,
                onEvent: onEvent
            )
            scratch.append("Résultat \(deterministic.action):\n\(enriched.text)")
            mergeSources(enriched.sources, into: &collectedSources)
            if let tid = enriched.mailThreadId { mailThreadId = tid }
            toolCalls += 1
            steps += 1
            markIndex(actIndex, running: false)
            let next = await revisedPlan(
                current: plan,
                observation: enriched.text,
                userText: request.userText,
                runtime: runtime
            )
            if next.map(\.title) != plan.map(\.title) {
                plan = next
                onEvent?(.plan(steps: plan))
            }
        }

        let packet = ConversationContextCompressor.compress(
            history: request.history,
            profile: profile,
            taskHint: request.userText
        )

        while steps < profile.maxWorkflowSteps {
            try Task.checkCancellation()
            steps += 1
            var shouldSynthesize = false

            let system = """
            Tu es l’agent Chatbot. Tu disposes d’outils. Réponds soit :
            1) JSON {"type":"tool","action":"<nom>","arguments":{...}}
            2) JSON {"type":"final","content":"<réponse utilisateur>"}
            3) Texte final si tu as assez d’info.
            Outils :
            \(tools.catalogSummary)
            Budgets : max \(profile.maxToolCalls) appels outils.
            N’invente pas de données mail/web/fichiers : utilise un outil.
            Formate la réponse finale en Markdown. Ne récite pas les sources. Cite (web_N) seulement après un fait.
            """

            var messages = packet.messages
            var userBlob = request.userText
            if let scope = request.scopeHint, !scope.isEmpty {
                userBlob += "\n[Contexte: \(scope)]"
            }
            if let threadId = request.threadId, !threadId.isEmpty {
                userBlob += "\n[threadId=\(threadId)]"
            }
            if !scratch.isEmpty {
                let obs = scratch.suffix(2).joined(separator: "\n---\n")
                userBlob += "\n\nObservations:\n" + GenerationContextBudget.clip(
                    obs,
                    maxChars: profile.toolResultCharBudget
                )
            }
            messages.append(LLMChatMessage(role: .user, content: userBlob))

            let raw = try await runtime.generate(
                system: system,
                messages: messages,
                maxTokens: profile.outputTokens(for: .agentStep)
            )

            switch StructuredActionParser.parse(raw) {
            case .final(let text):
                if scratch.isEmpty {
                    markIndex(answerIndex, running: true)
                    onEvent?(.synthesizing)
                    markIndex(answerIndex, running: false)
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
                    markIndex(answerIndex, running: true)
                    onEvent?(.synthesizing)
                    markIndex(answerIndex, running: false)
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
                markIndex(actIndex, running: true)
                do {
                    let enriched = try await executeToolWithFollowUp(
                        call,
                        tools: tools,
                        profile: profile,
                        onEvent: onEvent
                    )
                    scratch.append("Résultat \(call.action):\n\(enriched.text)")
                    mergeSources(enriched.sources, into: &collectedSources)
                    if let tid = enriched.mailThreadId { mailThreadId = tid }
                    toolCalls += 1
                    if plan.indices.contains(actIndex) {
                        plan[actIndex].status = "done"
                    }
                    markIndex(actIndex, running: false)
                    let next = await revisedPlan(
                        current: plan,
                        observation: enriched.text,
                        userText: request.userText,
                        runtime: runtime
                    )
                    if next.map(\.title) != plan.map(\.title) {
                        plan = next
                        onEvent?(.plan(steps: plan))
                    }
                } catch is CancellationError {
                    onEvent?(.cancelled)
                    throw CancellationError()
                } catch {
                    scratch.append("Erreur \(call.action): \(error.localizedDescription)")
                    toolCalls += 1
                    if plan.indices.contains(actIndex) {
                        plan[actIndex].status = "error"
                    }
                    let failId = plan.indices.contains(actIndex) ? plan[actIndex].id : "s-error"
                    onEvent?(.stepFailed(id: failId, message: error.localizedDescription))
                    let next = await revisedPlan(
                        current: plan,
                        observation: "Erreur \(call.action): \(error.localizedDescription)",
                        userText: request.userText,
                        runtime: runtime
                    )
                    if next.map(\.title) != plan.map(\.title) {
                        plan = next
                        onEvent?(.plan(steps: plan))
                    }
                }
            }
            if shouldSynthesize { break }
        }

        markIndex(answerIndex, running: true)
        onEvent?(.synthesizing)
        let synthSystem = AgentWorkflow.synthesisSystem(hasSources: !collectedSources.isEmpty)
        var synthMessages = packet.messages
        let obs = scratch.isEmpty
            ? "(aucune observation outil)"
            : GenerationContextBudget.clip(scratch.joined(separator: "\n---\n"), maxChars: profile.toolResultCharBudget)
        let userContent = """
        USER REQUEST
        \(request.userText)

        INTERNAL NOTES (travail interne, ne pas réciter) :
        \(obs)
        """
        synthMessages.append(LLMChatMessage(role: .user, content: userContent))
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
        onEvent: ((AgentOrchestrationEvent) -> Void)?
    ) async throws -> AIToolResult {
        if call.action == "web_search" {
            let packet = try await WebEvidencePipeline.gather(
                query: call.arguments["query"] ?? call.arguments["q"] ?? "",
                tools: tools,
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
                AgentPlanStep(id: "s1", title: "Identifier les critères pour \(snippet)", status: "pending"),
                AgentPlanStep(id: "s2", title: "Extraire les informations de chaque option", status: "pending"),
                AgentPlanStep(id: "s3", title: "Comparer les compromis", status: "pending"),
                AgentPlanStep(id: "s4", title: "Recommander l’option la plus adaptée", status: "pending"),
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
        for (i, item) in arr.prefix(6).enumerated() {
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard title.count >= 4 else { continue }
            if looksLikeChainOfThought(title) { continue }
            let id = (item["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "s\(i + 1)"
            steps.append(AgentPlanStep(id: id, title: String(title.prefix(96)), status: "pending"))
        }
        return steps
    }

    static func looksLikeChainOfThought(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.hasPrefix("je pense") || lower.hasPrefix("je me demande")
            || lower.contains("mon raisonnement") || lower.hasPrefix("je vais probablement")
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

    @MainActor
    static func buildPlan(
        userText: String,
        firstTool: AIToolCall?,
        runtime: any AIRuntime
    ) async -> [AgentPlanStep] {
        let fallback = goalAwareFallbackPlan(userText: userText, firstTool: firstTool)
        let profile = runtime.executionProfile
        let prompt = """
        USER TASK:
        \(userText)

        Produis un JSON unique : {"steps":[{"id":"s1","title":"..."}]}
        1 à 6 étapes opérationnelles adaptées à CETTE tâche (pas un template générique).
        Une question simple = une seule étape. Une tâche complexe = plusieurs étapes concrètes.
        Titres concrets, utiles à l’utilisateur. Pas de « Je pense que ». Pas d’autre texte.
        """
        do {
            let raw = try await runtime.generate(
                system: """
                Tu es un planificateur d’agent. JSON uniquement, sans markdown.
                Les titres doivent coller à la tâche réelle.
                """,
                messages: [LLMChatMessage(role: .user, content: prompt)],
                maxTokens: min(280, profile.outputTokens(for: .agentStep))
            )
            if let parsed = parsePlanJSON(raw), parsed.count >= 1 {
                return parsed
            }
        } catch {
            WorkflowTrace.log("agent", ["plan_fallback": "true"])
        }
        return fallback
    }

    @MainActor
    static func revisedPlan(
        current: [AgentPlanStep],
        observation: String,
        userText: String,
        runtime: any AIRuntime
    ) async -> [AgentPlanStep] {
        let done = current.filter { $0.status == "done" || $0.status == "error" }
        let pendingTitles = current
            .filter { $0.status == "pending" || $0.status == "running" }
            .map(\.title)
            .joined(separator: " | ")
        let prompt = """
        USER TASK:
        \(userText)

        NEW OBSERVATION:
        \(String(observation.prefix(1200)))

        DONE STEPS:
        \(done.map(\.title).joined(separator: " | "))

        PENDING STEPS:
        \(pendingTitles.isEmpty ? "(none)" : pendingTitles)

        JSON only: {"steps":[{"id":"s1","title":"..."}]}
        Remaining operational steps after this observation (0 à 4).
        Add, drop, or rewrite pending steps if needed. No chain-of-thought.
        Empty steps array if ready to answer.
        """
        do {
            let raw = try await runtime.generate(
                system: "Tu révises le plan d’un agent. JSON uniquement.",
                messages: [LLMChatMessage(role: .user, content: prompt)],
                maxTokens: min(220, runtime.executionProfile.outputTokens(for: .agentStep))
            )
            guard let parsed = parsePlanJSON(raw) else { return current }
            var next = done
            for (i, step) in parsed.enumerated() {
                if looksLikeChainOfThought(step.title) { continue }
                let id = "s\(done.count + i + 1)"
                next.append(AgentPlanStep(id: id, title: step.title, status: "pending"))
            }
            if next.map(\.title) == current.map(\.title) { return current }
            return next
        } catch {
            WorkflowTrace.log("agent", ["plan_revise_skip": "true"])
            return current
        }
    }

    /// Heuristiques déterministes : évite de demander au petit modèle de “deviner” l’outil évident.
    private static func deterministicFirstTool(for request: Request) -> AIToolCall? {
        let lower = request.userText.lowercased()
        if lower.contains("http://") || lower.contains("https://") {
            if let url = extractURL(from: request.userText) {
                return AIToolCall(action: "web_fetch", arguments: ["url": url])
            }
        }
        if lower.contains("cherche sur le web")
            || lower.contains("recherche web")
            || lower.contains("sur internet")
            || lower.contains("google")
            || lower.contains("dernières informations")
            || lower.contains("dernieres informations")
            || lower.contains("actualité")
            || lower.contains("actualite")
            || lower.contains("rapport qualité") || lower.contains("rapport qualite")
            || lower.contains("meilleur gpu") || lower.contains("meilleure carte")
            || (lower.contains("recherche") && (lower.contains("web") || lower.contains("internet") || lower.contains("en ligne")))
            || (lower.contains("web") && (lower.contains("cherche") || lower.contains("recherche"))) {
            return AIToolCall(action: "web_search", arguments: ["query": compactWebQuery(request.userText)])
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

    static func compactWebQuery(_ text: String) -> String {
        var q = text
        for prefix in ["recherche sur internet ", "recherche sur le web ", "cherche sur internet ",
                       "recherche ", "cherche "] {
            if q.lowercased().hasPrefix(prefix) {
                q = String(q.dropFirst(prefix.count))
                break
            }
        }
        return q.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let profile = runtime.executionProfile
        let packet = try await WebEvidencePipeline.gather(
            query: request.query,
            tools: tools,
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
            subject: request.subject
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

    static func userPrompt(instruction: String, body: String, to: String, subject: String) -> String {
        let consigne = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
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
