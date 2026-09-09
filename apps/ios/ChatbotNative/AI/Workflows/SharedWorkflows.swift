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
        let plan = makePlan(userText: request.userText, firstTool: firstTool)

        WorkflowTrace.log("workflow", [
            "type": "agent",
            "runtime": "local",
            "steps": "\(profile.maxWorkflowSteps)",
        ])
        onEvent?(.started)
        onEvent?(.plan(steps: plan))

        func mark(_ id: String, running: Bool = true) {
            if running {
                let title = plan.first(where: { $0.id == id })?.title ?? id
                onEvent?(.stepStarted(id: id, title: title))
            } else {
                onEvent?(.stepCompleted(id: id))
            }
        }

        mark("understand")
        mark("understand", running: false)

        if let deterministic = firstTool {
            mark("act")
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
            mark("act", running: false)
        }

        let packet = ConversationContextCompressor.compress(
            history: request.history,
            profile: profile,
            taskHint: request.userText
        )

        while steps < profile.maxWorkflowSteps {
            try Task.checkCancellation()
            steps += 1

            let system = """
            Tu es l’agent Chatbot. Tu disposes d’outils. Réponds soit :
            1) JSON {"type":"tool","action":"<nom>","arguments":{...}}
            2) JSON {"type":"final","content":"<réponse utilisateur>"}
            3) Texte final si tu as assez d’info.
            Outils :
            \(tools.catalogSummary)
            Budgets : max \(profile.maxToolCalls) appels outils.
            N’invente pas de données mail/web/fichiers : utilise un outil.
            Formate la réponse finale en Markdown. Cite les sources (web_N) si présentes.
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
                mark("answer")
                onEvent?(.synthesizing)
                onEvent?(.stepCompleted(id: "answer"))
                onEvent?(.completed)
                return Result(
                    text: text,
                    stepsUsed: steps,
                    toolCallsUsed: toolCalls,
                    sources: collectedSources,
                    mailThreadId: mailThreadId
                )
            case .invalid:
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty, !cleaned.hasPrefix("{") {
                    mark("answer")
                    onEvent?(.synthesizing)
                    onEvent?(.stepCompleted(id: "answer"))
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
                    break
                }
                let signature = toolSignature(call)
                if signature == lastToolSignature {
                    WorkflowTrace.log("agent", ["anti_loop": call.action])
                    break
                }
                lastToolSignature = signature
                mark("act")
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
                } catch is CancellationError {
                    onEvent?(.cancelled)
                    throw CancellationError()
                } catch {
                    scratch.append("Erreur \(call.action): \(error.localizedDescription)")
                    toolCalls += 1
                    onEvent?(.stepFailed(id: "act", message: error.localizedDescription))
                }
                mark("act", running: false)
            }
        }

        mark("answer")
        onEvent?(.synthesizing)
        let synthSystem = collectedSources.isEmpty
            ? "Synthétise à partir des observations. Pas de JSON. Markdown autorisé."
            : WebGroundingPrompt.system() + "\nSynthétise à partir des extraits. Pas de JSON."
        var synthMessages = packet.messages
        let obs = scratch.isEmpty
            ? "(aucune observation outil)"
            : GenerationContextBudget.clip(scratch.joined(separator: "\n---\n"), maxChars: profile.toolResultCharBudget)
        let userContent = "Demande: \(request.userText)\n\n\(obs)"
        synthMessages.append(LLMChatMessage(role: .user, content: userContent + "\n\nRéponds à l’utilisateur."))
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
        onEvent?(.stepCompleted(id: "answer"))
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

    private static func makePlan(userText: String, firstTool: AIToolCall?) -> [AgentPlanStep] {
        let lower = userText.lowercased()
        var steps: [AgentPlanStep] = [
            AgentPlanStep(id: "understand", title: "Analyser ce que tu demandes", status: "pending"),
        ]
        if firstTool?.action == "web_search" || lower.contains("internet") || lower.contains("recherche") {
            steps.append(AgentPlanStep(id: "act", title: "Rechercher sur le web", status: "pending"))
            steps.append(AgentPlanStep(id: "answer", title: "Rédiger la réponse", status: "pending"))
        } else if firstTool?.action.hasPrefix("mail") == true || lower.contains("mail") {
            steps.append(AgentPlanStep(id: "act", title: "Consulter la boîte mail", status: "pending"))
            steps.append(AgentPlanStep(id: "answer", title: "Rédiger la réponse", status: "pending"))
        } else if firstTool?.action.hasPrefix("files") == true {
            steps.append(AgentPlanStep(id: "act", title: "Parcourir les fichiers", status: "pending"))
            steps.append(AgentPlanStep(id: "answer", title: "Rédiger la réponse", status: "pending"))
        } else {
            steps.append(AgentPlanStep(id: "act", title: "Collecter les informations", status: "pending"))
            steps.append(AgentPlanStep(id: "answer", title: "Rédiger la réponse", status: "pending"))
        }
        return steps
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

/// Boîte mail (liste, pas un fil ouvert) — Gmail device, jamais le PC en mode local.
enum MailMailboxWorkflow {
    struct Request: Sendable {
        var userText: String
        var context: MailContextKind
    }

    struct Result: Sendable {
        var text: String
        var mailThreadId: String?
        var sourcesLabel: String?
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
        let system = """
        Tu es l’assistant mail. Tu as accès aux mails via l’application (résultats ci-dessous).
        N’écris JAMAIS que tu n’as pas accès aux mails.
        Réponds en français, naturellement, à partir UNIQUEMENT des messages fournis.
        Mentionne expéditeur, objet, date. Markdown autorisé.
        Si la liste est vide, dis-le clairement.
        """
        let messages = [
            LLMChatMessage(
                role: .user,
                content: "Question: \(request.userText)\n\nMails:\n\(GenerationContextBudget.clip(result.text, maxChars: profile.toolResultCharBudget))"
            ),
        ]
        let text: String
        if let onToken {
            text = try await runtime.generateStream(
                system: system,
                messages: messages,
                maxTokens: profile.outputTokens(for: .mailSummary),
                onToken: onToken
            )
        } else {
            text = try await runtime.generate(
                system: system,
                messages: messages,
                maxTokens: profile.outputTokens(for: .mailSummary)
            )
        }
        return Result(text: text, mailThreadId: result.mailThreadId, sourcesLabel: nil)
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
        onEvent?(.synthesizing)
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
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        tools: AIToolRegistry
    ) async throws -> String {
        let profile = runtime.executionProfile
        do {
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
            if request.userQuestion.isEmpty { return data.text }
            return try await runtime.generate(
                system: "Aide sur les fichiers accessibles à l’app. Utilise uniquement les données fournies. Markdown autorisé.",
                messages: [
                    LLMChatMessage(
                        role: .user,
                        content: "Question: \(request.userQuestion)\n\nDonnées:\n\(data.text)"
                    ),
                ],
                maxTokens: profile.outputTokens(for: .files)
            )
        } catch let error as AIRuntimeError {
            return error.localizedDescription
        }
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
