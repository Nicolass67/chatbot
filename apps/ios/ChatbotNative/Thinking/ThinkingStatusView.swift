import SwiftUI

/// Thinking — discret, distinct de l’Agent.
struct ThinkingStatusView: View {
    let kind: ThinkingKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: AppTheme.space10) {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 7, height: 7)
                .opacity(reduceMotion ? 0.9 : (pulse ? 1 : 0.35))
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulse
                )

            Text(kind.label)
                .font(CNFont.caption.weight(.medium))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.space16)
        .padding(.vertical, AppTheme.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.label)
        .accessibilityIdentifier(A11yID.Chat.thinking)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            if !reduceMotion { pulse = true }
        }
    }
}

/// Indicateur « ChatGPT-like » dans le fil de messages (emplacement de la future réponse).
struct InStreamWorkingIndicator: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(AppTheme.mutedForeground)
                .opacity(reduceMotion ? 0.85 : (pulse ? 1.0 : 0.42))
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
                    value: pulse
                )
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityIdentifier(A11yID.Chat.thinking)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            if !reduceMotion { pulse = true }
        }
    }
}

/// État de progression user-safe (pas de chaîne de pensée privée).
enum ThinkingKind: Equatable {
    case reflecting
    case analyzing
    case searching
    case verifying
    case preparing
    case working
    case custom(String)

    var label: String {
        switch self {
        case .reflecting: return "Réflexion…"
        case .analyzing: return "Analyse du contexte…"
        case .searching: return "Recherche…"
        case .verifying: return "Vérification…"
        case .preparing: return "Préparation de la réponse…"
        case .working: return "Travail en cours…"
        case .custom(let s): return s
        }
    }

    static func fromSSE(type: String, message: String?) -> ThinkingKind {
        let raw = ((message ?? "") + " " + type).lowercased()
        if raw.contains("search") || raw.contains("recherche") || raw.contains("web") {
            return .searching
        }
        if raw.contains("verif") || raw.contains("check") || raw.contains("valid") {
            return .verifying
        }
        if raw.contains("analy") || raw.contains("context") || raw.contains("contexte") {
            return .analyzing
        }
        if raw.contains("prépar") || raw.contains("prepar") || raw.contains("synth") || raw.contains("répond") {
            return .preparing
        }
        if type == "thinking" || raw.contains("think") || raw.contains("réflex") {
            return .reflecting
        }
        if type == "tool_start" {
            return .working
        }
        if let message, !message.isEmpty, message.count < 48, !message.contains("{") {
            return .custom(message)
        }
        return .reflecting
    }
}
