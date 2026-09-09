import Foundation

/// Événements d’orchestration Agent — **identiques PC SSE / runtime local**.
/// L’UI (`AgentActivityView`) ne parse jamais le texte du modèle.
enum AgentOrchestrationEvent: Sendable, Equatable {
    case started
    case plan(steps: [AgentPlanStep])
    case stepStarted(id: String, title: String)
    case stepCompleted(id: String)
    case stepFailed(id: String, message: String)
    case toolStarted(tool: String, query: String?)
    case toolCompleted(tool: String, sourceCount: Int)
    case webSearch(query: String)
    case sources([SearchSourceDTO])
    case sourceOpened(source: SearchSourceDTO, index: Int, total: Int)
    case synthesizing
    case completed
    case cancelled
    case failed(String)
}

enum WorkflowTrace {
    /// Logs ciblés run/files — toujours émis (validation appareil, pas seulement DEBUG).
    static func log(_ category: String, _ fields: [String: String]) {
        let body = fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        print("[\(category)] \(body)")
    }
}
