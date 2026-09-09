import Foundation

// MARK: - DTOs

struct DirectMailMessage: Identifiable, Hashable, Sendable {
    let id: String
    let threadId: String?
    let subject: String?
    let from: String?
    let snippet: String?
    let date: String?
    let bodyPlain: String?
    let bodyHtml: String?
    let labelIds: [String]
    var rfc822MessageId: String? = nil
    var rfc822References: String? = nil
}

struct DirectMailThread: Identifiable, Hashable, Sendable {
    let id: String
    let threadId: String?
    let subject: String?
    let from: String?
    let snippet: String?
    let date: String?
    let bodyPlain: String?
    let labelIds: [String]
    let messages: [DirectMailMessage]
}

struct DirectMailListPage: Hashable, Sendable {
    let messages: [DirectMailMessage]
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct DirectMailDraft: Hashable, Sendable {
    let id: String
    let messageId: String?
    let threadId: String?
}

enum DirectGmailError: Error, LocalizedError, Sendable {
    case notConnected
    case unauthorized
    case http(Int, String)
    case decode
    case invalidArgument(String)
    /// Envoi bloqué : doit passer par la confirmation UI (`MailSendConfirmation` / `confirmSend`).
    case sendRequiresConfirmation
    case insufficientScopes
    case sendInProgress
    case emptyOutboundBody

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Aucun compte Gmail connecté sur cet iPhone."
        case .unauthorized:
            return "Session Gmail expirée. Reconnecte ton compte."
        case .http(let code, let detail):
            if code == 429 {
                return "Gmail est saturé (quota). Attends un instant puis réessaie."
            }
            if code >= 500 {
                return "Gmail est temporairement indisponible (\(code))."
            }
            if Self.looksLikeInsufficientScopes(detail) {
                return Self.insufficientScopesMessage
            }
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Erreur Gmail (HTTP \(code))."
                : "Erreur Gmail (HTTP \(code)) : \(trimmed)"
        case .decode:
            return "Réponse Gmail illisible."
        case .invalidArgument(let detail):
            return detail
        case .sendRequiresConfirmation:
            return "L’envoi nécessite une confirmation explicite."
        case .insufficientScopes:
            return Self.insufficientScopesMessage
        case .sendInProgress:
            return "Envoi déjà en cours."
        case .emptyOutboundBody:
            return "Impossible d’envoyer un message vide."
        }
    }

    static let insufficientScopesMessage = "Autorisation Gmail requise pour cette action."

    var isInsufficientScopes: Bool {
        switch self {
        case .insufficientScopes:
            return true
        case .http(let code, let detail):
            return code == 403 && Self.looksLikeInsufficientScopes(detail)
        default:
            return false
        }
    }

    static func looksLikeInsufficientScopes(_ detail: String) -> Bool {
        let lower = detail.lowercased()
        return lower.contains("insufficient authentication scopes")
            || lower.contains("insufficientpermissions")
            || lower.contains("access not configured")
    }

    static func isInsufficientScopes(_ error: Error) -> Bool {
        if let gmail = error as? DirectGmailError { return gmail.isInsufficientScopes }
        return looksLikeInsufficientScopes(error.localizedDescription)
    }
}

// MARK: - Client

/// Client REST Gmail API v1 — Bearer access token (device), **sans** passer par le PC.
///
/// `sendMessage` / `sendDraft` ne doivent être appelés **qu’après** confirmation UI
/// (`LocalMailAssistant.confirmSend` ou équivalent). Ne pas les brancher sur la sortie brute du LLM.
@MainActor
final class DirectGmailClient {
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
    private let session: URLSession
    private let oauth: GmailOAuthSession

    init(oauth: GmailOAuthSession = .shared, urlSession: URLSession = .shared) {
        self.oauth = oauth
        self.session = urlSession
    }

    // MARK: List / get

