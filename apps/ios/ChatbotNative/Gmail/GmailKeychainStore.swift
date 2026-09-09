import Foundation
import Security

/// Tokens Gmail OAuth en Keychain (même service que la session app).
///
/// **NE JAMAIS** journaliser les valeurs de tokens.
enum GmailKeychainStore {
    private static let service = "fr.nicolazer.chatbot.native"

    private static let accessTokenAccount = "gmail-access-token"
    private static let refreshTokenAccount = "gmail-refresh-token"
    private static let expiresAtAccount = "gmail-expires-at"
    private static let emailAccount = "gmail-email"
    private static let displayNameAccount = "gmail-display-name"
    private static let grantedScopesAccount = "gmail-granted-scopes"

    static func saveAccessToken(_ token: String) throws {
        try save(account: accessTokenAccount, value: token)
    }

    static func saveRefreshToken(_ token: String) throws {
        try save(account: refreshTokenAccount, value: token)
    }

    /// Instant d’expiration access token (ISO-8601 ou epoch seconds string).
    static func saveExpiresAt(_ expiresAt: String) throws {
        try save(account: expiresAtAccount, value: expiresAt)
    }

    static func saveEmail(_ email: String) throws {
        try save(account: emailAccount, value: email)
    }

    static func loadAccessToken() -> String? { load(account: accessTokenAccount) }
    static func loadRefreshToken() -> String? { load(account: refreshTokenAccount) }
    static func loadExpiresAt() -> String? { load(account: expiresAtAccount) }
    static func loadEmail() -> String? { load(account: emailAccount) }
    static func saveDisplayName(_ name: String) throws {
        try save(account: displayNameAccount, value: name)
    }

    static func loadDisplayName() -> String? { load(account: displayNameAccount) }

    static func saveGrantedScopes(_ scopes: String) throws {
        try save(account: grantedScopesAccount, value: scopes)
    }

    static func loadGrantedScopes() -> String? { load(account: grantedScopesAccount) }

    static func clear() {
        delete(account: accessTokenAccount)
        delete(account: refreshTokenAccount)
        delete(account: expiresAtAccount)
        delete(account: emailAccount)
        delete(account: displayNameAccount)
        delete(account: grantedScopesAccount)
    }

    // MARK: - Keychain primitives (miroir KeychainStore)

    private static func save(account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "GmailKeychain", code: Int(status))
        }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
