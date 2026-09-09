import Foundation

/// Source unique Chat vs Agent (sélection utilisateur).
/// Distinct de `EffectiveExecutionMode` (PC vs runtime local).
enum ConversationInteractionMode: String, Codable, CaseIterable, Sendable {
    case chat
    case agent

    init(stored: String?) {
        self = ConversationInteractionMode(rawValue: stored ?? "") ?? .chat
    }
}

/// Quel workflow métier lancer — **jamais** déduit d’un outil Web ou d’un petit modèle.
enum ConversationWorkflowKind: String, Sendable, Equatable {
    case chat
    case agent
    case web
    case mail
    case files
}

enum ConversationWorkflowRouter {
    /// Ordre : Files (scope) → Agent (si l’utilisateur l’a choisi) → Mail → Web → Chat.
    /// Une recherche Web en mode Chat reste `web` (ChatWorkflow / WebSearchWorkflow), jamais `agent`.
    static func kind(
        interaction: ConversationInteractionMode,
        filesScope: Bool,
        preferMail: Bool,
        webEnabled: Bool
    ) -> ConversationWorkflowKind {
        if filesScope { return .files }
        if interaction == .agent { return .agent }
        if preferMail { return .mail }
        if webEnabled { return .web }
        return .chat
    }
}