    func listMessages(
        query: String? = nil,
        pageToken: String? = nil,
        maxResults: Int = 25
    ) async throws -> DirectMailListPage {
        var components = URLComponents(url: baseURL.appendingPathComponent("messages"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "maxResults", value: "\(min(max(maxResults, 1), 100))")]
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let pageToken, !pageToken.isEmpty {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items
        let obj = try await jsonObject(url: components.url!)
        let refs = obj["messages"] as? [[String: Any]] ?? []
        let next = obj["nextPageToken"] as? String
        let estimate = obj["resultSizeEstimate"] as? Int

        // Métadonnées légères (évite N× format=full pour la boîte).
        var messages: [DirectMailMessage] = []
        messages.reserveCapacity(refs.count)
        for ref in refs {
            guard let id = ref["id"] as? String else { continue }
            let meta = try await getMessageMetadata(id: id)
            messages.append(meta)
        }
        return DirectMailListPage(
            messages: messages,
            nextPageToken: next,
            resultSizeEstimate: estimate
        )
    }

    func getMessage(id: String) async throws -> DirectMailMessage {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DirectGmailError.invalidArgument("Identifiant de message manquant.") }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("messages").appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        let obj = try await jsonObject(url: components.url!)
        return Self.mapMessage(obj)
    }

    func getThread(id: String) async throws -> DirectMailThread {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DirectGmailError.invalidArgument("Identifiant de fil manquant.") }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("threads").appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        let obj = try await jsonObject(url: components.url!)
        let threadId = (obj["id"] as? String) ?? trimmed
        let rawMessages = obj["messages"] as? [[String: Any]] ?? []
        let mapped = rawMessages.map { Self.mapMessage($0) }
        let last = mapped.last
        let first = mapped.first
        return DirectMailThread(
            id: threadId,
            threadId: threadId,
            subject: last?.subject ?? first?.subject,
            from: last?.from ?? first?.from,
            snippet: last?.snippet ?? first?.snippet,
            date: last?.date ?? first?.date,
            bodyPlain: mapped.map { $0.bodyPlain ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n\n---\n\n"),
            labelIds: last?.labelIds ?? first?.labelIds ?? [],
            messages: mapped
        )
    }

    // MARK: Draft / send
    //
    // Action            → endpoint                         → scope
    // list/get          → messages.list / get, threads.get → gmail.readonly
    // send              → users.messages.send              → gmail.send | compose | modify
    // drafts (legacy)   → drafts.create / send / delete    → gmail.compose
    // mark read         → messages.modify (-UNREAD)        → gmail.modify
    // trash             → messages.trash                   → gmail.modify
    //
    // L’assistant n’utilise plus drafts.create à la rédaction.

    func createDraft(
        to: String,
        subject: String,
        body: String,
        threadId: String? = nil
    ) async throws -> DirectMailDraft {
        try await withScopeRecovery {
            let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTo.isEmpty else {
                throw DirectGmailError.invalidArgument("Destinataire manquant.")
            }
            let raw = try GmailRfc822.encodeRaw(to: trimmedTo, subject: subject, body: body)
            var message: [String: Any] = ["raw": raw]
            if let threadId, !threadId.isEmpty {
                message["threadId"] = threadId
            }
            let payload: [String: Any] = ["message": message]
            let obj = try await jsonObject(
                url: baseURL.appendingPathComponent("drafts"),
                method: "POST",
                jsonBody: payload
            )
            let draftId = obj["id"] as? String ?? ""
            let msg = obj["message"] as? [String: Any]
            return DirectMailDraft(
                id: draftId,
                messageId: msg?["id"] as? String,
                threadId: msg?["threadId"] as? String ?? threadId
            )
        }
    }

