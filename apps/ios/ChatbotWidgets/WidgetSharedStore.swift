import Foundation
import WidgetKit

/// Copie locale des clés App Group (évite de lier le target app).
enum WidgetSharedStore {
    static let appGroupId = "group.fr.nicolazer.chatbot.native"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    enum Key {
        static let runtimeStatus = "widget.runtimeStatus"
        static let modelName = "widget.modelName"
        static let updatedAt = "widget.updatedAt"
        static let mailUnread = "widget.mailUnread"
        static let filesRecentCount = "widget.filesRecentCount"
    }

    static func snapshot() -> WidgetSnapshot {
        let defaults = defaults
        return WidgetSnapshot(
            runtimeStatus: defaults?.string(forKey: Key.runtimeStatus) ?? "",
            modelName: defaults?.string(forKey: Key.modelName) ?? "",
            mailUnread: defaults?.integer(forKey: Key.mailUnread) ?? 0,
            filesRecentCount: defaults?.integer(forKey: Key.filesRecentCount) ?? 0,
            updatedAt: {
                let t = defaults?.double(forKey: Key.updatedAt) ?? 0
                return t > 0 ? Date(timeIntervalSince1970: t) : nil
            }()
        )
    }
}

struct WidgetSnapshot: Equatable {
    var runtimeStatus: String
    var modelName: String
    var mailUnread: Int
    var filesRecentCount: Int
    var updatedAt: Date?

    enum AssistantPhase {
        case ready, loading, unavailable, error, unknown

        var title: String {
            switch self {
            case .ready: return "Assistant prêt"
            case .loading: return "Chargement…"
            case .unavailable: return "Modèle indisponible"
            case .error: return "Assistant indisponible"
            case .unknown: return "Ouvrir Chatbot"
            }
        }

        var symbol: String {
            switch self {
            case .ready: return "●"
            case .loading: return "◌"
            case .unavailable, .unknown: return "○"
            case .error: return "!"
            }
        }
    }

    var phase: AssistantPhase {
        switch runtimeStatus.uppercased() {
        case "READY", "OK", "IDLE": return .ready
        case "LOADING", "LOADING_MODEL", "SWITCHING", "BUSY", "WARMING": return .loading
        case "OFFLINE", "UNAVAILABLE": return .unavailable
        case "ERROR", "FAILED": return .error
        default: return .unknown
        }
    }
}

struct AssistantEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct AssistantProvider: TimelineProvider {
    func placeholder(in context: Context) -> AssistantEntry {
        AssistantEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                runtimeStatus: "READY",
                modelName: "Modèle local",
                mailUnread: 0,
                filesRecentCount: 0,
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AssistantEntry) -> Void) {
        completion(AssistantEntry(date: Date(), snapshot: WidgetSharedStore.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AssistantEntry>) -> Void) {
        let entry = AssistantEntry(date: Date(), snapshot: WidgetSharedStore.snapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
