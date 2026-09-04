import Foundation

/// Données déterministes pour XCUITest Simulator. Jamais utilisées hors `UITestMode`.
enum UITestFixtures {
    // MARK: - Chat

    static let emptyConversation = ConversationDTO(
        id: "uitest-conv-empty",
        title: "Nouveau chat",
        updatedAt: "2099-01-01T12:00:00Z",
        chatMode: "chat",
        reasoningEffort: nil,
        scope: ConversationScope.general.rawValue,
        contextKey: nil,
        contextLabel: nil
    )

    static let sampleConversation = ConversationDTO(
        id: "uitest-conv-sample",
        title: "UITest conversation",
        updatedAt: "2099-01-01T11:00:00Z",
        chatMode: "chat",
        reasoningEffort: nil,
        scope: ConversationScope.general.rawValue,
        contextKey: nil,
        contextLabel: nil
    )

    static let mailScopedConversation = ConversationDTO(
        id: "uitest-conv-mail",
        title: "Assistant Mail",
        updatedAt: "2099-01-01T10:00:00Z",
        chatMode: "chat",
        reasoningEffort: nil,
        scope: ConversationScope.mail.rawValue,
        contextKey: "thread:uitest-thread-free",
        contextLabel: "Facture Free"
    )

    static let filesScopedConversation = ConversationDTO(
        id: "uitest-conv-files",
        title: "Assistant Files",
        updatedAt: "2099-01-01T09:00:00Z",
        chatMode: "chat",
        reasoningEffort: nil,
        scope: ConversationScope.files.rawValue,
        contextKey: "file:uitest-file-notes",
        contextLabel: "notes.txt"
    )

    static func conversations(scope: ConversationScope) -> [ConversationDTO] {
        switch scope {
        case .general: return [sampleConversation]
        case .mail: return [mailScopedConversation]
        case .files: return [filesScopedConversation]
        }
    }

    static func messages(conversationId: String) -> [MessageDTO] {
        if conversationId == sampleConversation.id {
            return [
                MessageDTO(
                    id: "uitest-msg-user",
                    role: "user",
                    content: "Bonjour UITest",
                    createdAt: "2099-01-01T11:00:00Z",
                    attachments: nil
                ),
                MessageDTO(
                    id: "uitest-msg-assistant",
                    role: "assistant",
                    content: "Réponse déterministe Simulator.",
                    createdAt: "2099-01-01T11:00:01Z",
                    attachments: nil
                ),
            ]
        }
        return []
    }

    // MARK: - Mail

    static let freeInvoice = MailMessageSummary(
        id: "uitest-mail-free",
        threadId: "uitest-thread-free",
        from: MailAddressDTO(email: "facturation@free.fr", name: "Free"),
        subject: "Votre facture Free du mois",
        snippet: "Montant TTC 29,99 € — téléchargez votre facture PDF.",
        date: "2099-01-02T08:15:00Z",
        isUnread: true,
        hasAttachments: true
    )

    static let htmlMail = MailMessageSummary(
        id: "uitest-mail-html",
        threadId: "uitest-thread-html",
        from: MailAddressDTO(email: "newsletter@example.com", name: "Example News"),
        subject: "Newsletter HTML",
        snippet: "Contenu riche avec liens et images.",
        date: "2099-01-02T07:00:00Z",
        isUnread: false,
        hasAttachments: false
    )

    static let plainMail = MailMessageSummary(
        id: "uitest-mail-plain",
        threadId: "uitest-thread-plain",
        from: MailAddressDTO(email: "alice@example.com", name: "Alice"),
        subject: "Texte brut (fallback)",
        snippet: "Corps texte uniquement, sans HTML.",
        date: "2099-01-01T18:00:00Z",
        isUnread: false,
        hasAttachments: false
    )

    static let draftMail = MailMessageSummary(
        id: "uitest-mail-draft",
        threadId: "uitest-thread-draft",
        from: MailAddressDTO(email: "me@example.com", name: "Moi"),
        subject: "Brouillon UITest",
        snippet: "Brouillon de réponse déterministe…",
        date: "2099-01-01T16:00:00Z",
        isUnread: false,
        hasAttachments: false
    )

    static func mailInbox(category: String?) -> [MailMessageSummary] {
        if category == "drafts" { return [draftMail] }
        return [freeInvoice, htmlMail, plainMail]
    }