    /// Envoie un brouillon existant — évité pour l’assistant (préférer `sendMessage`).
    func sendDraft(id: String) async throws {
        let lock = try GmailSendLock.acquire()
        defer { GmailSendLock.release(lock) }
        try await withScopeRecovery {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DirectGmailError.invalidArgument("Identifiant de brouillon manquant.")
            }
            _ = try await jsonObject(
                url: baseURL.appendingPathComponent("drafts").appendingPathComponent("send"),
                method: "POST",
                jsonBody: ["id": trimmed]
            )
        }
    }

    func deleteDraft(id: String) async throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await withScopeRecovery {
            _ = try await jsonObject(
                url: baseURL.appendingPathComponent("drafts").appendingPathComponent(trimmed),
                method: "DELETE"
            )
        }
    }

    /// Envoie un message immédiatement (raw). Un seul appel réseau d’envoi.
    func sendMessage(
        to: String,
        subject: String,
        body: String,
        threadId: String? = nil,
        cc: String? = nil,
        bcc: String? = nil,
        inReplyTo: String? = nil,
        references: String? = nil,
        attachments: [(filename: String, mimeType: String, data: Data)] = []
    ) async throws {
        let lock = try GmailSendLock.acquire()
        defer { GmailSendLock.release(lock) }
        try await withScopeRecovery {
            let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTo.isEmpty else {
                throw DirectGmailError.invalidArgument("Destinataire manquant.")
            }
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBody.isEmpty else {
                throw DirectGmailError.emptyOutboundBody
            }
            let raw = try GmailRfc822.encodeRaw(
                to: trimmedTo,
                cc: cc,
                bcc: bcc,
                subject: subject,
                body: trimmedBody,
                inReplyTo: inReplyTo,
                references: references,
                attachments: attachments.map {
                    GmailRfc822.Attachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
                }
            )
            var payload: [String: Any] = ["raw": raw]
            if let threadId, !threadId.isEmpty {
                payload["threadId"] = threadId
            }
            _ = try await jsonObject(
                url: baseURL.appendingPathComponent("messages").appendingPathComponent("send"),
                method: "POST",
                jsonBody: payload
            )
        }
    }

    func markRead(
        messageId: String,
        threadId: String? = nil,
        recoverScopes: Bool = true
    ) async throws {
        func perform() async throws {
            let trimmed = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DirectGmailError.invalidArgument("Identifiant de message manquant.")
            }
            _ = try await jsonObject(
                url: baseURL
                    .appendingPathComponent("messages")
                    .appendingPathComponent(trimmed)
                    .appendingPathComponent("modify"),
                method: "POST",
                jsonBody: ["removeLabelIds": ["UNREAD"]]
            )
            let thread = (threadId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !thread.isEmpty {
                _ = try? await jsonObject(
                    url: baseURL
                        .appendingPathComponent("threads")
                        .appendingPathComponent(thread)
                        .appendingPathComponent("modify"),
                    method: "POST",
                    jsonBody: ["removeLabelIds": ["UNREAD"]]
                )
            }
        }
        if recoverScopes {
            try await withScopeRecovery { try await perform() }
        } else {
            try await perform()
        }
    }

    func trashMessage(messageId: String, recoverScopes: Bool = true) async throws {
        func perform() async throws {
            let trimmed = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DirectGmailError.invalidArgument("Identifiant de message manquant.")
            }
            _ = try await jsonObject(
                url: baseURL
                    .appendingPathComponent("messages")
                    .appendingPathComponent(trimmed)
                    .appendingPathComponent("trash"),
                method: "POST"
            )
        }
        if recoverScopes {
            try await withScopeRecovery { try await perform() }
        } else {
            try await perform()
        }
    }

    /// Un seul retry après réautorisation — jamais de boucle 403.
    private func withScopeRecovery<T>(_ op: () async throws -> T) async throws -> T {
        do {
            return try await op()
        } catch let error as DirectGmailError where error.isInsufficientScopes {
            do {
                try await oauth.authorize(forceConsent: true)
            } catch {
                throw DirectGmailError.insufficientScopes
            }
            return try await op()
        } catch let error as GmailRfc822.EncodeError {
            throw DirectGmailError.invalidArgument(error.localizedDescription)
        }
    }

    // MARK: - HTTP (401 → refresh once)

    private func getMessageMetadata(id: String) async throws -> DirectMailMessage {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("messages").appendingPathComponent(id),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
        ]
        let obj = try await jsonObject(url: components.url!)
        return Self.mapMessage(obj)
    }

    private func jsonObject(
        url: URL,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        didRefresh: Bool = false
    ) async throws -> [String: Any] {
        let token = try await oauth.validAccessToken()
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw DirectGmailError.http(-1, error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw DirectGmailError.decode
        }
        if http.statusCode == 401, !didRefresh {
            _ = try await oauth.refreshAccessToken()
            return try await jsonObject(url: url, method: method, jsonBody: jsonBody, didRefresh: true)
        }
        if http.statusCode == 401 {
            throw DirectGmailError.unauthorized
        }
        if http.statusCode == 403 {
            let message = Self.extractGoogleErrorMessage(data) ?? ""
            if DirectGmailError.looksLikeInsufficientScopes(message) {
                throw DirectGmailError.insufficientScopes
            }
            throw DirectGmailError.http(http.statusCode, message)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractGoogleErrorMessage(data) ?? ""
            throw DirectGmailError.http(http.statusCode, message)
        }
        if data.isEmpty {
            return [:]
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DirectGmailError.decode
        }
        return obj
    }

    // MARK: - Mapping

    private static func mapMessage(_ obj: [String: Any]) -> DirectMailMessage {
        let id = (obj["id"] as? String) ?? ""
        let threadId = obj["threadId"] as? String
        let snippet = obj["snippet"] as? String
        let labelIds = obj["labelIds"] as? [String] ?? []
        let payload = obj["payload"] as? [String: Any]
        let headers = payload?["headers"] as? [[String: Any]] ?? []
        func header(_ name: String) -> String? {
            headers.first {
                ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame
            }?["value"] as? String
        }
        let bodyPlain: String? = {
            if let payload {
                return extractPlainText(from: payload)
            }
            return nil
        }()
        let bodyHtml: String? = {
            if let payload {
                return extractHTML(from: payload)
            }
            return nil
        }()
        let internalDate: String? = {
            if let ms = obj["internalDate"] as? String, let v = Double(ms) {
                return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: v / 1000))
            }
            if let ms = obj["internalDate"] as? Double {
                return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: ms / 1000))
            }
            return header("Date")
        }()
        return DirectMailMessage(
            id: id,
            threadId: threadId,
            subject: header("Subject"),
            from: header("From"),
            snippet: snippet,
            date: internalDate,
            bodyPlain: bodyPlain,
            bodyHtml: bodyHtml,
            labelIds: labelIds,
            rfc822MessageId: header("Message-ID") ?? header("Message-Id"),
            rfc822References: header("References")
        )
    }

    private static func extractPlainText(from payload: [String: Any]) -> String? {
        let mime = (payload["mimeType"] as? String)?.lowercased() ?? ""
        if mime == "text/plain", let data = payload["body"] as? [String: Any],
           let raw = data["data"] as? String {
            return decodeBase64URL(raw)
        }
        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                if let text = extractPlainText(from: part) { return text }
            }
            // multipart/alternative : chercher récursivement dans nested parts
            for part in parts {
                if let nested = part["parts"] as? [[String: Any]] {
                    for child in nested {
                        if let text = extractPlainText(from: child) { return text }
                    }
                }
            }
        }
        // Fallback : text/html strip grossier
        if mime == "text/html", let html = extractHTML(from: payload) {
            return stripHTML(html)
        }
        return nil
    }

    /// Extrait le corps HTML brut (pour `MailBodyReader`), sans le stripper.
    private static func extractHTML(from payload: [String: Any]) -> String? {
        let mime = (payload["mimeType"] as? String)?.lowercased() ?? ""
        if mime == "text/html", let data = payload["body"] as? [String: Any],
           let raw = data["data"] as? String {
            return decodeBase64URL(raw)
        }
        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                if let html = extractHTML(from: part) { return html }
            }
            for part in parts {
                if let nested = part["parts"] as? [[String: Any]] {
                    for child in nested {
                        if let html = extractHTML(from: child) { return html }
                    }
                }
            }
        }
        return nil
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        var s = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - s.count % 4
        if pad < 4 { s += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: s), !data.isEmpty else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // Certains corps Gmail arrivent en Latin-1 / Windows-1252.
        return String(data: data, encoding: .isoLatin1)
    }

    private static func stripHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractGoogleErrorMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }
}
