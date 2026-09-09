import Foundation

/// Index local des destinataires déjà vus (boîte Gmail / fils chargés).
/// Autocomplétion instantanée sans PC ; le réseau n’est qu’un complément.
@MainActor
final class MailRecipientDirectory {
    static let shared = MailRecipientDirectory()

    private var byEmail: [String: MailRecipientSuggestion] = [:]

    func ingest(summaries: [MailMessageSummary]) {
        for msg in summaries {
            guard let from = msg.from else { continue }
            upsert(email: from.email, name: from.name)
        }
    }

    func ingest(email: String, name: String?) {
        upsert(email: email, name: name)
    }

    func ingest(threadMessages: [MailThreadMessage]) {
        for msg in threadMessages {
            guard let from = msg.from else { continue }
            upsert(email: from.email, name: from.name)
        }
    }

    func suggest(query: String, excluding: [String] = [], limit: Int = 6) -> [MailRecipientSuggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return [] }
        let blocked = Set(excluding.map { $0.lowercased() })
        return byEmail.values
            .filter { !blocked.contains($0.email.lowercased()) }
            .filter { row in
                row.email.lowercased().contains(q)
                    || (row.displayName ?? "").lowercased().contains(q)
            }
            .sorted { lhs, rhs in
                score(lhs, q: q) > score(rhs, q: q)
            }
            .prefix(limit)
            .map { $0 }
    }

    private func upsert(email: String, name: String?) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.count >= 5 else { return }
        let key = trimmed.lowercased()
        let existing = byEmail[key]
        let display = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String? = {
            if let display, !display.isEmpty { return display }
            return existing?.displayName
        }()
        byEmail[key] = MailRecipientSuggestion(email: trimmed, displayName: resolvedName)
    }

    private func score(_ row: MailRecipientSuggestion, q: String) -> Int {
        let email = row.email.lowercased()
        let name = (row.displayName ?? "").lowercased()
        var s = 0
        if email.hasPrefix(q) { s += 30 }
        if name.hasPrefix(q) { s += 24 }
        if email.contains(q) { s += 10 }
        if name.contains(q) { s += 8 }
        return s
    }
}
