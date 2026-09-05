import SwiftUI
import WidgetKit

struct MailEntry: TimelineEntry {
    let date: Date
    let unread: Int
}

struct MailProvider: TimelineProvider {
    func placeholder(in context: Context) -> MailEntry {
        MailEntry(date: Date(), unread: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (MailEntry) -> Void) {
        completion(MailEntry(date: Date(), unread: WidgetSharedStore.snapshot().mailUnread))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MailEntry>) -> Void) {
        let entry = MailEntry(date: Date(), unread: WidgetSharedStore.snapshot().mailUnread)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MailUnreadWidget: Widget {
    let kind = "MailUnreadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MailProvider()) { entry in
            MailWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mail")
        .description("Nombre de mails non lus (sans contenu privé).")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MailWidgetView: View {
    let entry: MailEntry

    var body: some View {
        Link(destination: URL(string: "chatbot-native://tab/mail")!) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mail")
                    .font(.headline.weight(.semibold))
                Text(entry.unread > 0 ? "\(entry.unread)" : "—")
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text(entry.unread == 1 ? "non lu" : "non lus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Ouvrir Mail")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(4)
        }
        .accessibilityLabel("Mail, \(entry.unread) non lus")
    }
}
