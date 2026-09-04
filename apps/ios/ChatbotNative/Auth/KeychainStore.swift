import Foundation
import Security

enum KeychainStore {
    private static let service = "fr.nicolazer.chatbot.native"
    private static let tokenAccount = "app-session-token"
    private static let userAccount = "app-session-user"
    private static let expiresAccount = "app-session-expires"

    static func saveToken(_ token: String) throws {
        try save(account: tokenAccount, value: token)
    }

    static func saveUserId(_ userId: String) throws {
        try save(account: userAccount, value: userId)
    }

    static func saveExpiresAt(_ expiresAt: String) throws {
        try save(account: expiresAccount, value: expiresAt)
    }

    static func loadToken() -> String? { load(account: tokenAccount) }
    static func loadUserId() -> String? { load(account: userAccount) }
    static func loadExpiresAt() -> String? { load(account: expiresAccount) }

    static func clear() {
        delete(account: tokenAccount)
        delete(account: userAccount)
        delete(account: expiresAccount)
    }

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
            throw NSError(domain: "Keychain", code: Int(status))
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
