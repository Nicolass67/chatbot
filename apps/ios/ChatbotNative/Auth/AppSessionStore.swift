import Foundation
import AuthenticationServices
import Combine
import UIKit
import LocalAuthentication

@MainActor
final class AppSessionStore: NSObject, ObservableObject {
    @Published var token: String?
    @Published var userId: String?
    @Published var expiresAt: String?
    @Published var isBusy = false
    @Published var lastError: String?
    @Published var isUnlocked = true
    @Published var biometricLockEnabled: Bool = UserDefaults.standard.bool(forKey: "biometricLockEnabled")

    /// Host placeholder (Public.xcconfig / builds sans injection CI).
    static let placeholderHost = "your-worker.example.workers.dev"

    /// Origin publique (Info.plist `ChatbotPublicBaseURL` via Public.xcconfig / Local.xcconfig / Flash CI).
    let baseURL: URL = {
        let placeholder = URL(string: "https://\(AppSessionStore.placeholderHost)")!
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ChatbotPublicBaseURL") as? String
        else { return placeholder }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.host != nil else {
            return placeholder
        }
        return url
    }()

    /// True si Info.plist n’a pas d’origin réelle (clé absente ou placeholder).
    var isMisconfiguredBaseURL: Bool {
        guard let host = baseURL.host?.lowercased() else { return true }
        return host == Self.placeholderHost || host.contains("your-worker.example")
    }

    private var authSession: ASWebAuthenticationSession?

    var isAuthenticated: Bool { token?.isEmpty == false }

    var sessionExpiringSoon: Bool {
        guard let expiresAt,
              let date = ISO8601DateFormatter().date(from: expiresAt)
                ?? ISO8601DateFormatter().date(from: expiresAt.replacingOccurrences(of: " ", with: "T") + "Z")
        else { return false }
        return date.timeIntervalSinceNow < 24 * 3600 && date.timeIntervalSinceNow > 0
    }

    var sessionExpired: Bool {
        guard let expiresAt,
              let date = ISO8601DateFormatter().date(from: expiresAt)
                ?? ISO8601DateFormatter().date(from: expiresAt.replacingOccurrences(of: " ", with: "T") + "Z")
        else { return false }
        return date.timeIntervalSinceNow <= 0
    }

    override init() {
        super.init()
        let args = ProcessInfo.processInfo.arguments
        let uiTesting = args.contains("-UITesting")
            || ProcessInfo.processInfo.environment["CHATBOT_UI_TESTING"] == "1"
        if uiTesting {
            // Session locale déterministe — jamais de vrai token / Keychain utilisateur.
            token = UITestMode.fakeToken
            userId = UITestMode.fakeUserId
            expiresAt = UITestMode.fakeExpiresAt
            isUnlocked = true
            biometricLockEnabled = false
        } else if let existing = KeychainStore.loadToken() {
            token = existing
            userId = KeychainStore.loadUserId()
            expiresAt = KeychainStore.loadExpiresAt()
            if biometricLockEnabled {
                isUnlocked = false
            } else {
                isUnlocked = true
            }
            if sessionExpired {
                Task { await logout() }
            }
        }
    }

    func setBiometricLockEnabled(_ enabled: Bool) {
        biometricLockEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "biometricLockEnabled")
        if enabled {
            isUnlocked = false
        } else {
            isUnlocked = true
        }
    }

    func unlockWithBiometrics() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fallback device passcode
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                isUnlocked = true
                return
            }
            do {
                let ok = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Déverrouiller Chatbot"
                )
                isUnlocked = ok
            } catch {
                lastError = error.localizedDescription
            }
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Déverrouiller Chatbot"
            )
            isUnlocked = ok
        } catch {
            lastError = error.localizedDescription
        }
    }

    func login() {
        lastError = nil
        if isMisconfiguredBaseURL {
            lastError =
                "Origin non configurée (\(Self.placeholderHost)). Réinstalle l’IPA Flash avec la bonne URL."
            isBusy = false
            return
        }
        isBusy = true
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/auth/app-session/start"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "redirect_uri", value: "chatbot-native://auth"),
        ]
        guard let startURL = components.url else {
            lastError = "URL de login invalide"
            isBusy = false
            return
        }

        let session = ASWebAuthenticationSession(
            url: startURL,
            callbackURLScheme: "chatbot-native"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                guard let callbackURL,
                      let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let token = comps.queryItems?.first(where: { $0.name == "token" })?.value,
                      token.hasPrefix("chs_")
                else {
                    self.lastError = "Callback OAuth invalide"
                    return
                }
                do {
                    try KeychainStore.saveToken(token)
                    self.token = token
                    if let uid = comps.queryItems?.first(where: { $0.name == "userId" })?.value {
                        try KeychainStore.saveUserId(uid)
                        self.userId = uid
                    }
                    if let exp = comps.queryItems?.first(where: { $0.name == "expiresAt" })?.value {
                        try KeychainStore.saveExpiresAt(exp)
                        self.expiresAt = exp
                    }
                    self.isUnlocked = true
                } catch {
                    self.lastError = "Keychain: \(error.localizedDescription)"
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    func logout() async {
        if UITestMode.isActive {
            // Keep deterministic in-memory session for XCUITest.
            token = UITestMode.fakeToken
            userId = UITestMode.fakeUserId
            expiresAt = UITestMode.fakeExpiresAt
            isUnlocked = true
            return
        }
        if let token {
            var req = URLRequest(url: baseURL.appendingPathComponent("api/auth/app-session"))
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("ios", forHTTPHeaderField: "X-Client")
            req.setValue("3.0.0", forHTTPHeaderField: "X-App-Version")
            _ = try? await URLSession.shared.data(for: req)
        }
        KeychainStore.clear()
        TabMemoryCache.clearAll()
        token = nil
        userId = nil
        expiresAt = nil
        isUnlocked = true
    }
}

extension AppSessionStore: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
