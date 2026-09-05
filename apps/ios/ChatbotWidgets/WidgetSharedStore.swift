import Foundation
import SwiftUI
import WidgetKit

enum WidgetSharedStore {
    /// ID déclaré dans les entitlements (build Flash / Xcode).
    static let canonicalAppGroupId = "group.fr.nicolazer.chatbot.native"

    private static let resolvedAppGroupId: String = {
        resolveAppGroupId()
    }()

    static var appGroupId: String { resolvedAppGroupId }

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

    struct MailPreviewItem: Codable, Equatable, Identifiable, Hashable {
        var id: String
        var from: String
        var subject: String
        var snippet: String
        var dateLabel: String
        var unread: Bool
    }

    struct FilePreviewItem: Codable, Equatable, Identifiable, Hashable {
        var id: String
        var name: String
        var detail: String
        var isDirectory: Bool
    }

    private static func resolveAppGroupId() -> String {
        let base = canonicalAppGroupId
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: base) != nil {
            return base
        }
        if let remapped = remappedAppGroupId(from: Bundle.main.bundleIdentifier),
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: remapped) != nil {
            return remapped
        }
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
        guard !suffix.isEmpty else { return nil }
        return "\(canonicalAppGroupId).\(suffix)"
    }

    static func snapshot() -> WidgetSnapshot {
        let d = defaults
        func hex(_ key: String, fallback: UInt32) -> UInt32 {
            guard let d, d.object(forKey: key) != nil else { return fallback }
            return UInt32(truncatingIfNeeded: d.integer(forKey: key))
        }
        let mailPreviews: [MailPreviewItem] = {
            guard let data = d?.data(forKey: Key.mailPreviews),
                  let decoded = try? JSONDecoder().decode([MailPreviewItem].self, from: data)
            else { return [] }
            return decoded
        }()
        let filesPreviews: [FilePreviewItem] = {
            guard let data = d?.data(forKey: Key.filesPreviews),
                  let decoded = try? JSONDecoder().decode([FilePreviewItem].self, from: data)
            else { return [] }
            return decoded
        }()
        let updated: Date? = {
            let t = d?.double(forKey: Key.updatedAt) ?? 0
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }()
        let mailSynced = d?.object(forKey: Key.mailSynced) != nil
        let themeSynced = d?.object(forKey: Key.themeSynced) != nil
            || d?.object(forKey: Key.accentLight) != nil
        return WidgetSnapshot(
            runtimeStatus: d?.string(forKey: Key.runtimeStatus) ?? "",
            modelName: d?.string(forKey: Key.modelName) ?? "",
            conversationTitle: d?.string(forKey: Key.conversationTitle) ?? "",
            mailUnread: d?.integer(forKey: Key.mailUnread) ?? 0,
            mailPreviews: mailPreviews,
            mailSynced: mailSynced,
            filesRecentCount: d?.integer(forKey: Key.filesRecentCount) ?? 0,
            filesFolderName: d?.string(forKey: Key.filesFolderName) ?? "",
            filesPreviews: filesPreviews,
            // Fallbacks = défauts catalogue app (ice-blue / cyan / graphite).
            accentLight: hex(Key.accentLight, fallback: 0x3B82F6),
            accentDark: hex(Key.accentDark, fallback: 0x7DD3FC),
            secondaryLight: hex(Key.secondaryLight, fallback: 0x0EA5E9),
            secondaryDark: hex(Key.secondaryDark, fallback: 0x67E8F9),
            backgroundLight: hex(Key.backgroundLight, fallback: 0xF3F5F9),
            backgroundDark: hex(Key.backgroundDark, fallback: 0x0B0F14),
            themeSynced: themeSynced,
            updatedAt: updated
        )
    }
}

struct WidgetSnapshot: Equatable {
    var runtimeStatus: String
    var modelName: String
    var conversationTitle: String
    var mailUnread: Int
    var mailPreviews: [WidgetSharedStore.MailPreviewItem]
    var mailSynced: Bool
    var filesRecentCount: Int
    var filesFolderName: String
    var filesPreviews: [WidgetSharedStore.FilePreviewItem]
    var accentLight: UInt32
    var accentDark: UInt32
    var secondaryLight: UInt32
    var secondaryDark: UInt32
    var backgroundLight: UInt32
    var backgroundDark: UInt32
    var themeSynced: Bool
    var updatedAt: Date?

    enum AssistantPhase: Equatable {
        case ready, loading, unavailable, error, unknown

        var title: String {
            switch self {
            case .ready: return "Prêt"
            case .loading: return "Chargement…"
            case .unavailable: return "Indisponible"
            case .error: return "Erreur"
            case .unknown: return "Ouvrir l’app"
            }
        }

