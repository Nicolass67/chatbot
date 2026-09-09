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
    var messageId: String?
    var query: String?
    var label: String?
    var subject: String?
    var sender: String?

    init(
        threadId: String? = nil,
        messageId: String? = nil,
        query: String? = nil,
        label: String? = nil,
        subject: String? = nil,
        sender: String? = nil
    ) {
        self.threadId = threadId
        self.messageId = messageId
        self.query = query
        self.label = label
        self.subject = subject
        self.sender = sender
    }

    init(_ reference: MailHandoffDTO) {
        self.init(
            threadId: reference.threadId,
            messageId: reference.messageId,
            query: reference.query,
            label: reference.label,
            subject: reference.subject,
            sender: reference.sender
        )
    }
}

/// Handoff Files → Assistant Mail (PJ préchargée).
struct MailAttachHandoff: Equatable, Sendable, Identifiable {
    var id: String { fileId }
    let fileId: String
    let filename: String
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
    /// Incrémenté pour focaliser le composer (Nouveau chat). Survit au remount de ChatScreen.
    var composerFocusGeneration: UInt64 = 0
    /// Legacy soft-context (évité pour Mail/Files Assistant — préférer sheets in-place).
    var chatContextRequest: ChatContextRequest?
    var showSettings = false

    /// Mail Assistant sheet (in-place, pas de switch vers Chat).
    var presentMailAssistant = false
    var mailAssistantContext: MailAssistantContext = .global
    /// Fichiers Files → PJ assistant Mail (consommés par ChatScreen scope mail).
    var mailAttachHandoffs: [MailAttachHandoff] = []
    /// Sources Files→Mail persistantes : survivent à « Nouveau chat » jusqu’à envoi / retrait.
    var mailStickyAttachSources: [MailAttachHandoff] = []
    var mailComposerPrefill: String?
    /// Consigne « écris un mail… » à consommer par Mail Assistant (une seule fois).
    var pendingMailComposeInstruction: String?
    /// Brouillon déjà généré à poser dans Mail Assistant (évite une 2e génération).
    var pendingMailDraft: MailSendConfirmation?

    /// Files Assistant sheet (in-place).
    var presentFilesAssistant = false
    var filesAssistantContext: FilesAssistantContext = .global
    /// Incrémente pour forcer la fermeture des sheets Assistant locales (Mail/Files).
    var assistantDismissToken: Int = 0

    /// Intents QA / deep links — uniquement si session authentifiée (pas de bypass auth).
    var qaIntent: QaNavIntent?

    func openMail(threadId: String? = nil, query: String? = nil, label: String? = nil) {
        openMail(
            MailHandoffDTO(intent: "open", query: query, threadId: threadId, label: label)
        )
    }

    func openMail(_ reference: MailHandoffDTO) {
        dismissAssistantSheets()
        mailDeepLink = MailDeepLink(reference)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            selectedTab = .mail
        }
    }

    func openFiles(rootId: String? = nil, query: String? = nil) {
        filesDeepLink = FilesDeepLink(rootId: rootId, query: query, intent: .search)
        selectedTab = .files
    }

    /// Ferme toute sheet Assistant Mail/Files présentée localement.
    func dismissAssistantSheets() {
        presentMailAssistant = false
        presentFilesAssistant = false
        assistantDismissToken &+= 1
    }

    /// Ouvre le preview du fichier (ferme l’assistant si besoin côté appelant).
    func openFilePreview(
        fileId: String,
        fileName: String,
        rootId: String?,
        folderPath: String?
    ) {
        dismissAssistantSheets()
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
        dismissAssistantSheets()
        // Poser le deep-link puis switcher d’onglet au tick suivant :
        // évite les courses sheet Mail/Files encore en fermeture.
        filesDeepLink = FilesDeepLink(
            rootId: rootId,
            fileName: title,
            folderPath: folderPath,
            intent: .folder
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            selectedTab = .files
        }
    }

    /// Déclenche téléchargement + navigation preview (share depuis FilePreview).
    func downloadFile(
        fileId: String,
        fileName: String,
        rootId: String?,
        folderPath: String?
    ) {
        dismissAssistantSheets()
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

    func openMailAssistantForCompose(instruction: String) {
        pendingMailComposeInstruction = instruction
        pendingMailDraft = nil
        openMailAssistant(.global)
    }

    func presentGeneratedMailDraft(_ confirmation: MailSendConfirmation, context: MailAssistantContext) {
        pendingMailDraft = confirmation
        pendingMailComposeInstruction = nil
        openMailAssistant(context)
    }

    /// Ouvre l’assistant Mail avec des fichiers Files déjà prêts à joindre.
    /// Composer : PJ seules — aucun texte prérempli (sauf `prefill` explicite).
    func shareFilesToMail(
        files: [(fileId: String, filename: String)],
        prefill: String? = nil
    ) {
        guard !files.isEmpty else { return }
        let handoffs = files.map {
            MailAttachHandoff(fileId: $0.fileId, filename: $0.filename)
        }
        for handoff in handoffs {
            if !mailStickyAttachSources.contains(where: { $0.fileId == handoff.fileId }) {
                mailStickyAttachSources.append(handoff)
            }
        }
        mailAttachHandoffs = handoffs
        mailComposerPrefill = prefill
        mailAssistantContext = .global
        presentMailAssistant = true
        presentFilesAssistant = false
        assistantDismissToken &+= 1
        selectedTab = .mail
    }

    func clearMailStickyAttachments() {
        mailStickyAttachSources = []
        mailAttachHandoffs = []
    }

    /// Files Assistant sheet (in-place, comme Mail — pas de redirect Chat).
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
