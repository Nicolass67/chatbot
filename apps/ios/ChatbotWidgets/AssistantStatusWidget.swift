import SwiftUI
import WidgetKit

struct AssistantStatusWidget: Widget {
    let kind = "AssistantStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AssistantProvider()) { entry in
            AssistantWidgetView(entry: entry)
        }
        .configurationDisplayName("Assistant")
        .description("Statut du modèle, conversation active et accès rapide au chat.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AssistantWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: AssistantEntry

    private var snap: WidgetSnapshot { entry.snapshot }
    private var phase: WidgetSnapshot.AssistantPhase { snap.phase }
    private var accent: Color { snap.accent(colorScheme) }
    private var secondary: Color { snap.secondary(colorScheme) }
    private var canvas: Color { snap.canvas(colorScheme) }

    private var modelLabel: String {
        let name = snap.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Modèle local" : name
    }

    private var conversationLabel: String {
        let t = snap.conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Chat" : t
    }

    private var updatedLabel: String {
        guard let date = snap.updatedAt else { return "" }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "fr_FR")
        rel.unitsStyle = .abbreviated
        return "MAJ \(rel.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        Link(destination: URL(string: "chatbot-native://chat")!) {
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
        .accessibilityLabel("Assistant, \(phase.title), \(modelLabel), \(conversationLabel)")
        .accessibilityHint("Ouvre le chat")
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Assistant", systemImage: "message.fill", accent: accent)
            HStack(spacing: 8) {
                Image(systemName: phase.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(phaseColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title)
                        .font(.headline.weight(.bold))
                    Text(phase.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversationLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(modelLabel)
                    .font(.caption2)
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeader(title: "Assistant", systemImage: "message.fill", accent: accent)
                if !updatedLabel.isEmpty {
                    Text(updatedLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: phase.symbolName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 54, height: 54)
                    .background(
                        LinearGradient(
                            colors: [accent.opacity(0.28), secondary.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(phase.title)
                        .font(.title3.weight(.bold))
                    Text(phase.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            WidgetRowCard(
                title: conversationLabel,
                subtitle: modelLabel,
                trailing: nil,
                symbol: "bubble.left.and.bubble.right.fill",
                accent: accent,
                emphasized: true
            )
            Spacer(minLength: 0)
            Text("Continuer le chat")
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .ready: return accent
        case .loading: return secondary
        case .unavailable, .unknown: return .secondary
        case .error: return Color(widgetHex: 0xEF4444)
        }
    }
}
