import SwiftUI

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

/// Indicateur compact pendant le streaming Chat (pas Agent).
struct ThinkingStatusView: View {
    let kind: ThinkingKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: AppTheme.space12) {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                .frame(width: 22, height: 22)

            Text(kind.label)
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.space16)
        .padding(.vertical, AppTheme.space8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.label)
        .accessibilityIdentifier(A11yID.Chat.thinking)
    }
}
