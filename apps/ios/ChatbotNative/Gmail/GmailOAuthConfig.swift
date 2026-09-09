import Foundation

/// Configuration OAuth Google pour Gmail **direct** (iPhone → Google, sans PC).
///
/// Client **public** iOS uniquement : pas de `client_secret` (interdit / inutile avec PKCE).
/// Le Client ID vient exclusivement d’Info.plist (`GoogleOAuthIosClientID`) — jamais hardcodé.
enum GmailOAuthConfig {
    /// Clé Info.plist / xcconfig. Peut être vide tant que le Client ID iOS n’est pas provisionné.
    static let clientIDPlistKey = "GoogleOAuthIosClientID"

    /// Redirect custom scheme (doit matcher CFBundleURLSchemes + console Google Cloud).
    static let redirectURI = "chatbot-native://oauth/gmail"

    /// Scheme passé à `ASWebAuthenticationSession`.
    static let callbackURLScheme = "chatbot-native"

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

    /// Scopes de départ (minimaux pour le mode mail local) :
    /// - `gmail.readonly` — lister / lire messages et fils
    /// - `gmail.compose` — créer des brouillons (sans envoyer)
    /// - `gmail.send` — envoyer **uniquement** après confirmation UI explicite
    /// - `userinfo.email` — afficher le compte connecté (pas de profil élargi)
    static let scopes: [String] = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.compose",
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/userinfo.email",
    ]

    /// Client ID iOS (chaîne vide si non configuré).
    static var clientID: String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: clientIDPlistKey) as? String else {
            return ""
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool { !clientID.isEmpty }

    static var scopeString: String { scopes.joined(separator: " ") }
}
