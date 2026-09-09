import Foundation

/// Conversation stockée uniquement sur l’appareil (pas de sync SQLite PC).
struct LocalConversation: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var scope: ConversationScope
    var createdAt: Date
    var updatedAt: Date
    var chatMode: String?

    init(
        id: String = UUID().uuidString,
        title: String = "Nouvelle conversation",
        scope: ConversationScope = .general,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        chatMode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.scope = scope
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.chatMode = chatMode
    }
}

struct LocalStoredAttachment: Codable, Hashable, Sendable {
    var id: String
    var filename: String?
    var mimeType: String?
    var sizeBytes: Int?
    var type: String?
    /// Nom de fichier dans Documents/LocalAttachments — pas un chemin brut.
    var localRelativePath: String?
}

struct LocalMessage: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    var id: String
    var conversationId: String
    var role: Role
    var content: String
    var createdAt: Date
    var attachments: [LocalStoredAttachment]?

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: Role,
        content: String,
        createdAt: Date = Date(),
        attachments: [LocalStoredAttachment]? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
    }
}

/// Persistance locale Application Support/LocalChat/ — hors SQLite PC.
@MainActor
final class LocalChatStore: ObservableObject {
    static let shared = LocalChatStore()

    @Published private(set) var conversations: [LocalConversation] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var rootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LocalChat", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var conversationsURL: URL {
        rootDirectory.appendingPathComponent("conversations.json")
    }

    private func messagesURL(for conversationId: String) -> URL {
        rootDirectory.appendingPathComponent("\(conversationId).messages.json")
    }

    init() {
        reloadConversations()
    }

    func reloadConversations() {
        guard let data = try? Data(contentsOf: conversationsURL),
              let decoded = try? decoder.decode([LocalConversation].self, from: data)
        else {
            conversations = []
            return
        }
        conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Conversations CRUD

    func conversations(scope: ConversationScope) -> [LocalConversation] {
        conversations.filter { $0.scope == scope }
    }

    @discardableResult
    func createConversation(
        title: String = "Nouvelle conversation",
        scope: ConversationScope = .general
    ) -> LocalConversation {
        let conversation = LocalConversation(title: title, scope: scope)
        conversations.insert(conversation, at: 0)
        persistConversations()
        persistMessages([], for: conversation.id)
        return conversation
    }

    func updateConversation(_ conversation: LocalConversation) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        var next = conversation
        next.updatedAt = Date()
        conversations[idx] = next
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persistConversations()
    }

    func renameConversation(id: String, title: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].title = title
        conversations[idx].updatedAt = Date()
        persistConversations()
    }

    func deleteConversation(id: String) {
        conversations.removeAll { $0.id == id }
        persistConversations()
        try? fileManager.removeItem(at: messagesURL(for: id))
    }

    // MARK: - Messages CRUD

    func messages(for conversationId: String) -> [LocalMessage] {
        let url = messagesURL(for: conversationId)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode([LocalMessage].self, from: data)
        else {
            return []
        }
        return decoded.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func appendMessage(
        conversationId: String,
        role: LocalMessage.Role,
        content: String,
        id: String? = nil,
        attachments: [LocalStoredAttachment]? = nil
    ) -> LocalMessage? {
        guard conversations.contains(where: { $0.id == conversationId }) else { return nil }
        var list = messages(for: conversationId)
        let messageId = {
            let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? UUID().uuidString : trimmed
        }()
        if list.contains(where: { $0.id == messageId }) {
            return list.first { $0.id == messageId }
        }
        let message = LocalMessage(
            id: messageId,
            conversationId: conversationId,
            role: role,
            content: content,
            attachments: attachments
        )
        list.append(message)
        persistMessages(list, for: conversationId)
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].updatedAt = Date()
            if conversations[idx].title == "Nouvelle conversation", role == .user {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    conversations[idx].title = String(trimmed.prefix(48))
                } else if let name = attachments?.first?.filename, !name.isEmpty {
                    conversations[idx].title = String((name as NSString).lastPathComponent.prefix(48))
                }
            }
            conversations.sort { $0.updatedAt > $1.updatedAt }
            persistConversations()
        }
        return message
    }

    func setChatMode(_ mode: String, conversationId: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].chatMode = mode
        conversations[idx].updatedAt = Date()
        persistConversations()
    }

    func replaceMessages(_ messages: [LocalMessage], for conversationId: String) {
        persistMessages(messages, for: conversationId)
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].updatedAt = Date()
            persistConversations()
        }
    }

    func deleteMessage(id: String, conversationId: String) {
        var list = messages(for: conversationId)
        list.removeAll { $0.id == id }
        persistMessages(list, for: conversationId)
    }

    // MARK: - Persistence

    private func persistConversations() {
        do {
            let data = try encoder.encode(conversations)
            try data.write(to: conversationsURL, options: [.atomic])
        } catch {
            // Persistance best-effort.
        }
    }

    private func persistMessages(_ messages: [LocalMessage], for conversationId: String) {
        do {
            let data = try encoder.encode(messages)
            try data.write(to: messagesURL(for: conversationId), options: [.atomic])
        } catch {
            // Persistance best-effort.
        }
    }
}

extension LocalConversation {
    func asConversationDTO() -> ConversationDTO {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ConversationDTO(
            id: id,
            title: title,
            updatedAt: formatter.string(from: updatedAt),
            chatMode: chatMode,
            reasoningEffort: nil,
            scope: scope.rawValue,
            contextKey: nil,
            contextLabel: nil
        )
    }
}

extension LocalMessage {
    func asMessageDTO() -> MessageDTO {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let mapped: [MessageAttachmentDTO]? = attachments?.map {
            MessageAttachmentDTO(
                id: $0.id,
                filename: $0.filename,
                mimeType: $0.mimeType,
                sizeBytes: $0.sizeBytes,
                type: $0.type
            )
        }
        return MessageDTO(
            id: id,
            role: role.rawValue,
            content: content,
            createdAt: formatter.string(from: createdAt),
            attachments: mapped
        )
    }
}
