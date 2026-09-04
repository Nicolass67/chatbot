import Foundation

/// Demande d’ouverture d’un chat contextuel (Mail / Files), persisté par clé.
struct ChatContextRequest: Equatable, Sendable {
    enum Kind: String, Sendable {
        case mail
        case file
    }

    var kind: Kind
    /// Clé stable (threadId mail, fileId fichier, ou global).
    var key: String
    var title: String
    var prefill: String
    /// Si true, préremplit même une conversation déjà existante.
    var forcePrefill: Bool = true

    var storageKey: String { "ctxchat.\(kind.rawValue).\(key)" }
}

/// Compat : délègue à ConversationSessionStore (scopes Mail/Files).
@MainActor
enum ContextualChatStore {
    static func conversationId(for request: ChatContextRequest) -> String? {
        let scope: ConversationScope = request.kind == .mail ? .mail : .files
        return ConversationSessionStore.conversationId(
            scope: scope,
            contextKey: request.key
        )
    }

    static func save(conversationId: String, for request: ChatContextRequest) {
        let scope: ConversationScope = request.kind == .mail ? .mail : .files
        ConversationSessionStore.save(
            conversationId: conversationId,
            scope: scope,
            contextKey: request.key
        )
    }

    static func clear(for request: ChatContextRequest) {
        let scope: ConversationScope = request.kind == .mail ? .mail : .files
        ConversationSessionStore.clear(scope: scope, contextKey: request.key)
    }
}
