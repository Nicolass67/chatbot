import Foundation

/// Outils Mail — même surface ; exécution via Gmail device + budgets du profile.
struct MailSearchTool: AITool {
    var name: String { "mail_search" }
    var summary: String { "Recherche mails Gmail. Arguments: query" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let query = (arguments["query"] ?? arguments["q"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AIRuntimeError.toolInvalidArguments("query requis")
        }
        guard GmailOAuthSession.shared.isConnected else {
            throw AIRuntimeError.toolFailed("Gmail non connecté sur cet iPhone.")
        }
        let client = DirectGmailClient(oauth: .shared)
        let max = max(1, min(profile.maxMailMessages, 12))
        let page = try await client.listMessages(query: query, pageToken: nil, maxResults: max)
        if page.messages.isEmpty {
            return AIToolResult(action: name, ok: true, text: "Aucun mail pour « \(query) ».", truncated: false)
        }
        let body = page.messages.prefix(max).enumerated().map { idx, m in
            """
            [\(idx + 1)] id=\(m.id)
            De: \(m.from ?? "—") | Objet: \(m.subject ?? "—")
            \(String((m.snippet ?? "").prefix(profile.maxWebSnippetChars)))
            """
        }.joined(separator: "\n\n")
        return AIToolResult(action: name, ok: true, text: body, truncated: false)
    }
}

struct MailSummarizeTool: AITool {
    var name: String { "mail_summarize" }
    var summary: String { "Résume un fil mail. Arguments: threadId" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let threadId = (arguments["threadId"] ?? arguments["id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadId.isEmpty else {
            throw AIRuntimeError.toolInvalidArguments("threadId requis")
        }
        let assistant = LocalMailAssistant()
        let text = try await assistant.summarizeThread(threadId: threadId)
        let clipped = String(text.prefix(profile.toolResultCharBudget))
        return AIToolResult(
            action: name,
            ok: true,
            text: clipped,
            truncated: text.count > clipped.count
        )
    }
}

struct MailDraftReplyTool: AITool {
    var name: String { "mail_draft_reply" }
    var summary: String { "Propose une réponse (non envoyée). Arguments: threadId, instruction" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let threadId = (arguments["threadId"] ?? arguments["id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadId.isEmpty else {
            throw AIRuntimeError.toolInvalidArguments("threadId requis")
        }
        let instruction = (arguments["instruction"] ?? arguments["query"] ?? "Réponds poliment.")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = LocalMailAssistant()
        let confirmation = try await assistant.draftReply(threadId: threadId, instruction: instruction)
        let text = """
        Proposition (non envoyée)
        À: \(confirmation.to)
        Objet: \(confirmation.subject)

        \(confirmation.proposedBody)
        """
        let clipped = String(text.prefix(profile.toolResultCharBudget))
        return AIToolResult(
            action: name,
            ok: true,
            text: clipped,
            truncated: text.count > clipped.count
        )
    }
}

/// Files — même outil ; sans PC PathGuard = échec technique d’outil, pas “feature absente”.
struct FilesListTool: AITool {
    var name: String { "files_list" }
    var summary: String { "Liste des fichiers (nécessite backend PC). Arguments: path (optionnel)" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        _ = arguments
        _ = profile
        // Sans session PC authentifiée, PathGuard serveur est indisponible.
        // Ce n’est PAS un gating modèle : c’est une dépendance d’infrastructure.
        throw AIRuntimeError.toolFailed(
            "L’outil Files nécessite le backend PC (PathGuard). Connecte le PC pour lister les fichiers distants. " +
            "Les documents locaux du téléphone pourront être traités via extraction/chunks quand un chemin local est fourni."
        )
    }
}

/// Mémoire — sélection déterministe / stub local (store mémoire applicatif).
struct MemoryRecallTool: AITool {
    var name: String { "memory_recall" }
    var summary: String { "Rappelle des faits pertinents. Arguments: query" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let query = (arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let store = LocalMemoryStore.shared
        let facts = store.recall(matching: query, budget: profile.toolResultCharBudget / 2)
        if facts.isEmpty {
            return AIToolResult(
                action: name,
                ok: true,
                text: "Aucun fait mémorisé pertinent pour le moment.",
                truncated: false
            )
        }
        return AIToolResult(action: name, ok: true, text: facts, truncated: false)
    }
}