        var detail: String {
            switch self {
            case .ready: return "Modèle local prêt à répondre"
            case .loading: return "Préparation du modèle…"
            case .unavailable: return "Runtime hors ligne"
            case .error: return "Échec runtime — rouvre Chatbot"
            case .unknown: return "Synchronise en ouvrant l’app"
            }
        }

        var symbolName: String {
            switch self {
            case .ready: return "checkmark.circle.fill"
            case .loading: return "arrow.triangle.2.circlepath"
            case .unavailable: return "icloud.slash"
            case .error: return "exclamationmark.triangle.fill"
            case .unknown: return "ellipsis.circle"
            }
        }
    }

    var phase: AssistantPhase {
        switch runtimeStatus.uppercased() {
        case "READY", "OK", "IDLE", "BUSY": return .ready
        case "LOADING", "LOADING_MODEL", "SWITCHING", "WARMING", "WARMING_UP": return .loading
        case "OFFLINE", "UNAVAILABLE": return .unavailable
        case "ERROR", "FAILED": return .error
        default: return .unknown
        }
    }

    func accent(_ scheme: ColorScheme) -> Color {
        Color(widgetHex: scheme == .dark ? accentDark : accentLight)
    }

    func secondary(_ scheme: ColorScheme) -> Color {
        Color(widgetHex: scheme == .dark ? secondaryDark : secondaryLight)
    }

    func canvas(_ scheme: ColorScheme) -> Color {
        Color(widgetHex: scheme == .dark ? backgroundDark : backgroundLight)
    }

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            runtimeStatus: "READY",
            modelName: "Qwen2.5-14B",
            conversationTitle: "Conversation",
            mailUnread: 3,
            mailPreviews: [
                .init(id: "1", from: "Alice Martin", subject: "Facture mars", snippet: "Voici la facture…", dateLabel: "09:12", unread: true),
                .init(id: "2", from: "Banque", subject: "Votre relevé", snippet: "Relevé disponible", dateLabel: "Hier", unread: true),
                .init(id: "3", from: "Nicolas", subject: "Weekend", snippet: "Samedi ?", dateLabel: "Lun.", unread: false),
            ],
            mailSynced: true,
            filesRecentCount: 12,
            filesFolderName: "Documents",
            filesPreviews: [
                .init(id: "a", name: "Contrat.pdf", detail: "PDF · 240 Ko", isDirectory: false),
                .init(id: "b", name: "Photos", detail: "Dossier", isDirectory: true),
                .init(id: "c", name: "Notes.md", detail: "MD · 12 Ko", isDirectory: false),
            ],
            accentLight: 0x3B82F6,
            accentDark: 0x7DD3FC,
            secondaryLight: 0x0EA5E9,
            secondaryDark: 0x67E8F9,
            backgroundLight: 0xF3F5F9,
            backgroundDark: 0x0B0F14,
            themeSynced: true,
            updatedAt: Date()
        )
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

struct WidgetAccentBackground: View {
    let accent: Color
    let secondary: Color
    let canvas: Color
    var colorScheme: ColorScheme

    var body: some View {
        ZStack {
            canvas
            LinearGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.58 : 0.42),
                    secondary.opacity(colorScheme == .dark ? 0.34 : 0.22),
                    canvas.opacity(colorScheme == .dark ? 0.90 : 0.82),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(accent.opacity(colorScheme == .dark ? 0.44 : 0.28))
                .frame(width: 168, height: 168)
                .blur(radius: 36)
                .offset(x: 62, y: -58)
            Circle()
                .fill(secondary.opacity(colorScheme == .dark ? 0.30 : 0.20))
                .frame(width: 132, height: 132)
                .blur(radius: 30)
                .offset(x: -68, y: 60)
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.22),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
    }
}

struct WidgetHeader: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

struct WidgetMetricHero: View {
    let value: String
    let caption: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent.opacity(0.9))
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }
}

struct WidgetRowCard: View {
    let title: String
    let subtitle: String
    let trailing: String?
    let symbol: String
    let accent: Color
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(emphasized ? .bold : .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            accent.opacity(emphasized ? 0.16 : 0.08),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(accent.opacity(emphasized ? 0.55 : 0.22), lineWidth: 1)
        )
    }
}

struct AssistantEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct AssistantProvider: TimelineProvider {
    func placeholder(in context: Context) -> AssistantEntry {
        AssistantEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (AssistantEntry) -> Void) {
        completion(AssistantEntry(date: Date(), snapshot: WidgetSharedStore.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AssistantEntry>) -> Void) {
        let entry = AssistantEntry(date: Date(), snapshot: WidgetSharedStore.snapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date())
            ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
