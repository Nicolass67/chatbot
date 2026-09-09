import Foundation

/// Politique d’état de la carte brouillon — séparée de l’UI pour les tests.
enum MailDraftCardPolicy {
    enum Delivery: String, Equatable, Sendable {
        case draft
        case generating
        case sending
        case sent
        case failed
    }

    static func recoverable(
        collapsed: Bool,
        sent: Bool,
        draftId: String?,
        text: String,
        inConversation: Bool
    ) -> Bool {
        guard collapsed, !sent else { return false }
        if let draftId, !draftId.isEmpty { return true }
        if inConversation { return true }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func visible(
        collapsed: Bool,
        sent: Bool,
        inConversation: Bool,
        draftId: String?,
        streaming: Bool
    ) -> Bool {
        !collapsed
            && !sent
            && (inConversation || !(draftId ?? "").isEmpty || streaming)
    }

    static func statusLabel(
        sent: Bool,
        sending: Bool,
        streaming: Bool,
        stored: String
    ) -> String {
        if sent { return "Envoyé" }
        if sending { return "Envoi…" }
        if streaming { return stored.isEmpty ? "Rédaction…" : stored }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains("envoyé") { return "Brouillon" }
        return trimmed.isEmpty ? "Brouillon" : trimmed
    }

    static func sanitizedRestoreStatus(_ status: String, sent: Bool) -> String {
        if sent { return "Envoyé" }
        let lower = status.lowercased()
        if lower.contains("envoyé") || lower == "envoyé" { return "Brouillon" }
        return status.isEmpty ? "Brouillon" : status
    }
}
