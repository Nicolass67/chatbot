import Foundation

/// Cache process des listes d’onglets — survive un remount TabView sans refetch réseau.
@MainActor
enum TabMemoryCache {
    struct MailSnapshot {
        var messages: [MailMessageSummary]
        var category: String
        var unreadOnly: Bool
        var sortRaw: String
        var search: String
        var nextPageToken: String?
        var pageTokenStack: [String?]
        var resultSizeEstimate: Int?
        var sortedWindow: [MailMessageSummary]
        var localPageIndex: Int
        var windowExhausted: Bool
    }

    static var mail: MailSnapshot?
    static var fileRoots: [FileRootDTO]?
    static var chatMessagesByConversation: [String: [MessageDTO]] = [:]

    static func saveChat(conversationId: String, messages: [MessageDTO]) {
        guard !messages.isEmpty else { return }
        chatMessagesByConversation[conversationId] = messages
    }

    static func chat(conversationId: String) -> [MessageDTO]? {
        chatMessagesByConversation[conversationId]
    }
}
