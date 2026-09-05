import Foundation
import WidgetKit

/// Données partagées App ↔ Widget (App Group). Autorisé : sujets mail, noms fichiers, modèle.
enum WidgetSharedStore {
    static let appGroupId = "group.fr.nicolazer.chatbot.native"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    enum Key {
        static let runtimeStatus = "widget.runtimeStatus"
        static let modelName = "widget.modelName"
        static let conversationTitle = "widget.conversationTitle"
        static let updatedAt = "widget.updatedAt"
        static let mailUnread = "widget.mailUnread"
        static let mailPreviews = "widget.mailPreviews"
        static let filesRecentCount = "widget.filesRecentCount"
        static let filesFolderName = "widget.filesFolderName"
        static let filesPreviews = "widget.filesPreviews"
        static let accentLight = "widget.accentLight"
        static let accentDark = "widget.accentDark"
        static let secondaryLight = "widget.secondaryLight"
        static let secondaryDark = "widget.secondaryDark"
        static let backgroundLight = "widget.backgroundLight"
        static let backgroundDark = "widget.backgroundDark"
    }

    struct MailPreviewItem: Codable, Equatable, Identifiable {
        var id: String
        var from: String
        var subject: String
        var snippet: String
        var dateLabel: String
        var unread: Bool
    }

    struct FilePreviewItem: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var detail: String
        var isDirectory: Bool
    }

    static func publishAssistant(status: String, modelName: String?, conversationTitle: String? = nil) {
        guard let defaults else { return }
        let prevStatus = defaults.string(forKey: Key.runtimeStatus) ?? ""
        let prevModel = defaults.string(forKey: Key.modelName) ?? ""
        let prevTitle = defaults.string(forKey: Key.conversationTitle) ?? ""
        let nextModel = (modelName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTitle = (conversationTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let statusChanged = prevStatus != status
        let modelChanged = !nextModel.isEmpty && prevModel != nextModel
        let titleChanged = !nextTitle.isEmpty && prevTitle != nextTitle
        guard statusChanged || modelChanged || titleChanged else { return }

        defaults.set(status, forKey: Key.runtimeStatus)
        if !nextModel.isEmpty {
            defaults.set(nextModel, forKey: Key.modelName)
        }
        if !nextTitle.isEmpty {
            defaults.set(nextTitle, forKey: Key.conversationTitle)
        }
        touch(defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: "AssistantStatusWidget")
    }

    /// `previews: nil` = ne touche pas aux aperçus (ex. bump compteur seul).
    static func publishMailUnread(_ count: Int, previews: [MailPreviewItem]? = nil) {
        guard let defaults else { return }
        let next = max(0, count)
        let countSame = defaults.object(forKey: Key.mailUnread) != nil
            && defaults.integer(forKey: Key.mailUnread) == next
        var previewsChanged = false
        if let previews {
            let encoded = (try? JSONEncoder().encode(Array(previews.prefix(5)))) ?? Data()
            let prevData = defaults.data(forKey: Key.mailPreviews) ?? Data()
            if prevData != encoded {
                defaults.set(encoded, forKey: Key.mailPreviews)
                previewsChanged = true
            }
        }
        if countSame && !previewsChanged { return }

        defaults.set(next, forKey: Key.mailUnread)
        touch(defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: "MailUnreadWidget")
    }

    static func publishFilesRecent(
        count: Int,
        folderName: String?,
        previews: [FilePreviewItem]
    ) {
        guard let defaults else { return }
        let next = max(0, count)
        let folder = (folderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = (try? JSONEncoder().encode(Array(previews.prefix(6)))) ?? Data()
        let prevData = defaults.data(forKey: Key.filesPreviews) ?? Data()
        let prevFolder = defaults.string(forKey: Key.filesFolderName) ?? ""
        let countSame = defaults.object(forKey: Key.filesRecentCount) != nil
            && defaults.integer(forKey: Key.filesRecentCount) == next
        if countSame && prevData == encoded && prevFolder == folder { return }

        defaults.set(next, forKey: Key.filesRecentCount)
        defaults.set(folder, forKey: Key.filesFolderName)
        defaults.set(encoded, forKey: Key.filesPreviews)
        touch(defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: "FilesRecentWidget")
    }

    /// Compat : ancien appel compteur seul.
    static func publishFilesRecentCount(_ count: Int) {
        publishFilesRecent(count: count, folderName: nil, previews: [])
    }

    /// Couleurs thème app → widgets (accent + secondaire + fond).
    static func publishTheme(
        accentLight: UInt32,
        accentDark: UInt32,
        secondaryLight: UInt32,
        secondaryDark: UInt32,
        backgroundLight: UInt32,
        backgroundDark: UInt32
    ) {
        guard let defaults else { return }
        let values: [(String, Int)] = [
            (Key.accentLight, Int(accentLight & 0x00FF_FFFF)),
            (Key.accentDark, Int(accentDark & 0x00FF_FFFF)),
            (Key.secondaryLight, Int(secondaryLight & 0x00FF_FFFF)),
            (Key.secondaryDark, Int(secondaryDark & 0x00FF_FFFF)),
            (Key.backgroundLight, Int(backgroundLight & 0x00FF_FFFF)),
            (Key.backgroundDark, Int(backgroundDark & 0x00FF_FFFF)),
        ]
        var changed = false
        for (key, value) in values {
            if defaults.object(forKey: key) == nil || defaults.integer(forKey: key) != value {
                defaults.set(value, forKey: key)
                changed = true
            }
        }
        guard changed else { return }
        touch(defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Accent seul (rétrocompat).
    static func publishAccent(light: UInt32, dark: UInt32) {
        publishTheme(
            accentLight: light,
            accentDark: dark,
            secondaryLight: light,
            secondaryDark: dark,
            backgroundLight: 0xF4F7FB,
            backgroundDark: 0x0B1220
        )
    }

    private static func touch(_ defaults: UserDefaults) {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
    }
}
