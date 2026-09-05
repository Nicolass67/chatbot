import SwiftUI
import WidgetKit

struct AssistantStatusWidget: Widget {
    let kind = "AssistantStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AssistantProvider()) { entry in
            AssistantWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Assistant")
        .description("Statut du modèle local et accès rapide au chat.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AssistantWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: AssistantEntry

    private var phase: WidgetSnapshot.AssistantPhase { entry.snapshot.phase }
    private var accent: Color { entry.snapshot.accentColor(scheme: colorScheme) }
    private var modelLabel: String {
        let name = entry.snapshot.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Modèle local" : name
    }

    var body: some View {
        Link(destination: URL(string: "chatbot-native://chat")!) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "message.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text("Assistant")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(phase.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(phaseColor)
                        .accessibilityHidden(true)
                    Text(phase.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }

                if family == .systemMedium {
                    Text(modelLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Ouvrir")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                } else {
                    Spacer(minLength: 0)
                    Text(modelLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant, \(phase.title), \(modelLabel)")
        .accessibilityHint("Ouvre le chat")
    }

    private var phaseColor: Color {
        switch phase {
        case .ready: return accent
        case .loading: return accent.opacity(0.75)
        case .unavailable, .unknown: return .secondary
        case .error: return Color(widgetHex: 0xEF4444)
        }
    }
}
