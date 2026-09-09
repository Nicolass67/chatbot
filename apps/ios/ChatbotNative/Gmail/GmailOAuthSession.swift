import Foundation
import AuthenticationServices
import CryptoKit
import Combine
import UIKit

enum GmailOAuthError: Error, LocalizedError, Sendable {
    case notConfigured
    case cancelled
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case keychain(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Client Google OAuth non configuré (GoogleOAuthIosClientID manquant)."
        case .cancelled:
            return "Connexion Gmail annulée."
        case .invalidCallback:
            return "Retour OAuth Gmail invalide."
        case .stateMismatch:
            return "Échec de sécurité OAuth (état incohérent). Réessaie."
        case .tokenExchangeFailed(let detail):
            return "Échange du code OAuth impossible. \(detail)"
        case .refreshFailed(let detail):
            return "Session Gmail expirée — reconnexion nécessaire. \(detail)"
        case .keychain(let detail):
            return "Impossible d’enregistrer les identifiants Gmail. \(detail)"
        case .network(let detail):
            return "Réseau indisponible pour Gmail. \(detail)"
        }
    }
}

/// Session OAuth Gmail native (PKCE, client public iOS). Tokens en Keychain — jamais loggés.
@MainActor
final class GmailOAuthSession: NSObject, ObservableObject {
    static let shared = GmailOAuthSession()

    @Published private(set) var isConnected = false
    @Published private(set) var email: String?
    @Published var lastError: String?
    @Published var isBusy = false

    private var authSession: ASWebAuthenticationSession?
    private var pendingState: String?
    private var pendingCodeVerifier: String?

    /// Marge avant expiration pour rafraîchir l’access token.
    private let refreshSkew: TimeInterval = 60

    override init() {
        super.init()
        restoreFromKeychain()
    }

    func restoreFromKeychain() {
        email = GmailKeychainStore.loadEmail()
        isConnected = GmailKeychainStore.loadRefreshToken() != nil
            || GmailKeychainStore.loadAccessToken() != nil
    }

    // MARK: - Connect / Disconnect

