import Foundation

/// Identité d’affichage (signature mail). Jamais générée deux fois par le modèle.
enum UserDisplayName {
    static func resolved() -> String {
        if let stored = UserDefaults.standard.string(forKey: "user.displayName")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return firstName(from: stored)
        }
        if let gmail = GmailKeychainStore.loadDisplayName()?
            .trimmingCharacters(in: .whitespacesAndNewlines), !gmail.isEmpty {
            return firstName(from: gmail)
        }
        if let email = GmailKeychainStore.loadEmail()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let local = email.split(separator: "@").first {
            let raw = String(local).replacingOccurrences(of: ".", with: " ")
            return raw.split(separator: " ").first.map { $0.capitalized } ?? raw.capitalized
        }
        return ""
    }

    static func firstName(from full: String) -> String {
        let parts = full.split(whereSeparator: { $0.isWhitespace })
        guard let first = parts.first else { return full }
        return String(first)
    }
}

enum MailSignature {
    /// Ajoute « Cordialement, / {nom} » une seule fois. Le modèle ne signe pas.
    static func appendOnce(_ body: String, name: String = UserDisplayName.resolved()) -> String {
        let person = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = stripTrailingComplimentaryClose(
            body.trimmingCharacters(in: .whitespacesAndNewlines),
            name: person
        )
        guard !trimmed.isEmpty else { return body }
        guard !person.isEmpty else { return trimmed }
        if alreadySigned(trimmed, name: person) {
            return trimmed
        }
        return trimmed + "\n\nCordialement,\n\n\(person)"
    }

    /// Retire uniquement une formule de politesse **en fin** de message (pas au milieu).
    static func stripTrailingComplimentaryClose(_ body: String, name: String) -> String {
        var lines = body.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        let nameLower = name.lowercased()
        if !nameLower.isEmpty, let last = lines.last, last.lowercased() == nameLower {
            lines.removeLast()
            while let last = lines.last, last.isEmpty { lines.removeLast() }
        }
        if let last = lines.last, isComplimentaryClose(last) {
            lines.removeLast()
            while let last = lines.last, last.isEmpty { lines.removeLast() }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isComplimentaryClose(_ line: String) -> Bool {
        let t = line.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.;: "))
        let closings = [
            "cordialement",
            "bien cordialement",
            "bien à vous",
            "bien a vous",
            "sincèrement",
            "sincerement",
            "respectueusement",
            "best regards",
            "kind regards",
            "regards",
        ]
        return closings.contains(t)
    }

    static func alreadySigned(_ body: String, name: String) -> Bool {
        let nameLower = name.lowercased()
        guard !nameLower.isEmpty else { return false }
        let tail = String(body.suffix(min(body.count, 180))).lowercased()
        if tail.contains("cordialement") && tail.contains(nameLower) { return true }
        if tail.contains("bien à vous") && tail.contains(nameLower) { return true }
        if tail.contains("bien a vous") && tail.contains(nameLower) { return true }
        if tail.contains("sincèrement") && tail.contains(nameLower) { return true }
        return false
    }
}
