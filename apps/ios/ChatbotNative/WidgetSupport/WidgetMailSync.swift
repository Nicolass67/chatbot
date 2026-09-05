import Foundation
import WidgetKit

/// Synchronise le widget Mail hors de l’onglet Mail (lancement / retour premier plan).
enum WidgetMailSync {
    private static var lastAttempt: Date?
    private static let minInterval: TimeInterval = 45

    @MainActor
    static func syncIfNeeded(session: AppSessionStore, force: Bool = false) async {
        guard session.isAuthenticated, let token = session.token, !token.isEmpty else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < minInterval {
            return
        }
        lastAttempt = Date()

        let client = APIClient(baseURL: session.baseURL, token: token)
        do {
            let page = try await client.listMailMessages(
                maxResults: 5,
                category: "inbox",
                query: "is:unread",
                pageToken: nil
            )
            let count = page.resultSizeEstimate ?? page.messages.count
            let previews = page.messages.prefix(5).map { msg -> WidgetSharedStore.MailPreviewItem in
                let name = msg.from?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let email = msg.from?.email ?? ""
                let fromLabel: String = {
                    if let name, !name.isEmpty { return name }
                    if !email.isEmpty { return email }
                    return "Inconnu"
                }()
                let subject = (msg.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let snippet = (msg.snippet ?? "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return WidgetSharedStore.MailPreviewItem(
                    id: msg.id,
                    from: fromLabel,
                    subject: subject.isEmpty ? "(Sans objet)" : subject,
                    snippet: String(snippet.prefix(120)),
                    dateLabel: dateLabel(msg.date),
                    unread: msg.isUnread != false
                )
            }
            WidgetSharedStore.publishMailUnread(count, previews: Array(previews))
        } catch {
            // Conserve la dernière valeur widget.
        }
    }

    private static func dateLabel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return String(raw.prefix(10)) }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "fr_FR")
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
