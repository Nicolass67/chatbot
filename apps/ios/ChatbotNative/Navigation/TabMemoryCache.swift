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

    struct FileFolderSnapshot {
        var entries: [FileEntryDTO]
        var nextCursor: String?
    }

    static var mail: MailSnapshot?
    static var fileRoots: [FileRootDTO]?
    /// Contenu des dossiers Files (clé `rootId|path`).
    static var fileFolders: [String: FileFolderSnapshot] = [:]
    /// Pile de navigation Files (dossiers / fichiers) — conserve l’emplacement entre onglets.
    static var filesPath: [FilesDestination]?
    static var chatMessagesByConversation: [String: [MessageDTO]] = [:]

    static func folderKey(rootId: String, path: String) -> String {
        "\(rootId)|\(path)"
    }

    static func saveFolder(rootId: String, path: String, entries: [FileEntryDTO], nextCursor: String?) {
        fileFolders[folderKey(rootId: rootId, path: path)] = .init(
            entries: entries,
            nextCursor: nextCursor
        )
    }

    static func folder(rootId: String, path: String) -> FileFolderSnapshot? {
        fileFolders[folderKey(rootId: rootId, path: path)]
    }

    static func invalidateFolder(rootId: String, path: String) {
        fileFolders.removeValue(forKey: folderKey(rootId: rootId, path: path))
    }

    static func saveChat(conversationId: String, messages: [MessageDTO]) {
        guard !messages.isEmpty else { return }
        chatMessagesByConversation[conversationId] = messages
    }

    static func chat(conversationId: String) -> [MessageDTO]? {
        chatMessagesByConversation[conversationId]
    }
}
