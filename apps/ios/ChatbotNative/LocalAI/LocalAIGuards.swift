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

/// Télécharger n’active **jamais** le modèle. L’utilisateur doit appuyer sur Utiliser.
enum LocalModelInstallPolicy {
    static let activatesDownloadedModel = false
}

/// Pin llama.cpp : Gemma 4 (`LLM_ARCH_GEMMA4` + `PROJECTOR_TYPE_GEMMA4V`) est déjà dans b10809.
/// Ne pas bumper : la vision Qwen3.5 fonctionne sur ce tag.
enum LlamaCppPinnedRelease {
    static let tag = "b10809"
    static let gemma4TextArchitectureSupported = true
    static let gemma4vProjectorSupported = true
}
