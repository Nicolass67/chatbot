import Foundation
import UniformTypeIdentifiers
import UIKit

struct ConversationDTO: Identifiable, Codable, Hashable {
    let id: String
    var title: String?
    let updatedAt: String?
    var chatMode: String?
    var reasoningEffort: String?
    var scope: String?
    var contextKey: String?
    var contextLabel: String?
}

struct MessageAttachmentDTO: Identifiable, Codable, Hashable {
    let id: String
    let filename: String?
    let mimeType: String?
    let sizeBytes: Int?
    let type: String?
}

struct MessageDTO: Identifiable, Codable, Hashable {
    let id: String
    let role: String
    let content: String
    let createdAt: String?
    var attachments: [MessageAttachmentDTO]?
}

struct UploadedAttachment: Identifiable, Hashable {
    let id: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    var previewData: Data?
    var isUploading: Bool = false
    var error: String? = nil

    var isImage: Bool {
        mimeType.hasPrefix("image/") || typeHint == "image"
    }

    var typeHint: String {
        mimeType.hasPrefix("image/") ? "image" : "document"
    }
}

struct ChatSendOptions: Sendable {
    var attachmentIds: [String] = []
    var regenerate: Bool = false
    var editMessageId: String? = nil
    var mode: String = "chat"
    var activeContext: ActiveContextHint? = nil
}

struct ModelOptionDTO: Identifiable, Hashable {
    let id: String
    let name: String
}

struct ReasoningModeDTO: Identifiable, Codable, Hashable {
    let id: String
    let label: String?
}

struct ReasoningCapabilitiesDTO: Codable, Hashable {
    let modelId: String?
    let supported: Bool?
    let kind: String?
    let modes: [ReasoningModeDTO]?
    let defaultModeId: String?
}

struct SearchSourceDTO: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let domain: String?
    let snippet: String?
}

struct MailHandoffDTO: Hashable {
    let intent: String?
    let reason: String?
    let query: String?
    let threadId: String?
    let label: String?
}

struct FilesHandoffDTO: Hashable {
    let intent: String?
    let reason: String?
    let query: String?
    let rootId: String?
}

enum APIClientError: LocalizedError {
    case unauthorized
    case http(Int, String)
    case decode

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expirée — reconnectez-vous."
        case .http(let code, let body):
            let lower = body.lowercased()
            if (code == 502 || code == 503) &&
                (lower.contains("backend_offline") || lower.contains("injoignable") || lower.contains("indisponible") || body == "SSE failed") {
                return "Le PC est momentanément injoignable. Réessaie dans quelques secondes."
            }
            if body.isEmpty || body == "SSE failed" {
                return "HTTP \(code)"
            }
            return body.hasPrefix("HTTP") ? body : "HTTP \(code): \(body)"
        case .decode: return "Réponse invalide"
        }
    }
}

final class APIClient: @unchecked Sendable {
    let baseURL: URL
    var token: String?

