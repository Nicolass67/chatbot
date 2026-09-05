import Foundation
import WidgetKit

/// Données minimales partagées App ↔ Widget (pas de secrets / tokens).
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

    static func publishAssistant(status: String, modelName: String?) {
        guard let defaults else { return }
        let prevStatus = defaults.string(forKey: Key.runtimeStatus) ?? ""
        let prevModel = defaults.string(forKey: Key.modelName) ?? ""
        let nextModel = (modelName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let statusChanged = prevStatus != status
        let modelChanged = !nextModel.isEmpty && prevModel != nextModel
        guard statusChanged || modelChanged else { return }

        defaults.set(status, forKey: Key.runtimeStatus)
        if !nextModel.isEmpty {
            defaults.set(nextModel, forKey: Key.modelName)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        WidgetCenter.shared.reloadTimelines(ofKind: "AssistantStatusWidget")
    }

    static func publishMailUnread(_ count: Int) {
        guard let defaults else { return }
        let next = max(0, count)
        if defaults.object(forKey: Key.mailUnread) != nil,
           defaults.integer(forKey: Key.mailUnread) == next {
            return
        }
        defaults.set(next, forKey: Key.mailUnread)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        WidgetCenter.shared.reloadTimelines(ofKind: "MailUnreadWidget")
    }

    static func publishFilesRecentCount(_ count: Int) {
        guard let defaults else { return }
        let next = max(0, count)
        if defaults.object(forKey: Key.filesRecentCount) != nil,
           defaults.integer(forKey: Key.filesRecentCount) == next {
            return
        }
        defaults.set(next, forKey: Key.filesRecentCount)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        WidgetCenter.shared.reloadTimelines(ofKind: "FilesRecentWidget")
    }

    /// Accent thème (hex RRGGBB) — jamais de secrets.
    static func publishAccent(light: UInt32, dark: UInt32) {
        guard let defaults else { return }
        let nextL = Int(light & 0x00FF_FFFF)
        let nextD = Int(dark & 0x00FF_FFFF)
        if defaults.object(forKey: Key.accentLight) != nil,
           defaults.integer(forKey: Key.accentLight) == nextL,
           defaults.integer(forKey: Key.accentDark) == nextD {
            return
        }
        defaults.set(nextL, forKey: Key.accentLight)
        defaults.set(nextD, forKey: Key.accentDark)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
