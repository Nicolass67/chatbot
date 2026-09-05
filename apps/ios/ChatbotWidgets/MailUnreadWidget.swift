import SwiftUI
import WidgetKit

struct MailEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct MailProvider: TimelineProvider {
    func placeholder(in context: Context) -> MailEntry {
        MailEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MailEntry) -> Void) {
        completion(MailEntry(date: Date(), snapshot: WidgetSharedStore.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MailEntry>) -> Void) {
        let entry = MailEntry(date: Date(), snapshot: WidgetSharedStore.snapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MailUnreadWidget: Widget {
    let kind = "MailUnreadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MailProvider()) { entry in
            MailWidgetView(entry: entry)
        }
        .configurationDisplayName("Mail")
        .description("Non lus, expéditeurs, sujets et aperçus.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MailWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family
    let entry: MailEntry

    private var snap: WidgetSnapshot { entry.snapshot }
    private var accent: Color { snap.accent(colorScheme) }
    private var secondary: Color { snap.secondary(colorScheme) }
    private var canvas: Color { snap.canvas(colorScheme) }

    var body: some View {
        Link(destination: URL(string: "chatbot-native://tab/mail")!) {
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
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Ouvre Mail")
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Mail", systemImage: "envelope.fill", accent: accent)
            WidgetMetricHero(
                value: "\(snap.mailUnread)",
                caption: snap.mailUnread == 1 ? "non lu" : "non lus",
                accent: accent
            )
            Spacer(minLength: 0)
            if let first = snap.mailPreviews.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(first.from)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Text(first.subject)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !first.snippet.isEmpty {
                        Text(first.snippet)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            } else if snap.mailSynced {
                Text(snap.mailUnread == 0 ? "Boîte à jour" : "Pas d’aperçu")
                    .font(.caption)
                    .foregroundStyle(secondary)
            } else {
                Text("Ouvre l’app pour sync")
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
        }
    }

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Mail", systemImage: "envelope.fill", accent: accent)
                WidgetMetricHero(
                    value: "\(snap.mailUnread)",
                    caption: snap.mailUnread == 1 ? "non lu" : "non lus",
                    accent: accent
                )
                Spacer(minLength: 0)
                Text("Ouvrir la boîte")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: 118, alignment: .leading)

            VStack(spacing: 6) {
                if snap.mailPreviews.isEmpty {
                    WidgetRowCard(
                        title: snap.mailSynced ? "Aucun aperçu" : "Pas encore synchronisé",
                        subtitle: snap.mailSynced
                            ? (snap.mailUnread == 0 ? "Boîte à jour" : "Ouvre Mail")
                            : "Ouvre Chatbot pour sync",
                        trailing: nil,
                        symbol: "tray",
                        accent: accent
                    )
                    Spacer(minLength: 0)
                } else {
                    ForEach(snap.mailPreviews.prefix(3)) { item in
                        let line: String = {
                            if !item.snippet.isEmpty {
                                return "\(item.subject) · \(item.snippet)"
                            }
                            return item.subject
                        }()
                        WidgetRowCard(
                            title: item.from,
                            subtitle: line,
                            trailing: item.dateLabel,
                            symbol: item.unread ? "envelope.badge.fill" : "envelope",
                            accent: accent,
                            emphasized: item.unread
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var accessibilityText: String {
        let preview = snap.mailPreviews.first.map { "\($0.from), \($0.subject)" } ?? "aucun aperçu"
        return "Mail, \(snap.mailUnread) non lus, \(preview)"
    }
}