    init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
    }

    private func authorizedRequest(path: String, method: String = "GET") -> URLRequest {
        // Append each path segment separately — appendingPathComponent("a/b") percent-encodes `/`.
        let segments = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        var url = baseURL
        for segment in segments {
            url = url.appendingPathComponent(segment)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ios", forHTTPHeaderField: "X-Client")
        req.setValue("3.0.0", forHTTPHeaderField: "X-App-Version")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func authorizedURLRequest(_ url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ios", forHTTPHeaderField: "X-Client")
        req.setValue("3.0.0", forHTTPHeaderField: "X-App-Version")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func listConversations(scope: ConversationScope = .general) async throws -> [ConversationDTO] {
        if UITestMode.isActive { return UITestFixtures.conversations(scope: scope) }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/conversations"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "scope", value: scope.rawValue)]
        let req = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode([ConversationDTO].self, from: data)
    }

    func createConversation(
        scope: ConversationScope = .general,
        contextKey: String? = nil,
        contextLabel: String? = nil,
        title: String? = nil
    ) async throws -> ConversationDTO {
        if UITestMode.isActive {
            switch scope {
            case .mail:
                return ConversationDTO(
                    id: "uitest-conv-mail-\(UUID().uuidString.prefix(8))",
                    title: title ?? "Assistant Mail",
                    updatedAt: "2099-01-01T12:00:00Z",
                    chatMode: "chat",
                    reasoningEffort: nil,
                    scope: scope.rawValue,
                    contextKey: contextKey,
                    contextLabel: contextLabel
                )
            case .files:
                return ConversationDTO(
                    id: "uitest-conv-files-\(UUID().uuidString.prefix(8))",
                    title: title ?? "Assistant Files",
                    updatedAt: "2099-01-01T12:00:00Z",
                    chatMode: "chat",
                    reasoningEffort: nil,
                    scope: scope.rawValue,
                    contextKey: contextKey,
                    contextLabel: contextLabel
                )
            case .general:
                return UITestFixtures.emptyConversation
            }
        }
        var req = authorizedRequest(path: "api/conversations", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["scope": scope.rawValue]
        if let contextKey { body["contextKey"] = contextKey }
        if let contextLabel { body["contextLabel"] = contextLabel }
        if let title { body["title"] = title }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(ConversationDTO.self, from: data)
    }

    func renameConversation(id: String, title: String) async throws -> ConversationDTO {
        if UITestMode.isActive {
            return ConversationDTO(
                id: id,
                title: title,
                updatedAt: "2099-01-01T12:00:00Z",
                chatMode: "chat",
                reasoningEffort: nil,
                scope: ConversationScope.general.rawValue,
                contextKey: nil,
                contextLabel: nil
            )
        }
        var req = authorizedRequest(path: "api/conversations/\(id)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(ConversationDTO.self, from: data)
    }

    func deleteConversation(id: String) async throws {
        if UITestMode.isActive { return }
        let req = authorizedRequest(path: "api/conversations/\(id)", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func patchConversation(id: String, chatMode: String? = nil, reasoningEffort: String? = nil) async throws {
        if UITestMode.isActive { return }
        var body: [String: Any] = [:]
        if let chatMode { body["chatMode"] = chatMode }
        if let reasoningEffort { body["reasoningEffort"] = reasoningEffort }
        var req = authorizedRequest(path: "api/conversations/\(id)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func patchConversationMode(id: String, mode: String) async throws {
        try await patchConversation(id: id, chatMode: mode)
    }

    func listMessages(conversationId: String) async throws -> [MessageDTO] {
        if UITestMode.isActive { return UITestFixtures.messages(conversationId: conversationId) }
        let req = authorizedRequest(path: "api/conversations/\(conversationId)/messages")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        if let arr = try? JSONDecoder().decode([MessageDTO].self, from: data) {
            return arr
        }
        struct Wrap: Decodable { let messages: [MessageDTO] }
        return try JSONDecoder().decode(Wrap.self, from: data).messages
    }

    func uploadAttachment(
        conversationId: String,
        filename: String,
        mimeType: String,
        fileData: Data
    ) async throws -> UploadedAttachment {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = authorizedRequest(path: "api/attachments/upload", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"conversationId\"\r\n\r\n")
        append("\(conversationId)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        struct Wrap: Decodable {
            struct Att: Decodable {
                let id: String
                let filename: String?
                let mimeType: String?
                let sizeBytes: Int?
            }
            let attachment: Att
        }
        let decoded = try JSONDecoder().decode(Wrap.self, from: data)
        return UploadedAttachment(
            id: decoded.attachment.id,
            filename: decoded.attachment.filename ?? filename,
            mimeType: decoded.attachment.mimeType ?? mimeType,
            sizeBytes: decoded.attachment.sizeBytes ?? fileData.count,
            previewData: mimeType.hasPrefix("image/") ? fileData : nil
        )
    }

    func deleteAttachment(id: String) async throws {
        let req = authorizedRequest(path: "api/attachments/\(id)", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func attachmentURL(id: String) -> URL {
        baseURL.appendingPathComponent("api/attachments/\(id)")
    }

    func getSettings() async throws -> [String: Any] {
        if UITestMode.isActive {
            return [
                "selectedModel": "uitest-model",
                "defaultReasoningEffort": "medium",
                "webSearchEnabled": false,
            ]
        }
        let req = authorizedRequest(path: "api/settings")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let settings = obj["settings"] as? [String: Any] { return settings }
            return obj
        }
        return [:]
    }

    func getWebSearchEnabled() async throws -> Bool {
        let settings = try await getSettings()
        return (settings["webSearchEnabled"] as? Bool) ?? false
    }

    func setWebSearchEnabled(_ enabled: Bool) async throws {
        if UITestMode.isActive { return }
        var req = authorizedRequest(path: "api/settings", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["webSearchEnabled": enabled])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    /// Planifie l'extinction du PC hôte (Windows, ~60 s).
    @discardableResult
    func shutdownHostPc() async throws -> String {
        if UITestMode.isActive {
            return "Extinction simulée (UITest)."
        }
        let req = authorizedRequest(path: "api/host/shutdown", method: "POST")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = obj["message"] as? String, !message.isEmpty {
                return message
            }
            if let ok = obj["ok"] as? Bool, !ok {
                let message = (obj["message"] as? String) ?? "Échec de l'extinction du PC"
                throw APIClientError.http(500, message)
            }
        }
        return "Extinction du PC planifiée."
    }

    func listModels() async throws -> [ModelOptionDTO] {
        if UITestMode.isActive {
            return [ModelOptionDTO(id: "uitest-model", name: "UITest Model")]
        }
        let req = authorizedRequest(path: "api/lm-studio/models")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        struct Row: Decodable { let id: String; let name: String? }
        struct Wrap: Decodable { let data: [Row]? }
        let decoded = try JSONDecoder().decode(Wrap.self, from: data)
        return (decoded.data ?? []).map { ModelOptionDTO(id: $0.id, name: $0.name ?? $0.id) }
    }

    func selectModel(_ modelKey: String) async throws -> RuntimeSnapshotDTO {
        if UITestMode.isActive {
            return RuntimeSnapshotDTO(
                status: "READY",
                phase: "ready",
                loadedModel: modelKey,
                targetModel: nil,
                preferredModel: modelKey,
                message: nil,
                progress: nil
            )
        }
        var req = authorizedRequest(path: "api/runtime/model", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["modelKey": modelKey])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        let obj = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return RuntimeSnapshotDTO(
            status: (obj["status"] as? String)
                ?? ((obj["phase"] as? String) == "ready" ? "READY" : "LOADING_MODEL"),
            phase: obj["phase"] as? String,
            loadedModel: obj["loadedModel"] as? String,
            targetModel: obj["targetModel"] as? String,
            preferredModel: obj["preferredModel"] as? String,
            message: obj["message"] as? String ?? obj["error"] as? String,
            progress: obj["progress"] as? Double
        )
    }

    struct RuntimeSnapshotDTO {
        let status: String
        let phase: String?
        let loadedModel: String?
        let targetModel: String?
        let preferredModel: String?
        let message: String?
        let progress: Double?
    }

    func runtimeSnapshot() async throws -> RuntimeSnapshotDTO {
        if UITestMode.isActive {
            return RuntimeSnapshotDTO(
                status: "READY",
                phase: "ready",
                loadedModel: "test-model",
                targetModel: nil,
                preferredModel: "test-model",
                message: nil,
                progress: nil
            )
        }
        let req = authorizedRequest(path: "api/runtime/status")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        let obj = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let model = obj["model"] as? [String: Any]
        return RuntimeSnapshotDTO(
            status: (obj["status"] as? String) ?? "UNKNOWN",
            phase: model?["phase"] as? String,
            loadedModel: (model?["loadedModel"] as? String) ?? (obj["modelLoaded"] as? String),
            targetModel: model?["targetModel"] as? String,
            preferredModel: model?["preferredModel"] as? String,
            message: (model?["message"] as? String) ?? (obj["message"] as? String) ?? (model?["error"] as? String),
            progress: model?["progress"] as? Double
        )
    }

    func reasoningCapabilities(modelId: String) async throws -> ReasoningCapabilitiesDTO {
        if UITestMode.isActive {
            return ReasoningCapabilitiesDTO(
                modelId: modelId,
                supported: true,
                kind: "effort",
                modes: [ReasoningModeDTO(id: "medium", label: "Medium")],
                defaultModeId: "medium"
            )
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/runtime/reasoning-capabilities"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "model", value: modelId)]
        let req = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(ReasoningCapabilitiesDTO.self, from: data)
    }

    func sendChat(
        conversationId: String,
        message: String,
        options: ChatSendOptions = ChatSendOptions(),
        streaming: ChatStreamingService,
        onEvent: @escaping @Sendable (ChatSSEParser.Event) -> Void
    ) async throws {
        try await streaming.stream(
            baseURL: baseURL,
            token: token,
            conversationId: conversationId,
            message: message,
            options: options,
            onEvent: onEvent
        )
    }

    /// Compat : stream via service éphémère (préférer `ChatStreamingService` partagé pour Stop).
    func sendChat(
        conversationId: String,
        message: String,
        options: ChatSendOptions = ChatSendOptions(),
        onEvent: @escaping @Sendable (ChatSSEParser.Event) -> Void
    ) async throws {
        let streaming = ChatStreamingService()
        try await sendChat(
            conversationId: conversationId,
            message: message,
            options: options,
            streaming: streaming,
            onEvent: onEvent
        )
    }

    func listMailMessages(
        maxResults: Int = 50,
        category: String? = nil,
        query: String? = nil,
        pageToken: String? = nil
    ) async throws -> MailMessagesPage {
        if UITestMode.isActive {
            var items = UITestFixtures.mailInbox(category: category)
            if let query, !query.isEmpty {
                let q = query.lowercased()
                items = items.filter {
                    ($0.subject ?? "").lowercased().contains(q)
                        || ($0.snippet ?? "").lowercased().contains(q)
                        || ($0.from?.email ?? "").lowercased().contains(q)
                }
            }
            let page = Array(items.prefix(maxResults))
            return MailMessagesPage(
                messages: page,
                nextPageToken: items.count > maxResults ? "uitest-next" : nil,
                resultSizeEstimate: items.count
            )
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/mail/messages"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "maxResults", value: "\(min(max(maxResults, 1), 50))")]
        if let category, !category.isEmpty {
            items.append(URLQueryItem(name: "category", value: category))
        }
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let pageToken, !pageToken.isEmpty {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items
        let request = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(MailMessagesPage.self, from: data)
    }

    func indexFileRoot(rootId: String, purge: Bool = false) async throws -> FileIndexResult {
        if UITestMode.isActive {
            return FileIndexResult(indexed: 3, skipped: 1, purged: purge ? true : nil)
        }
        var req = authorizedRequest(path: "api/files/index", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["rootId": rootId]
        if purge { body["purge"] = true }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(FileIndexResult.self, from: data)
    }

    func oauthAccounts() async throws -> (configured: Bool, emails: [String]) {
        if UITestMode.isActive { return (true, ["uitest@example.com"]) }
        let req = authorizedRequest(path: "api/oauth/accounts")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, [])
        }
        let configured = obj["configured"] as? Bool ?? false
        let accounts = obj["accounts"] as? [[String: Any]] ?? []
        let emails = accounts.compactMap { $0["email"] as? String ?? $0["accountEmail"] as? String }
        return (configured, emails)
    }

    func runtimeStatus() async throws -> String {
        if UITestMode.isActive { return "OK" }
        let req = authorizedRequest(path: "api/runtime/status")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = obj["status"] as? String {
            return status
        }
        return "UNKNOWN"
    }

    func fetchMailThread(id: String) async throws -> MailThreadDTO {
        if UITestMode.isActive { return UITestFixtures.mailThread(id: id) }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIClientError.decode }
        do {
            return try await fetchMailThreadOnce(id: trimmed)
        } catch let APIClientError.http(code, _) where code == 500 || code == 502 || code == 503 {
            // Retry once — Gmail/provider flakes on large threads.
            try await Task.sleep(nanoseconds: 350_000_000)
            return try await fetchMailThreadOnce(id: trimmed)
        }
    }

    private func fetchMailThreadOnce(id: String) async throws -> MailThreadDTO {
        let req = authorizedRequest(path: "api/mail/threads/\(id)")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(MailThreadDTO.self, from: data)
    }

    func markMailRead(id: String) async throws {
        if UITestMode.isActive { return }
        var req = authorizedRequest(path: "api/mail/messages/\(id)/read", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func summarizeMail(threadId: String) async throws -> String {
        if UITestMode.isActive { return UITestFixtures.mailSummaryMarkdown }
        final class Box: @unchecked Sendable {
            var value = ""
        }
        let box = Box()
        try await streamSummarizeMail(threadId: threadId) { box.value += $0 }
        return box.value
    }

    /// Streaming réel résumé mail (SSE backend).
    func streamSummarizeMail(
        threadId: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        if UITestMode.isActive {
            onToken(UITestFixtures.mailSummaryMarkdown)
            return
        }
        var req = authorizedRequest(path: "api/mail/ai/summarize", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "threadId": threadId,
            "stream": true,
        ])
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIClientError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "")
        }
        var buffer = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload.isEmpty || payload == "[DONE]" { continue }
                if let data = payload.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let type = obj["type"] as? String
                    if type == "token", let content = obj["content"] as? String {
                        onToken(content)
                        buffer += content
                    } else if type == "error", let message = obj["message"] as? String {
                        throw APIClientError.http(502, message)
                    }
                }
            }
        }
        if buffer.isEmpty { throw APIClientError.decode }
    }

    struct MailSuggestReplyResult: Sendable {
        let draftId: String?
        let bodyText: String
        let subject: String?
        let to: [String]
    }

    func suggestMailReply(threadId: String, instruction: String? = nil) async throws -> MailSuggestReplyResult {
        if UITestMode.isActive {
            return MailSuggestReplyResult(
                draftId: "uitest-draft-1",
                bodyText: UITestFixtures.mailDraftBody,
                subject: "Re: Facture Free",
                to: ["uitest@example.com"]
            )
        }
        return try await streamSuggestMailReply(threadId: threadId, instruction: instruction) { _ in }
    }

    func streamSuggestMailReply(
        threadId: String,
        instruction: String? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> MailSuggestReplyResult {
        if UITestMode.isActive {
            let body = UITestFixtures.mailDraftBody
            onToken(body)
            return MailSuggestReplyResult(
                draftId: "uitest-draft-1",
                bodyText: body,
                subject: "Re: Facture Free",
                to: ["uitest@example.com"]
            )
        }
        var req = authorizedRequest(path: "api/mail/ai/suggest-reply", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["threadId": threadId, "stream": true]
        if let instruction, !instruction.isEmpty { body["instruction"] = instruction }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIClientError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "")
        }
        var streamed = ""
        var draftId: String?
        var subject: String?
        var to: [String] = []
        var finalBody: String?
        for try await line in bytes.lines {
            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload.isEmpty || payload == "[DONE]" { continue }
                if let data = payload.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let type = obj["type"] as? String
                    if type == "token", let content = obj["content"] as? String {
                        streamed += content
                        onToken(content)
                    } else if type == "done" {
                        draftId = obj["draftId"] as? String
                        subject = obj["subject"] as? String
                        finalBody = obj["bodyText"] as? String
                        if let draft = obj["draft"] as? [String: Any] {
                            to = (draft["to"] as? [String]) ?? []
                        }
                    } else if type == "error", let message = obj["message"] as? String {
                        throw APIClientError.http(502, message)
                    }
                }
            }
        }
        let text = (finalBody?.isEmpty == false ? finalBody! : streamed)
        guard !text.isEmpty else { throw APIClientError.decode }
        return MailSuggestReplyResult(
            draftId: draftId,
            bodyText: text,
            subject: subject,
            to: to
        )
    }

    func updateEmailDraft(id: String, bodyText: String, to: [String]? = nil) async throws {
        if UITestMode.isActive { return }
        var req = authorizedRequest(path: "api/email/drafts/\(id)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["bodyText": bodyText]
        if let to { payload["to"] = to }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func attachFilesToEmailDraft(id: String, attachmentIds: [String]) async throws {
        if UITestMode.isActive { return }
        guard !attachmentIds.isEmpty else { return }
        // GET pour fusionner avec les PJ déjà présentes.
        let getReq = authorizedRequest(path: "api/email/drafts/\(id)")
        let (getData, getResp) = try await URLSession.shared.data(for: getReq)
        try throwIfNeeded(getResp, getData)
        var existingIds: [String] = []
        if let obj = try? JSONSerialization.jsonObject(with: getData) as? [String: Any] {
            if let atts = obj["attachments"] as? [[String: Any]] {
                existingIds = atts.compactMap { $0["id"] as? String }
            } else if let ids = obj["attachmentIds"] as? [String] {
                existingIds = ids
            }
        }
        let merged = Array(Set(existingIds + attachmentIds))
        var req = authorizedRequest(path: "api/email/drafts/\(id)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "attachmentIds": merged,
        ] as [String: Any])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func validateEmailDraft(id: String) async throws {
        if UITestMode.isActive { return }
        var req = authorizedRequest(path: "api/email/drafts/\(id)/validate", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    struct EmailSendProposal: Sendable {
        let actionId: String
        let confirmationToken: String
    }

    func proposeEmailSend(draftId: String) async throws -> EmailSendProposal {
        var req = authorizedRequest(path: "api/email/actions/send", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["draftId": draftId])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionId = obj["actionId"] as? String ?? (obj["action"] as? [String: Any])?["id"] as? String,
              let token = obj["confirmationToken"] as? String
                ?? (obj["action"] as? [String: Any])?["confirmationToken"] as? String
        else {
            throw APIClientError.decode
        }
        return EmailSendProposal(actionId: actionId, confirmationToken: token)
    }

    func confirmEmailSend(
        actionId: String,
        confirmationToken: String,
        conversationId: String
    ) async throws {
        var req = authorizedRequest(path: "api/email/actions/\(actionId)/confirm", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "confirmationToken": confirmationToken,
            "conversationId": conversationId,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func downloadMailAttachment(messageId: String, attachmentId: String) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/mail/messages/\(messageId)/attachment"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "attachmentId", value: attachmentId),
            URLQueryItem(name: "download", value: "1"),
        ]
        let req = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return data
    }

    struct MailTrashProposal: Sendable {
        let actionId: String
        let confirmationToken: String
    }

    func proposeMailTrash(messageId: String) async throws -> MailTrashProposal {
        var req = authorizedRequest(path: "api/mail/actions/trash", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["messageId": messageId])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionId = obj["actionId"] as? String,
              let token = obj["confirmationToken"] as? String
        else { throw APIClientError.decode }
        return MailTrashProposal(actionId: actionId, confirmationToken: token)
    }

    func confirmMailTrash(actionId: String, confirmationToken: String) async throws {
        var req = authorizedRequest(path: "api/mail/actions/\(actionId)/confirm", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["confirmationToken": confirmationToken])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    /// Charge une miniature (serveur `?w=`) puis fallback full — cache mémoire + disque.
    func loadAttachmentImage(id: String, maxPixelSize: CGFloat = 360) async throws -> UIImage {
        let w = Int(maxPixelSize)
        let cacheKey = "att-\(id)-w\(w)"
        if let cached = await ImagePipeline.cached(cacheKey) { return cached }

        var components = URLComponents(url: attachmentURL(id: id), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "w", value: "\(w)")]
        let req = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        guard let image = ImagePipeline.downsample(data: data, maxPixelSize: maxPixelSize)
            ?? UIImage(data: data) else {
            throw APIClientError.decode
        }
        await ImagePipeline.store(image, key: cacheKey)
        return image
    }

    func conversationContext(conversationId: String) async throws -> ContextSnapshotDTO {
        if UITestMode.isActive {
            return ContextSnapshotDTO(
                conversationTokens: 120,
                contextLengthMax: 128_000,
                budgetTokens: 8_000,
                usedPercent: 1.5,
                remainingPercent: 98.5
            )
        }
        let req = authorizedRequest(path: "api/conversations/\(conversationId)/context")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(ContextSnapshotDTO.self, from: data)
    }

    func prefetchAttachmentThumbs(ids: [String], maxPixelSize: CGFloat = 360) {
        for id in ids {
            Task.detached(priority: .utility) { [baseURL, token] in
                let client = APIClient(baseURL: baseURL, token: token)
                _ = try? await client.loadAttachmentImage(id: id, maxPixelSize: maxPixelSize)
            }
        }
    }

    func confirmFilesAction(actionId: String, confirmationToken: String, confirm: Bool) async throws {
        var req = authorizedRequest(path: "api/files/actions", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "actionId": actionId,
            "action": confirm ? "confirm" : "cancel",
            "confirmationToken": confirmationToken,
        ] as [String: Any])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func proposeCreateDirectory(rootId: String, destRelativePath: String) async throws -> FilesProposeResult {
        try await proposeFilesMutation([
            "op": "create_directory",
            "destRootId": rootId,
            "destRelativePath": destRelativePath,
        ])
    }

    func proposeRenameFile(sourceFileId: String, newName: String) async throws -> FilesProposeResult {
        try await proposeFilesMutation([
            "op": "rename_file",
            "sourceFileId": sourceFileId,
            "newName": newName,
        ])
    }

    func proposeMoveFile(sourceFileId: String, destRootId: String, destRelativePath: String) async throws -> FilesProposeResult {
        try await proposeFilesMutation([
            "op": "move_file",
            "sourceFileId": sourceFileId,
            "destRootId": destRootId,
            "destRelativePath": destRelativePath,
        ])
    }

    /// Proposition de plan d’organisation intelligente (JSON brut pour parsing côté SmartOrganizer).
    func proposeOrganizationPlan(
        rootId: String,
        rootRelativePath: String,
        items: [[String: Any]],
        protectedPaths: [String],
        instruction: String?
    ) async throws -> Data {
        var body: [String: Any] = [
            "rootId": rootId,
            "rootRelativePath": rootRelativePath,
            "items": items,
            "protectedPaths": protectedPaths,
        ]
        if let instruction, !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["instruction"] = instruction
        }
        var req = authorizedRequest(path: "api/files/organize/plan", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return data
    }

    func proposeDeleteFile(sourceFileId: String) async throws -> FilesProposeResult {
        try await proposeFilesMutation([
            "op": "delete_file",
            "sourceFileId": sourceFileId,
        ])
    }

    private func proposeFilesMutation(_ body: [String: Any]) async throws -> FilesProposeResult {
        var req = authorizedRequest(path: "api/files/propose", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionId = obj["actionId"] as? String,
              let token = obj["confirmationToken"] as? String
        else { throw APIClientError.decode }
        let op = (obj["op"] as? String) ?? (body["op"] as? String) ?? "mutation"
        let payload = obj["payload"] as? [String: Any]
        let destRelativePath = (payload?["destRelativePath"] as? String)
            ?? (body["destRelativePath"] as? String)
            ?? ""
        let detail = destRelativePath.isEmpty
            ? ((payload?["sourceRelativePath"] as? String) ?? op)
            : destRelativePath
        return FilesProposeResult(
            actionId: actionId,
            confirmationToken: token,
            expiresAt: obj["expiresAt"] as? String,
            op: op,
            destRelativePath: destRelativePath.isEmpty ? detail : destRelativePath,
            detail: detail
        )
    }

    func uploadFiles(
        rootId: String,
        destRelativePath: String,
        filename: String,
        data fileData: Data,
        mimeType: String
    ) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = authorizedRequest(path: "api/files/upload", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"rootId\"\r\n\r\n\(rootId)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"destRelativePath\"\r\n\r\n\(destRelativePath)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func gmailAuthorizationURL() async throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/oauth/gmail/start"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "json")]
        var req = authorizedURLRequest(components.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let s = obj["authorizationUrl"] as? String,
           let url = URL(string: s) {
            return url
        }
        throw APIClientError.decode
    }

    func disconnectGmail() async throws {
        let req = authorizedRequest(path: "api/oauth/gmail/disconnect", method: "POST")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func listMemories(query: String? = nil) async throws -> [MemoryDTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/memories"), resolvingAgainstBaseURL: false)!
        if let query, !query.isEmpty {
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        let req = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode([MemoryDTO].self, from: data)
    }

    func createMemory(content: String) async throws {
        var req = authorizedRequest(path: "api/memories", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = obj["success"] as? Bool, !success {
            throw APIClientError.http(400, (obj["reason"] as? String) ?? "Mémoire refusée")
        }
    }

    func deleteMemory(id: String) async throws {
        let req = authorizedRequest(path: "api/memories/\(id)", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
    }

    func updateMemory(id: String, content: String) async throws -> MemoryDTO {
        var req = authorizedRequest(path: "api/memories/\(id)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(MemoryDTO.self, from: data)
    }

    func listFileRoots() async throws -> [FileRootDTO] {
        if UITestMode.isActive { return UITestFixtures.fileRoots }
        let req = authorizedRequest(path: "api/files/roots")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(resp, data)
        struct Wrap: Decodable { let roots: [FileRootDTO] }
        return try JSONDecoder().decode(Wrap.self, from: data).roots
    }

    func listFiles(rootId: String, path: String = "", cursor: String? = nil) async throws -> FileListDTO {
        if UITestMode.isActive { return UITestFixtures.listFiles(rootId: rootId, path: path) }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/files/list"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "root", value: rootId),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "limit", value: "200"),
        ]
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = items
        let request = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(resp, data)
        return try JSONDecoder().decode(FileListDTO.self, from: data)
    }

    func searchFiles(query: String, rootId: String? = nil, mode: String = "name") async throws -> [FileSearchHitDTO] {
        if UITestMode.isActive {
            let q = query.lowercased()
            return [
                FileSearchHitDTO(
                    fileId: "uitest-file-notes",
                    name: "notes.txt",
                    filename: "notes.txt",
                    relativePath: "notes.txt",
                    rootId: UITestFixtures.documentsRoot.id,
                    sizeBytes: 128,
                    isDirectory: false,
                    snippet: "UITest fixture",
                    matchSource: "name"
                ),
            ].filter { ($0.name ?? "").lowercased().contains(q) || q.count < 2 }
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/files/search"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mode", value: mode),
        ]
        if let rootId { items.append(URLQueryItem(name: "root", value: rootId)) }
        components.queryItems = items
        let request = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(resp, data)
        struct Wrap: Decodable { let results: [FileSearchHitDTO]? }
        return try JSONDecoder().decode(Wrap.self, from: data).results ?? []
    }

    func downloadFileBytes(fileId: String) async throws -> (Data, String, String) {
        if UITestMode.isActive {
            let name = "uitest.txt"
            return (Data("hello".utf8), name, "text/plain")
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/files/content"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "fileId", value: fileId),
            URLQueryItem(name: "download", value: "1"),
        ]
        let request = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(resp, data)
        guard let http = resp as? HTTPURLResponse else { throw APIClientError.decode }
        let mime = http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        var filename = "fichier"
        if let raw = http.value(forHTTPHeaderField: "X-Files-Name"),
           let decoded = raw.removingPercentEncoding,
           !decoded.isEmpty {
            filename = decoded
        } else if let cd = http.value(forHTTPHeaderField: "Content-Disposition"),
                  let range = cd.range(of: "filename=\""),
                  let end = cd[range.upperBound...].firstIndex(of: "\"") {
            let encoded = String(cd[range.upperBound..<end])
            filename = encoded.removingPercentEncoding ?? encoded
        }
        return (data, filename, mime)
    }

    func fetchFileContent(fileId: String) async throws -> FileContentDTO {
        if UITestMode.isActive { return UITestFixtures.fileContent(fileId: fileId) }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/files/content"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fileId", value: fileId)]
        let request = authorizedURLRequest(components.url!)
        let (data, resp) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(resp, data)
        if let http = resp as? HTTPURLResponse,
           let kind = http.value(forHTTPHeaderField: "X-Files-Kind"),
           kind == "image" || kind == "pdf" {
            return FileContentDTO(
                kind: kind,
                text: nil,
                name: nil,
                mime: http.value(forHTTPHeaderField: "Content-Type"),
                truncated: false,
                binary: data
            )
        }
        if let obj = try? JSONDecoder().decode(FileContentDTO.self, from: data) {
            return obj
        }
        throw APIClientError.decode
    }

    private func throwIfNeeded(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw APIClientError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.http(http.statusCode, body)
        }
    }
}

struct MailAddressDTO: Codable, Hashable {
    let email: String
    let name: String?
}

struct MailMessageSummary: Identifiable, Codable, Hashable {
    let id: String
    let threadId: String?
    let from: MailAddressDTO?
    let subject: String?
    let snippet: String?
    let date: String?
    let isUnread: Bool?
    let hasAttachments: Bool?

    func withUnread(_ value: Bool) -> MailMessageSummary {
        MailMessageSummary(
            id: id,
            threadId: threadId,
            from: from,
            subject: subject,
            snippet: snippet,
            date: date,
            isUnread: value,
            hasAttachments: hasAttachments
        )
    }
}

struct MailMessagesPage: Codable, Hashable {
    let messages: [MailMessageSummary]
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct FileIndexResult: Codable, Hashable {
    let indexed: Int?
    let skipped: Int?
    let purged: Bool?
    let ok: Bool?

    init(indexed: Int? = nil, skipped: Int? = nil, purged: Bool? = nil, ok: Bool? = nil) {
        self.indexed = indexed
        self.skipped = skipped
        self.purged = purged
        self.ok = ok
    }
}

struct MailThreadMessage: Identifiable, Codable, Hashable {
    let id: String
    let threadId: String?
    let from: MailAddressDTO?
    let subject: String?
    let date: String?
    let snippet: String?
    let bodyText: String?
    let bodyHtml: String?
    let isUnread: Bool?
    let hasAttachments: Bool?
    let attachments: [MailAttachmentDTO]?
}

struct MailThreadDTO: Identifiable, Codable, Hashable {
    let id: String
    let subject: String?
    let messages: [MailThreadMessage]?
}

struct ContextSnapshotDTO: Codable, Hashable {
    let conversationTokens: Int?
    let contextLengthMax: Int?
    let budgetTokens: Int?
    let usedPercent: Double?
    let remainingPercent: Double?
}

struct FileRootDTO: Identifiable, Codable, Hashable {
    let id: String
    let label: String?
    let absolutePath: String?
    let enabled: Bool?
}

struct FileEntryDTO: Identifiable, Codable, Hashable {
    /// ID stable pour NavigationLink (path unique sous la root).
    var id: String { relativePath }
    let fileId: String?
    let name: String?
    let relativePath: String
    let isDirectory: Bool?
    let sizeBytes: Int?
    /// Epoch ms — déjà fourni par `/api/files/list`.
    let mtimeMs: Int?
    let indexed: Bool?
}

struct FileListDTO: Codable, Hashable {
    let fileId: String?
    let entries: [FileEntryDTO]
    let nextCursor: String?
}

struct FileSearchHitDTO: Identifiable, Codable, Hashable {
    var id: String { fileId }
    let fileId: String
    let name: String?
    let filename: String?
    let relativePath: String?
    let rootId: String?
    let sizeBytes: Int?
    let isDirectory: Bool?
    let snippet: String?
    let matchSource: String?
}

struct FileContentDTO: Codable, Hashable {
    let kind: String?
    let text: String?
    let name: String?
    let mime: String?
    let truncated: Bool?
    var binary: Data? = nil

    enum CodingKeys: String, CodingKey {
        case kind, text, name, mime, truncated
    }
}

struct FilesProposeResult: Sendable, Identifiable {
    var id: String { actionId }
    let actionId: String
    let confirmationToken: String
    let expiresAt: String?
    let op: String
    /// Chemin relatif cible (mkdir / move) — aussi exposé via `detail` pour l’UI.
    let destRelativePath: String
    let detail: String
}
