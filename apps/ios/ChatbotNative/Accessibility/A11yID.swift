import Foundation

/// Identifiants d’accessibilité stables pour XCUITest / automation agent.
/// Convention : `domain.element` (chat.*, mail.*, files.*, assistant.*, agent.*).
enum A11yID {
    enum Navigation {
        static let tabBar = "navigation.tabBar"
        static let tabChat = "navigation.tab.chat"
        static let tabMail = "navigation.tab.mail"
        static let tabFiles = "navigation.tab.files"
    }

    enum Auth {
        static let login = "auth.login"
        static let unlock = "auth.unlock"
        static let lockScreen = "auth.lockScreen"
    }

    enum Chat {
        static let root = "chat.root"
        static let history = "chat.history"
        static let newConversation = "chat.new"
        static let settings = "chat.settings"
        static let composer = "chat.composer"
        static let composerField = "chat.composer.field"
        static let send = "chat.send"
        static let stop = "chat.stop"
        static let keyboardDismiss = "chat.keyboard.dismiss"
        static let attachImage = "chat.attach.image"
        static let attachFile = "chat.attach.file"
        static let options = "chat.overflow"
        static let overflow = "chat.overflow"
        static let thinking = "chat.thinking"
        static let messageList = "chat.messages"
    }

    enum Mail {
        static let root = "mail.root"
        static let search = "mail.search"
        static let settings = "mail.settings"
        static let assistant = "mail.assistant"
        static let message = "mail.message"
        static let rowPrefix = "mail.row."
        static let detail = "mail.detail"
        static let reply = "mail.reply"
        static let summary = "mail.summary"
        static let summaryAction = "mail.summary.action"
        static let bodyPlain = "mail.body.plain"
        static let bodyHtml = "mail.body.html"
        static let bodyShowHtml = "mail.body.showHtml"
        static let bodyShowPlain = "mail.body.showPlain"
        static let draft = "mail.draft"
        static let draftEditor = "mail.draft.editor"
        static let draftEdit = "mail.draft.edit"
        static let draftRetry = "mail.draft.retry"
        static let send = "mail.send"
        static let history = "mail.history"
        static let overflow = "mail.overflow"
    }

    enum Files {
        static let root = "files.root"
        static let search = "files.search"
        static let settings = "files.settings"
        static let assistant = "files.assistant"
        static let folder = "files.folder"
        static let file = "files.file"
        static let folderPrefix = "files.folder."
        static let filePrefix = "files.file."
        static let preview = "files.preview"
        static let back = "files.back"
        static let breadcrumb = "files.breadcrumb"
        static let reindex = "files.reindex"
    }

    enum Assistant {
        static let open = "assistant.open"
        static let root = "assistant.root"
        static let sheet = "assistant.root"
        static let close = "assistant.close"
        static let history = "assistant.history"
        static let contextChip = "assistant.context"
        static let composer = "assistant.composer"
        static let send = "assistant.send"
        static let stop = "assistant.stop"
        static let scopeMail = "assistant.scope.mail"
        static let scopeFiles = "assistant.scope.files"
        static let scopeGeneral = "assistant.scope.general"
        static let handoffMail = "assistant.handoff.mail"
        static let handoffFiles = "assistant.handoff.files"
    }

    enum Agent {
        static let root = "agent.root"
        static let timeline = "agent.timeline"
        static let stop = "agent.stop"
        static let step = "agent.step"
        /// Legacy alias used by older tests / chat chrome.
        static let banner = "chat.agent"
    }

    enum Settings {
        static let root = "settings.root"
        static let close = "settings.close"
        static let appearance = "settings.appearance"
        static let haptics = "settings.haptics"
        static let shutdownPc = "settings.shutdownPc"
        static let systemStatus = "settings.systemStatus"
    }
}
