import Foundation

/// Horloge runtime pour l’IA locale — injectée dans les prompts système, jamais affichée à l’utilisateur.
enum RuntimeTemporalContext {
    static func now(_ date: Date = Date()) -> Date { date }

    static func currentYear(now: Date = Date()) -> Int {
        Calendar.current.component(.year, from: now)
    }

    /// Marqueur du bloc horloge, utilisé pour ne pas l'injecter deux fois.
    static let clockBlockMarker = "Contexte temporel (interne"

    static func containsClockBlock(_ text: String) -> Bool {
        text.contains(clockBlockMarker)
    }

    /// Bloc à coller dans les system prompts (Agent, chat, recherche).
    static func silentClockBlock(now: Date = Date(), locale: Locale = Locale(identifier: "fr_FR")) -> String {
        let year = currentYear(now: now)
        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.dateStyle = .full
        dayFormatter.timeStyle = .none
        let day = dayFormatter.string(from: now)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let isoDay = iso.string(from: now)

        return """
        Contexte temporel (interne — ne le mentionne pas à l’utilisateur, ne dis pas « selon mon horloge ») :
        - Date du jour : \(day) (\(isoDay))
        - Année en cours : \(year)
        - Pour toute info actuelle (prix, sorties, actualité, « maintenant », « aujourd’hui »), raisonné en \(year) et utilise \(year) dans les requêtes web si une année est utile.
        - N’utilise pas une année passée inventée (ex. 2023/2024) sauf si l’utilisateur la demande explicitement.
        """
    }

    /// Enrichit une requête web si elle parle du présent et n’a pas déjà l’année.
    static func groundWebQuery(_ query: String, now: Date = Date()) -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return q }
        let year = String(currentYear(now: now))
        let lower = q.lowercased()
        if lower.contains(year) { return q }
        if lower.range(of: #"\b20\d{2}\b"#, options: .regularExpression) != nil {
            return q
        }
        let currentHints = [
            "actuel", "actuelle", "aujourd", "maintenant", "ce jour", "prix",
            "meilleur", "meilleure", "dernier", "dernière", "récent", "recente",
            "sortie", "disponible", "en ce moment", "cette année", "cette annee",
        ]
        guard currentHints.contains(where: { lower.contains($0) }) else { return q }
        return "\(q) \(year)"
    }
}
