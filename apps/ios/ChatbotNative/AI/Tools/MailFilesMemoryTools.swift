import Foundation

/// Outils Mail — même surface ; exécution via Gmail device + budgets du profile.
struct MailSearchTool: AITool {
    var name: String { "mail_search" }
    var summary: String { "Recherche mails Gmail. Arguments: query" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let userQuery = (arguments["query"] ?? arguments["q"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let intent = MailIntentDetector.detect(userQuery, hasOpenThread: false)
        let gmailQ = (arguments["gmailQuery"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let q = gmailQ.isEmpty
            ? MailIntentDetector.gmailQuery(for: intent == .none ? .genericMailbox : intent, userText: userQuery)
            : gmailQ
        guard !q.isEmpty else {
            throw AIRuntimeError.toolInvalidArguments("query requis")
        }
        guard GmailOAuthSession.shared.isConnected else {
            throw AIRuntimeError.toolFailed("Gmail non connecté sur cet iPhone.")
        }
        try Task.checkCancellation()
        let client = DirectGmailClient(oauth: .shared)
        let max = MailIntentDetector.resultLimit(
            for: intent == .none ? .genericMailbox : intent,
            profile: profile
        )
        let page = try await client.listMessages(query: q, pageToken: nil, maxResults: max)
        if page.messages.isEmpty {
            return AIToolResult(
                action: name,
                ok: true,
                text: "Aucun mail Gmail pour cette recherche (q=\(q)).",
                truncated: false
            )
        }
        let fetchBodies = (arguments["fetchBodies"] ?? "true").lowercased() != "false"
        var blocks: [String] = []
        var firstThread: String?
        for (idx, m) in page.messages.prefix(max).enumerated() {
            try Task.checkCancellation()
            if firstThread == nil { firstThread = m.threadId ?? m.id }
            var bodySnippet = m.snippet ?? ""
            if fetchBodies {
                if let full = try? await client.getMessage(id: m.id) {
                    let raw = MailThreadPromptBuilder.preferredBody(full)
                    bodySnippet = MailThreadPromptBuilder.clipBody(
                        MailThreadPromptBuilder.sanitize(raw),
                        maxChars: profile.maxMailBodyChars / max(max, 1)
                    )
                }
            }
            blocks.append(
                """
                [\(idx + 1)] messageId=\(m.id) threadId=\(m.threadId ?? m.id)
                De: \(m.from ?? "—")
                Objet: \(m.subject ?? "—")
                Date: \(m.date ?? "—")
                \(bodySnippet)
                """
            )
        }
        return AIToolResult(
            action: name,
            ok: true,
            text: blocks.joined(separator: "\n\n"),
            truncated: false,
            mailThreadId: firstThread
        )
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

/// Files — Documents iPhone en local ; PathGuard PC si une session distante est utilisée.
struct FilesListTool: AITool {
    var name: String { "files_list" }
    var summary: String { "Liste des fichiers locaux (iPhone) ou distants. Arguments: path (optionnel)" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let path = (arguments["path"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let text = try LocalFilesStore.catalogText(path: path, profile: profile)
            return AIToolResult(action: name, ok: true, text: text, truncated: false)
        } catch {
            throw AIRuntimeError.toolFailed(error.localizedDescription)
        }
    }
}

struct FilesSearchTool: AITool {
    var name: String { "files_search" }
    var summary: String { "Recherche des fichiers locaux par nom. Arguments: query" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let query = (arguments["query"] ?? arguments["q"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AIRuntimeError.toolInvalidArguments("query requis")
        }
        let hits = LocalFilesStore.search(query: query, profile: profile)
        if hits.isEmpty {
            return AIToolResult(
                action: name,
                ok: true,
                text: "Aucun fichier local nommé comme « \(query) ».",
                truncated: false
            )
        }
        let lines = hits.prefix(profile.maxDocumentChunks).map { hit in
            "- \(hit.name ?? hit.filename ?? hit.fileId) path=\(hit.relativePath ?? "")"
        }
        return AIToolResult(
            action: name,
            ok: true,
            text: "Fichiers locaux :\n" + lines.joined(separator: "\n"),
            truncated: hits.count > profile.maxDocumentChunks
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
