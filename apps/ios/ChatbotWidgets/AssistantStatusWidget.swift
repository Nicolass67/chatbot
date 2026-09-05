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
    let entry: AssistantEntry

    private var phase: WidgetSnapshot.AssistantPhase { entry.snapshot.phase }
    private var modelLabel: String {
        let name = entry.snapshot.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Modèle local" : name
    }

    var body: some View {
        Link(destination: URL(string: "chatbot-native://chat")!) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Assistant")
                    .font(.headline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(phase.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(phaseColor)
                    Text(phase.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                if family == .systemMedium {
                    Text(modelLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Ouvrir le chat")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                } else {
                    Spacer(minLength: 0)
                    Text(modelLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(4)
        }
        .accessibilityLabel("Assistant, \(phase.title), \(modelLabel)")
    }

    private var phaseColor: Color {
        switch phase {
        case .ready: return .green
        case .loading: return .orange
        case .unavailable, .unknown: return .secondary
        case .error: return .red
        }
    }
}
