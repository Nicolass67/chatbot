import Foundation
import SwiftUI
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
        static let accentLight = "widget.accentLight"
        static let accentDark = "widget.accentDark"
    }

    static func snapshot() -> WidgetSnapshot {
        let defaults = defaults
        let accentLight: UInt32 = {
            guard let defaults, defaults.object(forKey: Key.accentLight) != nil else {
                return 0x3B82F6
            }
            return UInt32(truncatingIfNeeded: defaults.integer(forKey: Key.accentLight))
        }()
        let accentDark: UInt32 = {
            guard let defaults, defaults.object(forKey: Key.accentDark) != nil else {
                return 0x7DD3FC
            }
            return UInt32(truncatingIfNeeded: defaults.integer(forKey: Key.accentDark))
        }()
        return WidgetSnapshot(
            runtimeStatus: defaults?.string(forKey: Key.runtimeStatus) ?? "",
            modelName: defaults?.string(forKey: Key.modelName) ?? "",
            mailUnread: defaults?.integer(forKey: Key.mailUnread) ?? 0,
            filesRecentCount: defaults?.integer(forKey: Key.filesRecentCount) ?? 0,
            accentLight: accentLight,
            accentDark: accentDark,
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
    var accentLight: UInt32
    var accentDark: UInt32
    var updatedAt: Date?

    /// Aligné sur ChatScreen / RuntimeStatusPill — jamais « prêt » si le runtime ne l’est pas.
    enum AssistantPhase: Equatable {
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
        // BUSY = modèle prêt (génération en cours) — même règle que assistantReadyForSend.
        case "READY", "OK", "IDLE", "BUSY":
            return .ready
        case "LOADING", "LOADING_MODEL", "SWITCHING", "WARMING", "WARMING_UP":
            return .loading
        case "OFFLINE", "UNAVAILABLE":
            return .unavailable
        case "ERROR", "FAILED":
            return .error
        default:
            return .unknown
        }
    }

    func accentColor(scheme: ColorScheme) -> Color {
        Color(widgetHex: scheme == .dark ? accentDark : accentLight)
    }
}

extension Color {
    init(widgetHex hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
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
                accentLight: 0x3B82F6,
                accentDark: 0x7DD3FC,
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AssistantEntry) -> Void) {
        completion(AssistantEntry(date: Date(), snapshot: WidgetSharedStore.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AssistantEntry>) -> Void) {
        let entry = AssistantEntry(date: Date(), snapshot: WidgetSharedStore.snapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
