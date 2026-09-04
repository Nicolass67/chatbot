import Foundation

/// Active uniquement via `-UITesting` / `CHATBOT_UI_TESTING=1` (XCUITest).
/// Ne jamais activer en production.
enum UITestMode {
    static var isActive: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITesting") { return true }
        if ProcessInfo.processInfo.environment["CHATBOT_UI_TESTING"] == "1" { return true }
        return false
    }

    /// Token in-memory factice — jamais un vrai `chs_` / Bearer utilisateur.
    static let fakeToken = "uitest-local-session"
    static let fakeUserId = "uitest-user"
    static let fakeExpiresAt = "2099-01-01T00:00:00Z"
}
