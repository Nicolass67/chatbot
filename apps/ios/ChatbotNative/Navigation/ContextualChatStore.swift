import Foundation

/// Demande d’ouverture d’un chat contextuel (Mail / Files), persisté par clé.
struct ChatContextRequest: Equatable, Sendable {
    enum Kind: String, Sendable {
        case mail
        case file
    }

    var kind: Kind
    /// Clé stable (threadId mail, fileId fichier).
    var key: String
    var title: String
    var prefill: String
    /// Si true, préremplit même une conversation déjà existante.
    var forcePrefill: Bool = true

    var storageKey: String { "ctxchat.\(kind.rawValue).\(key)" }
}

enum ContextualChatStore {
    static func conversationId(for request: ChatContextRequest) -> String? {
        UserDefaults.standard.string(forKey: request.storageKey)
    }

    static func save(conversationId: String, for request: ChatContextRequest) {
        UserDefaults.standard.set(conversationId, forKey: request.storageKey)
    }

    static func clear(for request: ChatContextRequest) {
        UserDefaults.standard.removeObject(forKey: request.storageKey)
    }
}
