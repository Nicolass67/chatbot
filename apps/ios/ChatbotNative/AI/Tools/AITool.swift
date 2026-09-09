import Foundation

// MARK: - Tool abstraction (commune PC / local)

struct AIToolCall: Equatable, Sendable {
    var action: String
    var arguments: [String: String]
}

struct AIToolResult: Equatable, Sendable {
    var action: String
    var ok: Bool
    var text: String
    var truncated: Bool

    static func failure(action: String, message: String) -> AIToolResult {
        AIToolResult(action: action, ok: false, text: message, truncated: false)
    }
}

@MainActor
protocol AITool {
    var name: String { get }
    var summary: String { get }
    func execute(arguments: [String: String], profile: LocalModelExecutionProfile) async throws -> AIToolResult
}

/// Parse une action structurée minimale. Ne fait jamais confiance aveugle au JSON modèle.
enum StructuredActionParser {
    enum Parsed: Equatable, Sendable {
        case tool(AIToolCall)
        case final(String)
        case invalid(String)
    }

    /// Accepte JSON compact ou un bloc ```json … ```.
    static func parse(_ raw: String) -> Parsed {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid("sortie vide") }

        if let json = extractJSONObject(from: trimmed),
           let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseObject(obj, fallbackText: trimmed)
        }

        // Pas de JSON → réponse finale texte.
        return .final(trimmed)
    }

    private static func parseObject(_ obj: [String: Any], fallbackText: String) -> Parsed {
        let type = (obj["type"] as? String)?.lowercased()
            ?? (obj["kind"] as? String)?.lowercased()

        if type == "final" || obj["content"] is String && type != "tool" && obj["action"] == nil {
            let content = (obj["content"] as? String)
                ?? (obj["answer"] as? String)
                ?? (obj["text"] as? String)
            if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .final(content.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let action = (obj["action"] as? String)
            ?? (obj["tool"] as? String)
            ?? (obj["name"] as? String)
        if let action, !action.isEmpty {
            var args: [String: String] = [:]
            if let dict = obj["arguments"] as? [String: Any] {
                for (k, v) in dict {
                    args[k] = stringify(v)
                }
            } else if let dict = obj["args"] as? [String: Any] {
                for (k, v) in dict {
                    args[k] = stringify(v)
                }
            }
            // Raccourcis plats : {"action":"web_search","query":"..."}
            for key in ["query", "q", "path", "id", "threadId", "instruction", "url"] {
                if args[key] == nil, let v = obj[key] {
                    args[key] = stringify(v)
                }
            }
            return .tool(AIToolCall(action: action, arguments: args))
        }

        if type == "final" {
            return .final(fallbackText)
        }
        return .invalid("JSON sans action/content exploitable")
    }

    private static func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let b = value as? Bool { return b ? "true" : "false" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return String(describing: value)
    }

    private static func extractJSONObject(from text: String) -> String? {
        if let fenced = text.range(of: "```json"),
           let end = text.range(of: "```", range: fenced.upperBound..<text.endIndex) {
            let inner = String(text[fenced.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.hasPrefix("{") { return inner }
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            return String(text[start...end])
        }
        return nil
    }
}

@MainActor
final class AIToolRegistry {
    private var tools: [String: any AITool] = [:]

    func register(_ tool: any AITool) {
        tools[tool.name] = tool
    }

    var catalogSummary: String {
        tools.values
            .sorted { $0.name < $1.name }
            .map { "- \($0.name): \($0.summary)" }
            .joined(separator: "\n")
    }

    func execute(
        _ call: AIToolCall,
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        guard let tool = tools[call.action] else {
            throw AIRuntimeError.toolUnknown(call.action)
        }
        let result = try await tool.execute(arguments: call.arguments, profile: profile)
        let budget = profile.toolResultCharBudget
        if result.text.count <= budget {
            return result
        }
        let clipped = String(result.text.prefix(budget)) + "\n…[tronqué]"
        return AIToolResult(action: result.action, ok: result.ok, text: clipped, truncated: true)
    }

    /// Registry par défaut pour le runtime local (mêmes noms d’outils côté PC conceptuellement).
    static func makeLocalDefault() -> AIToolRegistry {
        let registry = AIToolRegistry()
        registry.register(WebSearchTool())
        registry.register(WebFetchTool())
        registry.register(MailSearchTool())
        registry.register(MailSummarizeTool())
        registry.register(MailDraftReplyTool())
        registry.register(FilesListTool())
        registry.register(FilesSearchTool())
        registry.register(MemoryRecallTool())
        return registry
    }
}
