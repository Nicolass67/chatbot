import Foundation

/// Configuration OAuth Google pour Gmail **direct** (iPhone → Google, sans PC).
///
/// Client **public** iOS uniquement : pas de `client_secret` (interdit / inutile avec PKCE).
/// Le Client ID vient exclusivement d’Info.plist (`GoogleOAuthIosClientID`) — jamais hardcodé.
enum GmailOAuthConfig {
    /// Clé Info.plist / xcconfig. Peut être vide tant que le Client ID iOS n’est pas provisionné.
    static let clientIDPlistKey = "GoogleOAuthIosClientID"
    static let urlSchemePlistKey = "GoogleOAuthIosURLScheme"

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

    static let readonlyScope = "https://www.googleapis.com/auth/gmail.readonly"
    static let composeScope = "https://www.googleapis.com/auth/gmail.compose"
    static let sendScope = "https://www.googleapis.com/auth/gmail.send"
    /// Labels (UNREAD), trash — **pas** `mail.google.com` (suppression permanente).
    static let modifyScope = "https://www.googleapis.com/auth/gmail.modify"
    static let userInfoEmailScope = "https://www.googleapis.com/auth/userinfo.email"

    /// List/get → readonly ; send → send/compose ; mark-read/trash → modify.
    static let scopes: [String] = [
        readonlyScope,
        composeScope,
        sendScope,
        modifyScope,
        userInfoEmailScope,
    ]

    static let mutationScopes: [String] = [modifyScope]

    /// Client ID iOS (chaîne vide si non configuré).
    static var clientID: String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: clientIDPlistKey) as? String else {
            return ""
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Scheme iOS Google (`com.googleusercontent.apps.…`) — Info.plist ou dérivé du Client ID.
    static var reversedClientID: String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: urlSchemePlistKey) as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return Self.reversedClientID(from: clientID)
    }

    /// Redirect URI standard client iOS Google (AppAuth).
    static var redirectURI: String {
        let scheme = callbackURLScheme
        guard !scheme.isEmpty else { return "" }
        return "\(scheme):/oauthredirect"
    }

    /// Scheme passé à `ASWebAuthenticationSession`.
    static var callbackURLScheme: String { reversedClientID }

    static var isConfigured: Bool {
        !clientID.isEmpty && !callbackURLScheme.isEmpty
    }

    static var scopeString: String { scopes.joined(separator: " ") }

    static func reversedClientID(from clientID: String) -> String {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = ".apps.googleusercontent.com"
        guard id.hasSuffix(suffix) else { return "" }
        let prefix = String(id.dropLast(suffix.count))
        guard !prefix.isEmpty else { return "" }
        return "com.googleusercontent.apps.\(prefix)"
    }
}

/// Scopes réellement renvoyés par Google — jamais les scopes *demandés* si la réponse est vide.
enum GmailGrantedScopes {
    static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func set(from raw: String?) -> Set<String> {
        guard let normalized = normalized(raw) else { return [] }
        return Set(
            normalized
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    static func contains(_ granted: Set<String>, required: [String]) -> Bool {
        !granted.isEmpty && required.allSatisfy { granted.contains($0) }
    }
}
