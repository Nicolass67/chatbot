import SwiftUI
import WidgetKit

struct FilesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FilesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FilesEntry {
        FilesEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FilesEntry) -> Void) {
        completion(FilesEntry(date: Date(), snapshot: WidgetSharedStore.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FilesEntry>) -> Void) {
        let entry = FilesEntry(date: Date(), snapshot: WidgetSharedStore.snapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date())
            ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct FilesRecentWidget: Widget {
    let kind = "FilesRecentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FilesProvider()) { entry in
            FilesWidgetView(entry: entry)
        }
        .configurationDisplayName("Files")
        .description("Dossier courant, compteur et fichiers récents.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FilesWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family
    let entry: FilesEntry

    private var snap: WidgetSnapshot { entry.snapshot }
    private var accent: Color { snap.accent(colorScheme) }
    private var secondary: Color { snap.secondary(colorScheme) }
    private var canvas: Color { snap.canvas(colorScheme) }

    private var folderLabel: String {
        let n = snap.filesFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Dossier" : n
    }

    var body: some View {
        Link(destination: URL(string: "chatbot-native://tab/files")!) {
            Group {
                if family == .systemMedium { mediumBody } else { smallBody }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .containerBackground(for: .widget) {
            WidgetAccentBackground(
                accent: accent,
                secondary: secondary,
                canvas: canvas,
                colorScheme: colorScheme
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Files, \(folderLabel), \(snap.filesRecentCount) éléments")
        .accessibilityHint("Ouvre Files")
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Files", systemImage: "folder.fill", accent: accent)
            Text(folderLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
                .lineLimit(1)
            WidgetMetricHero(
                value: "\(snap.filesRecentCount)",
                caption: snap.filesRecentCount == 1 ? "fichier" : "fichiers",
                accent: accent
            )
            Spacer(minLength: 0)
            if let first = snap.filesPreviews.first {
                VStack(alignment: .leading, spacing: 2) {
                    Label(first.name, systemImage: first.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    if !first.detail.isEmpty {
                        Text(first.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Files", systemImage: "folder.fill", accent: accent)
                Text(folderLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent)
                    .lineLimit(2)
                WidgetMetricHero(
                    value: "\(snap.filesRecentCount)",
                    caption: snap.filesRecentCount == 1 ? "fichier" : "fichiers",
                    accent: accent
                )
                Spacer(minLength: 0)
                Text("Parcourir")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: 120, alignment: .leading)

            VStack(spacing: 6) {
                if snap.filesPreviews.isEmpty {
                    WidgetRowCard(
                        title: "Aucun fichier",
                        subtitle: "Ouvre Files pour synchroniser",
                        trailing: nil,
                        symbol: "folder.badge.questionmark",
                        accent: accent
                    )
                    Spacer(minLength: 0)
                } else {
                    ForEach(snap.filesPreviews.prefix(4)) { item in
                        WidgetRowCard(
                            title: item.name,
                            subtitle: item.detail.isEmpty
                                ? (item.isDirectory ? "Dossier" : "Fichier")
                                : item.detail,
                            trailing: nil,
                            symbol: item.isDirectory ? "folder.fill" : "doc.fill",
                            accent: accent
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
