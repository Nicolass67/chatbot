import Foundation

/// Verrou d’envoi synchrone (anti double-tap) — testable hors SwiftUI.
enum ChatSendGate {
    /// Pose `isSending = true` immédiatement si libre. Sinon refuse.
    @discardableResult
    static func tryBegin(isSending: inout Bool) -> Bool {
        guard !isSending else { return false }
        isSending = true
        return true
    }
}

/// Décision pure d’auto-chargement (pas de téléchargement / pas de 2e load).
enum LocalModelAutoLoadPolicy {
    static func shouldAttemptLoad(
        wantsLocalExecution: Bool,
        isInstalled: Bool,
        isReady: Bool,
        exclusiveBusy: Bool,
        isLoading: Bool
    ) -> Bool {
        guard wantsLocalExecution else { return false }
        guard isInstalled else { return false }
        guard !isReady else { return false }
        guard !exclusiveBusy else { return false }
        guard !isLoading else { return false }
        return true
    }
}
