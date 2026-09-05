import Foundation
import WidgetKit

/// Données partagées App ↔ Widget (App Group). Autorisé : sujets mail, noms fichiers, modèle.
enum WidgetSharedStore {
    /// ID déclaré dans les entitlements (build Flash / Xcode).
    static let canonicalAppGroupId = "group.fr.nicolazer.chatbot.native"

    /// ID réel après sideload free Apple ID (souvent `….native.<TEAM>`).
    private static let resolvedAppGroupId: String = {
        resolveAppGroupId()
    }()

    static var appGroupId: String { resolvedAppGroupId }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    /// Conteneur partagé — nil si App Group inaccessible (signature / profil).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    static var isAppGroupReady: Bool {
        defaults != nil && containerURL != nil
    }

    enum Key {
        static let runtimeStatus = "widget.runtimeStatus"
        static let modelName = "widget.modelName"
        static let conversationTitle = "widget.conversationTitle"
        static let updatedAt = "widget.updatedAt"
        static let mailUnread = "widget.mailUnread"
        static let mailPreviews = "widget.mailPreviews"
        static let mailSynced = "widget.mailSynced"
        static let filesRecentCount = "widget.filesRecentCount"
        static let filesFolderName = "widget.filesFolderName"
        static let filesPreviews = "widget.filesPreviews"
        static let accentLight = "widget.accentLight"
        static let accentDark = "widget.accentDark"
        static let secondaryLight = "widget.secondaryLight"
        static let secondaryDark = "widget.secondaryDark"
        static let backgroundLight = "widget.backgroundLight"
        static let backgroundDark = "widget.backgroundDark"
        static let themeSynced = "widget.themeSynced"
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

    /// Free sideload (isideload) remappe souvent :
    /// - bundle `fr.nicolazer.chatbot.native` → `….native.<TEAM>`
    /// - group `group.fr.nicolazer.chatbot.native` → `….native.<TEAM>`
    /// Sans ce suffixe, app et widget écrivent dans des suites isolées.
    private static func resolveAppGroupId() -> String {
        let base = canonicalAppGroupId
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: base) != nil {
            return base
        }
        if let remapped = remappedAppGroupId(from: Bundle.main.bundleIdentifier),
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: remapped) != nil {
            return remapped
        }
        // Dernier recours : ID remappé même si containerURL est encore nil au cold start.
        if let remapped = remappedAppGroupId(from: Bundle.main.bundleIdentifier) {
            return remapped
        }
        return base
    }

    private static func remappedAppGroupId(from bundleId: String?) -> String? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        let mainPrefix = "fr.nicolazer.chatbot.native."
        let widgetPrefix = "fr.nicolazer.chatbot.native.widgets."
        let suffix: String
        if bundleId.hasPrefix(widgetPrefix) {
            suffix = String(bundleId.dropFirst(widgetPrefix.count))
        } else if bundleId.hasPrefix(mainPrefix) {
            let rest = String(bundleId.dropFirst(mainPrefix.count))
            if rest == "widgets" { return nil }
            if rest.hasPrefix("widgets.") {
                suffix = String(rest.dropFirst("widgets.".count))
            } else {
                suffix = rest
            }
        } else {
            return nil
        }
        guard !suffix.isEmpty, !suffix.contains("/") else { return nil }
        return "\(canonicalAppGroupId).\(suffix)"
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
        let firstSync = defaults.object(forKey: Key.mailSynced) == nil
        if countSame && !previewsChanged && !firstSync { return }

        defaults.set(next, forKey: Key.mailUnread)
        defaults.set(true, forKey: Key.mailSynced)
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
        backgroundDark: UInt32,
        force: Bool = false
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
        var changed = force || defaults.object(forKey: Key.themeSynced) == nil
        for (key, value) in values {
            if defaults.object(forKey: key) == nil || defaults.integer(forKey: key) != value {
                defaults.set(value, forKey: key)
                changed = true
            }
        }
        guard changed else { return }
        defaults.set(true, forKey: Key.themeSynced)
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
            backgroundLight: 0xF3F5F9,
            backgroundDark: 0x0B0F14,
            force: true
        )
    }

    private static func touch(_ defaults: UserDefaults) {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        defaults.synchronize()
    }
}