    func connect() {
        lastError = nil
        guard GmailOAuthConfig.isConfigured else {
            lastError = GmailOAuthError.notConfigured.localizedDescription
            return
        }
        isBusy = true

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.s256Challenge(verifier: verifier)
        let state = Self.makeState()
        pendingCodeVerifier = verifier
        pendingState = state

        var components = URLComponents(url: GmailOAuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GmailOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GmailOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GmailOAuthConfig.scopeString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let startURL = components.url else {
            lastError = "URL d’autorisation Gmail invalide."
            isBusy = false
            return
        }

        let session = ASWebAuthenticationSession(
            url: startURL,
            callbackURLScheme: GmailOAuthConfig.callbackURLScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                defer { self.isBusy = false }
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionErrorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.lastError = GmailOAuthError.cancelled.localizedDescription
                    } else {
                        self.lastError = error.localizedDescription
                    }
                    return
                }
                guard let callbackURL else {
                    self.lastError = GmailOAuthError.invalidCallback.localizedDescription
                    return
                }
                do {
                    try await self.finishAuthorization(callbackURL: callbackURL)
                } catch {
                    self.lastError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    /// Callback deep link hors `ASWebAuthenticationSession` (ex. `onOpenURL`).
    /// Retourne `true` si l’URL a été consommée.
    @discardableResult
    func handleCallbackURL(_ url: URL) -> Bool {
        guard url.scheme == GmailOAuthConfig.callbackURLScheme else { return false }
        // chatbot-native://oauth/gmail?...
        let absolute = url.absoluteString.lowercased()
        guard absolute.contains("oauth/gmail") else { return false }
        guard pendingCodeVerifier != nil else { return false }
        isBusy = true
        Task { @MainActor in
            defer { self.isBusy = false }
            do {
                try await self.finishAuthorization(callbackURL: url)
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        return true
    }

    func disconnect() async {
        lastError = nil
        isBusy = true
        defer { isBusy = false }
        if let token = GmailKeychainStore.loadAccessToken() ?? GmailKeychainStore.loadRefreshToken() {
            await revokeQuietly(token: token)
        }
        GmailKeychainStore.clear()
        isConnected = false
        email = nil
        pendingState = nil
        pendingCodeVerifier = nil
    }

    // MARK: - Access token

    /// Access token valide (rafraîchit si expiré). Ne log jamais la valeur.
    func validAccessToken() async throws -> String {
        if let token = GmailKeychainStore.loadAccessToken(), !isAccessTokenExpired() {
            return token
        }
        return try await refreshAccessToken()
    }

    func refreshAccessToken() async throws -> String {
        guard let refresh = GmailKeychainStore.loadRefreshToken(), !refresh.isEmpty else {
            isConnected = false
            throw GmailOAuthError.refreshFailed("Aucun jeton de rafraîchissement.")
        }
        guard GmailOAuthConfig.isConfigured else {
            throw GmailOAuthError.notConfigured
        }

        var request = URLRequest(url: GmailOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = Self.formBody([
            "client_id": GmailOAuthConfig.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        request.httpBody = Data(body.utf8)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: request)
        } catch {
            throw GmailOAuthError.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw GmailOAuthError.refreshFailed("Réponse invalide.")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Ne pas inclure le corps brut (peut contenir des indices) — message FR générique.
            throw GmailOAuthError.refreshFailed("Code HTTP \(http.statusCode).")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String, !access.isEmpty
        else {
            throw GmailOAuthError.refreshFailed("Jeton d’accès manquant.")
        }

        do {
            try GmailKeychainStore.saveAccessToken(access)
            if let expiresIn = obj["expires_in"] as? Int ?? (obj["expires_in"] as? Double).map(Int.init) {
                let date = Date().addingTimeInterval(TimeInterval(expiresIn))
                try GmailKeychainStore.saveExpiresAt(Self.iso8601.string(from: date))
            }
            if let newRefresh = obj["refresh_token"] as? String, !newRefresh.isEmpty {
                try GmailKeychainStore.saveRefreshToken(newRefresh)
            }
        } catch {
            throw GmailOAuthError.keychain(error.localizedDescription)
        }
        isConnected = true
        return access
    }

    // MARK: - Private

    private func finishAuthorization(callbackURL: URL) async throws {
        guard let verifier = pendingCodeVerifier else {
            throw GmailOAuthError.invalidCallback
        }
        let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw GmailOAuthError.tokenExchangeFailed(err)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw GmailOAuthError.invalidCallback
        }
        if let expected = pendingState {
            let got = items.first(where: { $0.name == "state" })?.value
            guard got == expected else { throw GmailOAuthError.stateMismatch }
        }

        try await exchangeCode(code: code, verifier: verifier)
        pendingCodeVerifier = nil
        pendingState = nil
        authSession = nil
    }

    private func exchangeCode(code: String, verifier: String) async throws {
        guard GmailOAuthConfig.isConfigured else { throw GmailOAuthError.notConfigured }

        var request = URLRequest(url: GmailOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = Self.formBody([
            "client_id": GmailOAuthConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GmailOAuthConfig.redirectURI,
        ])
        request.httpBody = Data(body.utf8)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: request)
        } catch {
            throw GmailOAuthError.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw GmailOAuthError.tokenExchangeFailed("Code HTTP \(code).")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String, !access.isEmpty
        else {
            throw GmailOAuthError.tokenExchangeFailed("Réponse token incomplète.")
        }

        do {
            try GmailKeychainStore.saveAccessToken(access)
            if let refresh = obj["refresh_token"] as? String, !refresh.isEmpty {
                try GmailKeychainStore.saveRefreshToken(refresh)
            }
            if let expiresIn = obj["expires_in"] as? Int ?? (obj["expires_in"] as? Double).map(Int.init) {
                let date = Date().addingTimeInterval(TimeInterval(expiresIn))
                try GmailKeychainStore.saveExpiresAt(Self.iso8601.string(from: date))
            }
        } catch {
            throw GmailOAuthError.keychain(error.localizedDescription)
        }

        let accountEmail = try await fetchUserEmail(accessToken: access)
        if let accountEmail {
            do {
                try GmailKeychainStore.saveEmail(accountEmail)
            } catch {
                throw GmailOAuthError.keychain(error.localizedDescription)
            }
            email = accountEmail
        }
        isConnected = true
        lastError = nil
    }

    private func fetchUserEmail(accessToken: String) async throws -> String? {
        var req = URLRequest(url: GmailOAuthConfig.userInfoEndpoint)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["email"] as? String
    }

    private func revokeQuietly(token: String) async {
        var req = URLRequest(url: GmailOAuthConfig.revokeEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(Self.formBody(["token": token]).utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func isAccessTokenExpired() -> Bool {
        guard let raw = GmailKeychainStore.loadExpiresAt() else { return true }
        if let date = Self.iso8601.date(from: raw) {
            return date.timeIntervalSinceNow < refreshSkew
        }
        if let epoch = TimeInterval(raw) {
            return Date(timeIntervalSince1970: epoch).timeIntervalSinceNow < refreshSkew
        }
        return true
    }

    // MARK: - PKCE helpers

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func s256Challenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static let formAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func formBody(_ fields: [String: String]) -> String {
        fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}

extension GmailOAuthSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
