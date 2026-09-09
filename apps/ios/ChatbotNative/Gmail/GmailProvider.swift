import Foundation

/// Abstraction Gmail : mode distant (PC / APIClient) vs direct (iPhone → Gmail API).
protocol GmailServing: AnyObject {
    var isConnected: Bool { get async }
    var accountEmail: String? { get async }

    func listMessages(
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> DirectMailListPage

    func getMessage(id: String) async throws -> DirectMailMessage
    func getThread(id: String) async throws -> DirectMailThread

    func createDraft(
        to: String,
        subject: String,
        body: String,
        threadId: String?
    ) async throws -> DirectMailDraft

    /// Envoi d’un brouillon — **uniquement** après confirmation UI.
    func sendDraft(id: String) async throws

    /// Envoi direct — **uniquement** après confirmation UI.
    func sendMessage(
        to: String,
        subject: String,
        body: String,
        threadId: String?
    ) async throws
}

// MARK: - Remote (PC)

/// Façade mince sur `APIClient` (OAuth + Gmail restent côté serveur / SQLite PC).
final class RemoteGmailProvider: GmailServing, @unchecked Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    var isConnected: Bool {
        get async {
            do {
                let accounts = try await client.oauthAccounts()
                return accounts.configured && !accounts.emails.isEmpty
            } catch {
                return false
            }
        }
    }

    var accountEmail: String? {
        get async {
            do {
                let accounts = try await client.oauthAccounts()
                return accounts.emails.first
            } catch {
                return nil
            }
        }
    }

    func listMessages(
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> DirectMailListPage {
        let page = try await client.listMailMessages(
            maxResults: maxResults,
            category: nil,
            query: query,
            pageToken: pageToken
        )
        let mapped = page.messages.map { Self.mapSummary($0) }
        return DirectMailListPage(
            messages: mapped,
            nextPageToken: page.nextPageToken,
            resultSizeEstimate: page.resultSizeEstimate
        )
    }

    func getMessage(id: String) async throws -> DirectMailMessage {
        // Pas d’endpoint message isolé riche côté client — on lit le fil et on cherche l’id.
        // Fallback : résumé via thread si threadId == id (souvent le cas Gmail).
        let thread = try await client.fetchMailThread(id: id)
        if let hit = thread.messages?.first(where: { $0.id == id }) {
            return Self.mapThreadMessage(hit, fallbackThreadId: thread.id)
        }
        if let first = thread.messages?.first {
            return Self.mapThreadMessage(first, fallbackThreadId: thread.id)
        }
        return DirectMailMessage(
            id: id,
            threadId: thread.id,
            subject: thread.subject,
            from: nil,
            snippet: nil,
            date: nil,
            bodyPlain: nil,
            labelIds: []
        )
    }

    func getThread(id: String) async throws -> DirectMailThread {
        let thread = try await client.fetchMailThread(id: id)
        let messages = (thread.messages ?? []).map {
            Self.mapThreadMessage($0, fallbackThreadId: thread.id)
        }
        let last = messages.last
        let first = messages.first
        return DirectMailThread(
            id: thread.id,
            threadId: thread.id,
            subject: thread.subject ?? last?.subject ?? first?.subject,
            from: last?.from ?? first?.from,
            snippet: last?.snippet ?? first?.snippet,
            date: last?.date ?? first?.date,
            bodyPlain: messages.compactMap(\.bodyPlain).joined(separator: "\n\n---\n\n"),
            labelIds: last?.labelIds ?? [],
            messages: messages
        )
    }

    func createDraft(
        to: String,
        subject: String,
        body: String,
        threadId: String?
    ) async throws -> DirectMailDraft {
        // Le chemin remote utilise les drafts email serveur ; création générique non exposée
        // ici comme Gmail drafts.create. On renvoie une erreur claire.
        throw DirectGmailError.invalidArgument(
            "Création de brouillon direct indisponible en mode distant — utilise le flux drafts de l’app."
        )
    }

    func sendDraft(id: String) async throws {
        throw DirectGmailError.invalidArgument(
            "Envoi de brouillon Gmail API indisponible en mode distant — utilise la confirmation d’envoi existante."
        )
    }

    func sendMessage(
        to: String,
        subject: String,
        body: String,
        threadId: String?
    ) async throws {
        throw DirectGmailError.invalidArgument(
            "Envoi Gmail API direct indisponible en mode distant — utilise la confirmation d’envoi existante."
        )
    }

    // MARK: Mapping

    private static func mapSummary(_ m: MailMessageSummary) -> DirectMailMessage {
        let from: String? = {
            guard let addr = m.from else { return nil }
            if let name = addr.name, !name.isEmpty {
                return "\(name) <\(addr.email)>"
            }
            return addr.email
        }()
        return DirectMailMessage(
            id: m.id,
            threadId: m.threadId,
            subject: m.subject,
            from: from,
            snippet: m.snippet,
            date: m.date,
            bodyPlain: nil,
            labelIds: (m.isUnread == true) ? ["UNREAD"] : []
        )
    }

    private static func mapThreadMessage(
        _ m: MailThreadMessage,
        fallbackThreadId: String
    ) -> DirectMailMessage {
        let from: String? = {
            guard let addr = m.from else { return nil }
            if let name = addr.name, !name.isEmpty {
                return "\(name) <\(addr.email)>"
            }
            return addr.email
        }()
        return DirectMailMessage(
            id: m.id,
            threadId: m.threadId ?? fallbackThreadId,
            subject: m.subject,
            from: from,
            snippet: m.snippet,
            date: m.date,
            bodyPlain: m.bodyText,
            labelIds: (m.isUnread == true) ? ["UNREAD"] : []
        )
    }
}

// MARK: - Direct (iPhone)

/// Gmail sans PC : OAuth local + `DirectGmailClient`.
@MainActor
final class DirectGmailProvider: GmailServing {
    private let oauth: GmailOAuthSession
    private let client: DirectGmailClient

    init(
        oauth: GmailOAuthSession = .shared,
        client: DirectGmailClient? = nil
    ) {
        self.oauth = oauth
        self.client = client ?? DirectGmailClient(oauth: oauth)
    }

    var isConnected: Bool {
        get async { oauth.isConnected }
    }

    var accountEmail: String? {
        get async { oauth.email }
    }

    func listMessages(
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> DirectMailListPage {
        try await ensureConnected()
        return try await client.listMessages(
            query: query,
            pageToken: pageToken,
            maxResults: maxResults
        )
    }

    func getMessage(id: String) async throws -> DirectMailMessage {
        try await ensureConnected()
        return try await client.getMessage(id: id)
    }

    func getThread(id: String) async throws -> DirectMailThread {
        try await ensureConnected()
        return try await client.getThread(id: id)
    }

    func createDraft(
        to: String,
        subject: String,
        body: String,
        threadId: String?
    ) async throws -> DirectMailDraft {
        try await ensureConnected()
        return try await client.createDraft(
            to: to,
            subject: subject,
            body: body,
            threadId: threadId
        )
    }

    func sendDraft(id: String) async throws {
        try await ensureConnected()
        try await client.sendDraft(id: id)
    }

    func sendMessage(
        to: String,
        subject: String,
        body: String,
        threadId: String?
    ) async throws {
        try await ensureConnected()
        try await client.sendMessage(
            to: to,
            subject: subject,
            body: body,
            threadId: threadId
        )
    }

    private func ensureConnected() async throws {
        guard oauth.isConnected else { throw DirectGmailError.notConnected }
    }
}
