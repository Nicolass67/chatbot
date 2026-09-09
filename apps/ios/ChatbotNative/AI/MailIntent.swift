import Foundation

/// Contexte Mail commun (thread ouvert vs boîte). Pas de workflow PC/local séparé.
enum MailContextKind: Equatable, Sendable {
    case thread(threadId: String)
    case mailbox
    case searchResults
    case selectedMessage(id: String)
}

/// Intent déterministe — pas de second modèle. Un seul GGUF reste chargé.
enum MailUserIntent: Equatable, Sendable {
    case latest(count: Int)
    case unread(count: Int)
    case fromContact(String)
    case aboutTopic(String)
    case today
    case summarizeRecent(count: Int)
    case genericMailbox
    case threadSummary
    case threadReply
    case none

    var needsGmailSearch: Bool {
        switch self {
        case .none, .threadSummary, .threadReply: return false
        default: return true
        }
    }
}

enum MailIntentDetector {
    static func detect(_ raw: String, hasOpenThread: Bool) -> MailUserIntent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return hasOpenThread ? .none : .genericMailbox }
        let lower = text.lowercased()

        if hasOpenThread {
            if isReply(lower) { return .threadReply }
            if isSummarizeCurrent(lower) && !isMailboxWide(lower) { return .threadSummary }
        }

        if let n = latestCount(in: lower) { return .latest(count: n) }
        if isUnread(lower) && looksLikeMailQuestion(lower) { return .unread(count: 8) }
        if isToday(lower) && looksLikeMailQuestion(lower) { return .today }
        if isSummarizeRecent(lower) { return .summarizeRecent(count: recentCount(in: lower)) }
        if let contact = fromContact(in: text, lower: lower) { return .fromContact(contact) }
        if let topic = aboutTopic(in: text, lower: lower) { return .aboutTopic(topic) }
        if looksLikeMailQuestion(lower) || isMailboxWide(lower) {
            return .genericMailbox
        }
        return .none
    }

    /// Requête Gmail `q=` — jamais la phrase utilisateur brute.
    static func gmailQuery(for intent: MailUserIntent, userText: String) -> String {
        switch intent {
        case .latest, .genericMailbox, .summarizeRecent:
            return "in:inbox"
        case .unread:
            return "in:inbox is:unread"
        case .today:
            return "in:inbox newer_than:1d"
        case .fromContact(let name):
            let safe = sanitizeGmailToken(name)
            return "in:inbox from:\(safe)"
        case .aboutTopic(let topic):
            let safe = sanitizeGmailToken(topic)
            return "in:inbox (\(safe))"
        case .threadSummary, .threadReply, .none:
            return sanitizeGmailToken(userText)
        }
    }

    static func resultLimit(for intent: MailUserIntent, profile: LocalModelExecutionProfile) -> Int {
        let cap = max(1, profile.maxMailMessages)
        switch intent {
        case .latest(let n): return min(max(n, 1), cap)
        case .unread(let n), .summarizeRecent(let n): return min(max(n, 1), cap)
        case .today, .genericMailbox: return min(5, cap)
        case .fromContact, .aboutTopic: return min(6, cap)
        default: return min(5, cap)
        }
    }

    // MARK: - Heuristics

    private static func isReply(_ lower: String) -> Bool {
        ["répond", "repond", "reply", "rédige une réponse", "redige une reponse",
         "écris une réponse", "ecris une reponse", "prépare une réponse"].contains { lower.contains($0) }
    }

    private static func isSummarizeCurrent(_ lower: String) -> Bool {
        lower.contains("résum") || lower.contains("resum") || lower.contains("synthèse") || lower.contains("synthese")
    }

    private static func isMailboxWide(_ lower: String) -> Bool {
        lower.contains("dernier mail") || lower.contains("derniers mails")
            || lower.contains("dernier e-mail") || lower.contains("derniers e-mail")
            || lower.contains("dernier email") || lower.contains("boîte") || lower.contains("boite")
            || lower.contains("non lus") || lower.contains("non lu")
            || lower.contains("mes mails") || lower.contains("mes e-mails")
            || lower.contains("aujourd'hui") || lower.contains("aujourdhui")
            || lower.contains("qui m'a écrit") || lower.contains("qui m’a écrit")
            || lower.contains("ai-je reçu") || lower.contains("ai je recu")
            || lower.contains("est-ce que j'ai reçu") || lower.contains("est-ce que j’ai reçu")
    }

    private static func looksLikeMailQuestion(_ lower: String) -> Bool {
        lower.contains("mail") || lower.contains("e-mail") || lower.contains("email")
            || lower.contains("courrier") || lower.contains("inbox") || lower.contains("gmail")
    }

    private static func isUnread(_ lower: String) -> Bool {
        lower.contains("non lu") || lower.contains("unread") || lower.contains("pas lus")
    }

    private static func isToday(_ lower: String) -> Bool {
        lower.contains("aujourd'hui") || lower.contains("aujourdhui") || lower.contains("aujourd’hui")
            || lower.contains("ce matin") || lower.contains("cet après")
    }

    private static func isSummarizeRecent(_ lower: String) -> Bool {
        isSummarizeCurrent(lower) && (
            lower.contains("derniers") || lower.contains("récents") || lower.contains("recents")
                || lower.contains("boîte") || lower.contains("boite") || lower.contains("mes mail")
        )
    }

    private static func latestCount(in lower: String) -> Int? {
        if lower.contains("dernier mail") || lower.contains("dernier e-mail")
            || lower.contains("dernier email") || lower.contains("mon dernier") {
            if let n = explicitCount(in: lower) { return n }
            return 1
        }
        if lower.contains("derniers mails") || lower.contains("derniers e-mail")
            || lower.contains("derniers emails") {
            return explicitCount(in: lower) ?? 5
        }
        return nil
    }

    private static func recentCount(in lower: String) -> Int {
        explicitCount(in: lower) ?? 8
    }

    private static func explicitCount(in lower: String) -> Int? {
        let pattern = #"(\d+)\s*(mails?|e-?mails?|messages?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let r = Range(match.range(at: 1), in: lower),
              let n = Int(lower[r]) else { return nil }
        return min(max(n, 1), 20)
    }

    private static func fromContact(in text: String, lower: String) -> String? {
        let markers = ["mail de ", "e-mail de ", "email de ", "reçu de ", "recu de ",
                       "réponse de ", "reponse de ", "écrit ", "ecrit ", "de la part de "]
        for marker in markers where lower.contains(marker) {
            if let range = lower.range(of: marker) {
                let idx = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                var rest = String(text[idx...])
                rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: "«»\"' "))
                let token = rest.split(whereSeparator: { $0.isPunctuation || $0 == "?" || $0 == "!" }).first.map(String.init) ?? rest
                let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count >= 2, cleaned.lowercased() != "moi" { return cleaned }
            }
        }
        return nil
    }

    private static func aboutTopic(in text: String, lower: String) -> String? {
        let markers = ["concernant ", "au sujet de ", "à propos de ", "a propos de ", "sur le mail "]
        for marker in markers where lower.contains(marker) {
            if let range = lower.range(of: marker) {
                let idx = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                var rest = String(text[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
                if rest.count >= 2 { return rest }
            }
        }
        return nil
    }

    private static func sanitizeGmailToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "@" || scalar == "-" || scalar == "_" || scalar == " "
        }
        var out = String(String.UnicodeScalarView(filtered))
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
