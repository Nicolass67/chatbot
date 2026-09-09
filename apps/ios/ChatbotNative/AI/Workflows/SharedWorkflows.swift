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
        runtime: any AIRuntime
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
        let text = try await runtime.generate(
            system: system,
            messages: messages,
            maxTokens: profile.maxOutputTokens
        )
        return Result(text: text)
    }
}

/// Agent = plan → outils → synthèse. Budgets = ExecutionProfile uniquement.
enum AgentWorkflow {
    struct Request: Sendable {
        var userText: String
        var history: [LLMChatMessage]
        var threadId: String?
        var scopeHint: String?
    }

    struct StepEvent: Sendable {
        var label: String
    }

    struct Result: Sendable {
        var text: String
        var stepsUsed: Int
        var toolCallsUsed: Int
    }

    @MainActor
    static func run(
        _ request: Request,
        runtime: any AIRuntime,
        tools: AIToolRegistry,
        onStep: ((StepEvent) -> Void)? = nil
    ) async throws -> Result {
        let profile = runtime.executionProfile
        var toolCalls = 0
        var steps = 0
        var scratch: [String] = []

        // 1) Pré-sélection déterministe d’outils (le petit modèle ne “décide” pas seul).
        if let deterministic = deterministicFirstTool(for: request) {
            onStep?(StepEvent(label: "Outil : \(deterministic.action)"))
            let result = try await tools.execute(deterministic, profile: profile)
            scratch.append("Résultat \(deterministic.action):\n\(result.text)")
            toolCalls += 1
            steps += 1
        }

        let packet = ConversationContextCompressor.compress(
            history: request.history,
            profile: profile,
            taskHint: request.userText
        )

        while steps < profile.maxWorkflowSteps {
            steps += 1
            onStep?(StepEvent(label: "Étape \(steps)/\(profile.maxWorkflowSteps)"))

            let system = """
            Tu es l’agent Chatbot. Tu disposes d’outils. Réponds soit :
            1) JSON {"type":"tool","action":"<nom>","arguments":{...}}
            2) JSON {"type":"final","content":"<réponse utilisateur>"}
            3) Texte final si tu as assez d’info.
            Outils :
            \(tools.catalogSummary)
            Budgets : max \(profile.maxToolCalls) appels outils, réponses concises.
            Ne invente pas de données mail/web/fichiers : utilise un outil.
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
                userBlob += "\n\nObservations:\n" + scratch.suffix(3).joined(separator: "\n---\n")
            }
            messages.append(LLMChatMessage(role: .user, content: userBlob))

            let raw = try await runtime.generate(
                system: system,
                messages: messages,
                maxTokens: min(profile.maxOutputTokens, 512)
            )

            switch StructuredActionParser.parse(raw) {
            case .final(let text):
                return Result(text: text, stepsUsed: steps, toolCallsUsed: toolCalls)
            case .invalid:
                // Sortie non structurée mais non vide → traiter comme finale.
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty, !cleaned.hasPrefix("{") {
                    return Result(text: cleaned, stepsUsed: steps, toolCallsUsed: toolCalls)
                }
                scratch.append("Parse invalide, reformuler.")
                continue
            case .tool(let call):
                if toolCalls >= profile.maxToolCalls {
                    onStep?(StepEvent(label: "Budget outils atteint — synthèse"))
                    break
                }
                onStep?(StepEvent(label: "Outil : \(call.action)"))
                do {
                    let result = try await tools.execute(call, profile: profile)
                    scratch.append("Résultat \(call.action):\n\(result.text)")
                    toolCalls += 1
                } catch {
                    scratch.append("Erreur \(call.action): \(error.localizedDescription)")
                    toolCalls += 1
                }
            }
        }

        // Synthèse finale forcée (déterministe + LLM court).
        onStep?(StepEvent(label: "Synthèse"))
        let synthSystem = "Synthetise une réponse claire et concise pour l’utilisateur à partir des observations. Pas de JSON."
        var synthMessages = packet.messages
        let obs = scratch.isEmpty ? "(aucune observation outil)" : scratch.joined(separator: "\n---\n")
        synthMessages.append(
            LLMChatMessage(
                role: .user,
                content: "Demande: \(request.userText)\n\nObservations:\n\(obs)\n\nRéponds à l’utilisateur."
            )
        )
        let finalText = try await runtime.generate(
            system: synthSystem,
            messages: synthMessages,
            maxTokens: profile.maxOutputTokens
        )
        return Result(text: finalText, stepsUsed: steps, toolCallsUsed: toolCalls)
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
            || (lower.contains("web") && (lower.contains("cherche") || lower.contains("recherche"))) {
            return AIToolCall(action: "web_search", arguments: ["query": request.userText])
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
        if lower.contains("mail") || lower.contains("e-mail") || lower.contains("email") {
            if lower.contains("cherche") || lower.contains("trouve") || lower.contains("recherche") {
                return AIToolCall(action: "mail_search", arguments: ["query": request.userText])
            }
        }
        if lower.contains("fichier") || lower.contains("files") || lower.contains("document") {
            return AIToolCall(action: "files_list", arguments: ["path": ""])
        }
        if lower.contains("souviens") || lower.contains("mémoire") || lower.contains("memoire") {
            return AIToolCall(action: "memory_recall", arguments: ["query": request.userText])
        }
        return nil
    }

    private static func extractURL(from text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?.firstMatch(in: text, options: [], range: range).flatMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }
}

enum MailSummarizeWorkflow {
    struct Request: Sendable {
        var threadId: String
    }

    @MainActor
    static func run(_ request: Request, runtime: any AIRuntime) async throws -> String {
        _ = runtime.executionProfile // budgets appliqués dans LocalMailAssistant via profile
        let assistant = LocalMailAssistant()
        return try await assistant.summarizeThread(threadId: request.threadId)
    }
}

enum MailReplyWorkflow {
    struct Request: Sendable {
        var threadId: String
        var instruction: String
    }

    @MainActor
    static func run(_ request: Request, runtime: any AIRuntime) async throws -> MailSendConfirmation {
        _ = runtime.executionProfile
        let assistant = LocalMailAssistant()
        return try await assistant.draftReply(
            threadId: request.threadId,
            instruction: request.instruction
        )
    }
}

enum WebSearchWorkflow {
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
        let call = AIToolCall(action: "web_search", arguments: ["query": request.query])
        let result = try await tools.execute(call, profile: profile)
        guard request.synthesize else { return result.text }

        let text = try await runtime.generate(
            system: "Réponds en français avec sources si présentes. Sois concis.",
            messages: [
                LLMChatMessage(
                    role: .user,
                    content: "Question: \(request.query)\n\nRésultats:\n\(result.text)"
                ),
            ],
            maxTokens: profile.maxOutputTokens
        )
        return text
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
            let list = try await tools.execute(
                AIToolCall(action: "files_list", arguments: ["path": request.path]),
                profile: profile
            )
            if request.userQuestion.isEmpty { return list.text }
            return try await runtime.generate(
                system: "Aide sur les fichiers. Utilise uniquement les données fournies.",
                messages: [
                    LLMChatMessage(
                        role: .user,
                        content: "Question: \(request.userQuestion)\n\nDonnées:\n\(list.text)"
                    ),
                ],
                maxTokens: profile.maxOutputTokens
            )
        } catch let error as AIRuntimeError {
            // Échec technique d’outil — pas “Files désactivé parce que modèle petit”.
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
