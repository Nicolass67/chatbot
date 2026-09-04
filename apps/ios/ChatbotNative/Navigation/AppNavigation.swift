import Foundation

enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case chat = 0
    case mail = 1
    case files = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .mail: return "Mail"
        case .files: return "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .mail: return "envelope.fill"
        case .files: return "folder.fill"
        }
    }
}

struct MailDeepLink: Equatable, Sendable {
    var threadId: String?
    var query: String?
    var label: String?
}

struct FilesDeepLink: Equatable, Sendable {
    var rootId: String?
    var query: String?
}

struct MemoryDeepLink: Equatable, Sendable {
    var memoryId: String?
}

/// Navigation transversale (handoffs chat → Mail / Files / Memory / Settings).
@Observable
@MainActor
final class AppNavigation {
    var selectedTab: AppTab = .chat
    var mailDeepLink: MailDeepLink?
    var filesDeepLink: FilesDeepLink?
    var memoryDeepLink: MemoryDeepLink?
    var openConversationId: String?
    /// Prefill composer après handoff Files/Mail → Chat général seulement.
    var chatComposerPrefill: String?
    /// Legacy soft-context (évité pour Mail/Files Assistant — préférer sheets in-place).
    var chatContextRequest: ChatContextRequest?
    var showSettings = false

    /// Mail Assistant sheet (in-place, pas de switch vers Chat).
    var presentMailAssistant = false
    var mailAssistantContext: MailAssistantContext = .global

    /// Files Assistant sheet (in-place).
    var presentFilesAssistant = false
    var filesAssistantContext: FilesAssistantContext = .global

    /// Intents QA / deep links — uniquement si session authentifiée (pas de bypass auth).
    var qaIntent: QaNavIntent?

    func openMail(threadId: String? = nil, query: String? = nil, label: String? = nil) {
        mailDeepLink = MailDeepLink(threadId: threadId, query: query, label: label)
        selectedTab = .mail
    }

    func openFiles(rootId: String? = nil, query: String? = nil) {
        filesDeepLink = FilesDeepLink(rootId: rootId, query: query)
        selectedTab = .files
    }

    func openMemory(memoryId: String? = nil) {
        memoryDeepLink = MemoryDeepLink(memoryId: memoryId)
        showSettings = true
    }

    func openSettings() {
        showSettings = true
    }

    func openChat(conversationId: String) {
        openConversationId = conversationId
        selectedTab = .chat
    }

    func askAssistant(prefill: String) {
        chatComposerPrefill = prefill
        selectedTab = .chat
    }

    func openMailAssistant(_ context: MailAssistantContext = .global) {
        mailAssistantContext = context
        presentMailAssistant = true
        selectedTab = .mail
    }

    func openFilesAssistant(_ context: FilesAssistantContext = .global) {
        filesAssistantContext = context
        presentFilesAssistant = true
        selectedTab = .files
    }

    /// Ancien API — redirige vers Assistant **dans** Mail (plus vers Chat général).
    func askAboutMail(threadId: String, subject: String) {
        openMailAssistant(.thread(threadId: threadId, subject: subject, from: nil))
    }

    func askAboutFile(fileId: String, name: String) {
        openFilesAssistant(.file(fileId: fileId, name: name, rootId: "", path: ""))
    }

    func applyQaIntent(_ intent: QaNavIntent) {
        qaIntent = intent
        switch intent {
        case .chat, .composer, .agent, .thinking:
            selectedTab = .chat
            if intent == .chat || intent == .composer {
                openConversationId = "__new__"
            }
        case .mail, .mailDetail:
            selectedTab = .mail
        case .mailAssistant:
            openMailAssistant(.global)
        case .files, .filesDocuments, .filesNested, .filesFile:
            selectedTab = .files
        case .filesAssistant:
            openFilesAssistant(.global)
        }
    }
}

/// Deep-link intents for QA only — consumed by Mail/Files/Chat when authenticated.
enum QaNavIntent: String, Equatable, Sendable {
    case chat
    case composer
    case agent
    case thinking
    case mail
    case mailDetail
    case mailAssistant
    case files
    case filesDocuments
    case filesNested
    case filesFile
    case filesAssistant
}
