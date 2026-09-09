import Foundation

/// Routage Mail : API PC vs Gmail direct (iPhone → Google).
enum MailDataSource {
    /// Priorité au Gmail direct dès qu’une session OAuth locale est connectée,
    /// sinon fallback local/offline (PC down, mode local, etc.).
    @MainActor
    static func prefersDirect(
        session: AppSessionStore,
        execution: ExecutionModeStore,
        infra: InfrastructureStore,
        oauth: GmailOAuthSession = .shared
    ) -> Bool {
        if oauth.isConnected { return true }
        return session.localOnlyMode
            || execution.shouldUseLocalLLM
            || execution.preference == .forceLocal
            || infra.isPcConfirmedOffline
    }
}
