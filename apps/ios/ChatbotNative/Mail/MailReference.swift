import Foundation

/// Identité stable d’un mail pour tile persistante + deep-link.
/// Alias sémantique de `MailHandoffDTO` (même DTO, pas un second modèle métier).
enum MailReference {
    static func make(
        messageId: String?,
        threadId: String?,
        subject: String?,
        sender: String?,
        date: String?,
        query: String? = nil,
        mailboxId: String? = nil
    ) -> MailHandoffDTO {
        MailHandoffDTO(
            intent: "open",
            reason: subject,
            query: query,
            threadId: threadId,
            messageId: messageId,
            mailboxId: mailboxId,
            label: nil,
            subject: subject,
            sender: sender,
            date: date
        )
    }

    /// Premier hit `mail_search` (`messageId=` / `threadId=` / De / Objet).
    static func first(fromToolText text: String) -> MailHandoffDTO? {
        let block = firstBlock(in: text) ?? text
        let messageId = capture(#"messageId=([A-Za-z0-9_-]+)"#, in: block)
        let threadId = capture(#"threadId=([A-Za-z0-9_-]+)"#, in: block)
        guard messageId != nil || threadId != nil else { return nil }
        return make(
            messageId: messageId,
            threadId: threadId ?? messageId,
            subject: header("Objet", in: block) ?? header("Subject", in: block),
            sender: header("De", in: block) ?? header("From", in: block),
            date: header("Date", in: block)
        )
    }

    private static func firstBlock(in text: String) -> String? {
        let parts = text.components(separatedBy: "\n\n")
        return parts.first { $0.contains("messageId=") || $0.contains("threadId=") }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func header(_ name: String, in text: String) -> String? {
        let pattern = #"^"# + NSRegularExpression.escapedPattern(for: name) + #"\s*:\s*(.+)$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "—" ? nil : value
    }
}

enum MailMutationResult: Equatable, Sendable {
    case success
    case failure(String)
    case cancelled
}

enum MailNavigationCoordinator {
    @MainActor
    static func open(_ reference: MailHandoffDTO, nav: AppNavigation) {
        nav.openMail(reference)
    }
}