    static func mailThread(id: String) -> MailThreadDTO {
        let summary: MailMessageSummary
        switch id {
        case freeInvoice.threadId, freeInvoice.id: summary = freeInvoice
        case htmlMail.threadId, htmlMail.id: summary = htmlMail
        case plainMail.threadId, plainMail.id: summary = plainMail
        default: summary = freeInvoice
        }
        let html: String?
        let text: String?
        if summary.id == htmlMail.id {
            // Fragment HTML (pas de document imbriqué) + styles sombres pour valider sanitize/contraste.
            html = """
            <h1 style="color:#000000">Newsletter HTML</h1>
            <p style="color:#222222">Contenu <b>HTML</b> UITest avec contraste forcé.</p>
            <p style="color:#333333">Ligne longue pour vérifier le wrapping : facturation, abonnement, renouvellement automatique.</p>
            <a href="https://example.com" style="color:#0000ee">Lien exemple</a>
            """
            text = "Newsletter HTML"
        } else if summary.id == plainMail.id {
            html = nil
            text = """
            Bonjour,

            Voici un long message texte (fallback) pour valider la lisibilité P1b sur plusieurs paragraphes.

            - Point un : rappel du contexte
            - Point deux : détails utiles
            - Point trois : prochaine étape

            Corps texte uniquement, sans HTML. Fixture Simulator.

            Cordialement,
            Alice
            """
        } else {
            html = """
            <html><body style="color:#1a1a1a;background:#fafafa">
            <p>Facture Free <b>29,99 €</b></p>
            <p>Téléchargez votre facture PDF en pièce jointe.</p>
            </body></html>
            """
            text = """
            Montant TTC 29,99 € — téléchargez votre facture PDF.

            Période : janvier 2099
            Référence : FREE-UI-TEST-001

            Merci de votre confiance.
            """
        }
        let attachments: [MailAttachmentDTO]? = summary.hasAttachments == true
            ? [MailAttachmentDTO(id: "uitest-att-pdf", filename: "facture-free.pdf", mimeType: "application/pdf", sizeBytes: 12_345)]
            : nil
        let msg = MailThreadMessage(
            id: summary.id,
            threadId: summary.threadId,
            from: summary.from,
            subject: summary.subject,
            date: summary.date,
            snippet: summary.snippet,
            bodyText: text,
            bodyHtml: html,
            isUnread: summary.isUnread,
            hasAttachments: summary.hasAttachments,
            attachments: attachments
        )
        return MailThreadDTO(id: summary.threadId ?? summary.id, subject: summary.subject, messages: [msg])
    }

    static let mailSummaryMarkdown = """
    ## Résumé
    - Facture Free du mois : **29,99 €**
    - Pièce jointe PDF disponible
    - Aucune action urgente
    """

    static let mailDraftBody = """
    Bonjour,

    Merci pour votre message. Voici une réponse de brouillon UITest.

    Cordialement
    """

    // MARK: - Files

    static let documentsRoot = FileRootDTO(
        id: "uitest-root-documents",
        label: "Documents",
        absolutePath: "/UITest/Documents",
        enabled: true
    )

    static let downloadsRoot = FileRootDTO(
        id: "uitest-root-downloads",
        label: "Downloads",
        absolutePath: "/UITest/Downloads",
        enabled: true
    )

    static var fileRoots: [FileRootDTO] { [documentsRoot, downloadsRoot] }

    static let nestedFolder = FileEntryDTO(
        fileId: nil,
        name: "Projets",
        relativePath: "Projets",
        isDirectory: true,
        sizeBytes: nil,
        indexed: false
    )

    static let notesFile = FileEntryDTO(
        fileId: "uitest-file-notes",
        name: "notes.txt",
        relativePath: "notes.txt",
        isDirectory: false,
        sizeBytes: 128,
        indexed: true
    )

    static let nestedNotes = FileEntryDTO(
        fileId: "uitest-file-nested-notes",
        name: "spec.md",
        relativePath: "Projets/spec.md",
        isDirectory: false,
        sizeBytes: 256,
        indexed: true
    )

    static func listFiles(rootId: String, path: String) -> FileListDTO {
        if rootId == documentsRoot.id {
            if path.isEmpty || path == "/" {
                return FileListDTO(fileId: nil, entries: [nestedFolder, notesFile], nextCursor: nil)
            }
            if path == "Projets" || path.hasPrefix("Projets") {
                return FileListDTO(fileId: nil, entries: [nestedNotes], nextCursor: nil)
            }
        }
        if rootId == downloadsRoot.id {
            return FileListDTO(
                fileId: nil,
                entries: [
                    FileEntryDTO(
                        fileId: "uitest-file-dl",
                        name: "invoice.pdf",
                        relativePath: "invoice.pdf",
                        isDirectory: false,
                        sizeBytes: 4096,
                        indexed: false
                    ),
                ],
                nextCursor: nil
            )
        }
        return FileListDTO(fileId: nil, entries: [], nextCursor: nil)
    }

    static func fileContent(fileId: String) -> FileContentDTO {
        FileContentDTO(
            kind: "text",
            text: "# UITest fixture\n\nContenu déterministe pour preview Simulator.",
            name: fileId == nestedNotes.fileId ? "spec.md" : "notes.txt",
            mime: "text/plain",
            truncated: false,
            binary: nil
        )
    }
}
