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

/// Deep-link Files — preview fichier, dossier parent exact, ou recherche.
struct FilesDeepLink: Equatable, Sendable {
    enum Intent: String, Equatable, Sendable {
        case search
        case folder
        case preview
        case download
    }

    var rootId: String?
    var query: String?
    var fileId: String?
    var fileName: String?
    /// Chemin relatif du dossier parent (exact), "" = racine.
    var folderPath: String?
    var intent: Intent = .search
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
        filesDeepLink = FilesDeepLink(rootId: rootId, query: query, intent: .search)
        selectedTab = .files
    }

    /// Ouvre le preview du fichier (ferme l’assistant si besoin côté appelant).
    func openFilePreview(
        fileId: String,
        fileName: String,
        rootId: String?,
        folderPath: String?
    ) {
        presentMailAssistant = false
        presentFilesAssistant = false
        filesDeepLink = FilesDeepLink(
            rootId: rootId,
            fileId: fileId,
            fileName: fileName,
            folderPath: folderPath ?? "",
            intent: .preview
        )
        selectedTab = .files
    }

    /// Navigue vers le dossier parent exact du fichier.
    func openFileFolder(rootId: String?, folderPath: String, title: String? = nil) {
        presentMailAssistant = false
        presentFilesAssistant = false
        filesDeepLink = FilesDeepLink(
            rootId: rootId,
            fileName: title,
            folderPath: folderPath,
            intent: .folder
        )
        selectedTab = .files
    }

    /// Déclenche téléchargement + navigation preview (share depuis FilePreview).
    func downloadFile(
        fileId: String,
        fileName: String,
        rootId: String?,
        folderPath: String?
    ) {
        presentMailAssistant = false
        presentFilesAssistant = false
        filesDeepLink = FilesDeepLink(
            rootId: rootId,
            fileId: fileId,
            fileName: fileName,
            folderPath: folderPath ?? "",
            intent: .download
        )
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

enum FilesPathHelpers {
    /// Dossier parent d’un relativePath fichier (`a/b/c.pdf` → `a/b`, sinon `""`).
    static func parentFolder(of relativePath: String?) -> String {
        guard let relativePath, !relativePath.isEmpty else { return "" }
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard let idx = normalized.lastIndex(of: "/") else { return "" }
        return String(normalized[..<idx])
    }

    static func lastSegment(of path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.split(separator: "/").last.map(String.init) ?? path
    }
}
