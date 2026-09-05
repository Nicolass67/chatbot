import SwiftUI
import WidgetKit

/// Compteur générique uniquement — aucun nom / contenu de fichier.
struct FilesEntry: TimelineEntry {
    let date: Date
    let count: Int
    let accentLight: UInt32
    let accentDark: UInt32
}

struct FilesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FilesEntry {
        FilesEntry(date: Date(), count: 5, accentLight: 0x0EA5E9, accentDark: 0x67E8F9)
    }

    func getSnapshot(in context: Context, completion: @escaping (FilesEntry) -> Void) {
        let snap = WidgetSharedStore.snapshot()
        completion(
            FilesEntry(
                date: Date(),
                count: snap.filesRecentCount,
                accentLight: snap.accentLight,
                accentDark: snap.accentDark
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FilesEntry>) -> Void) {
        let snap = WidgetSharedStore.snapshot()
        let entry = FilesEntry(
            date: Date(),
            count: snap.filesRecentCount,
            accentLight: snap.accentLight,
            accentDark: snap.accentDark
        )
        let next = Calendar.current.date(byAdding: .minute, value: 45, to: Date())
            ?? Date().addingTimeInterval(2700)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct FilesRecentWidget: Widget {
    let kind = "FilesRecentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FilesProvider()) { entry in
            FilesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Files")
        .description("Nombre de fichiers du dossier courant (sans noms ni contenus).")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FilesWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: FilesEntry

    private var accent: Color {
        Color(widgetHex: colorScheme == .dark ? entry.accentDark : entry.accentLight)
    }

    var body: some View {
        Link(destination: URL(string: "chatbot-native://tab/files")!) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text("Files")
                        .font(.headline.weight(.semibold))
                }
                Text(entry.count > 0 ? "\(entry.count)" : "—")
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text(entry.count == 1 ? "fichier" : "fichiers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Ouvrir Files")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Files, \(entry.count) fichiers")
        .accessibilityHint("Ouvre Files")
    }
}
