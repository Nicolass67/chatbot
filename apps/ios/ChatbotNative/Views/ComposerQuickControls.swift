import SwiftUI

/// Canal d’outil forcé depuis le composer (cycle web → files → email).
enum ComposerToolChannel: String, CaseIterable, Identifiable {
    case web
    case files
    case email

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .web: return "globe"
        case .files: return "folder"
        case .email: return "envelope"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .web: return "Recherche web"
        case .files: return "Fichiers locaux"
        case .email: return "Outils e-mail"
        }
    }

    var menuTitle: String {
        switch self {
        case .web: return "Web"
        case .files: return "Fichiers"
        case .email: return "E-mail"
        }
    }

    mutating func cycle() {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return }
        self = all[(idx + 1) % all.count]
    }
}

/// Trois boutons ronds (icônes) : thinking, chat/agent, canal d’outil.
struct ComposerQuickControls: View {
    let thinkingEnabled: Bool
    let chatMode: String
    let toolChannel: ComposerToolChannel
    let thinkingAvailable: Bool
    let onToggleThinking: () -> Void
    let onToggleMode: () -> Void
    let onCycleTool: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ComposerRoundIconButton(
                systemImage: thinkingEnabled ? "brain.fill" : "brain",
                isActive: thinkingEnabled,
                disabled: !thinkingAvailable,
                accessibilityLabel: thinkingEnabled ? "Raisonnement activé" : "Raisonnement désactivé",
                accessibilityIdentifier: A11yID.Chat.thinkingToggle,
                action: onToggleThinking
            )

            ComposerRoundIconButton(
                systemImage: chatMode == "agent" ? "cpu.fill" : "bubble.left.and.bubble.right",
                isActive: chatMode == "agent",
                disabled: false,
                accessibilityLabel: chatMode == "agent" ? "Mode agent" : "Mode chat",
                accessibilityIdentifier: A11yID.Chat.modeToggle,
                action: onToggleMode
            )

            ComposerRoundIconButton(
                systemImage: toolChannel.systemImage,
                isActive: true,
                disabled: false,
                accessibilityLabel: toolChannel.accessibilityLabel,
                accessibilityIdentifier: A11yID.Chat.toolChannel,
                action: onCycleTool
            )
        }
        .accessibilityElement(children: .contain)
    }
}

struct ComposerRoundIconButton: View {
    let systemImage: String
    let isActive: Bool
    let disabled: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    /// Disque visible (~36) + zone tactile 44pt (HIG) pour un tap fiable au pouce.
    private let visualSize: CGFloat = 36
    private let hitSize: CGFloat = AppTheme.touchMin

    var body: some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    disabled
                        ? AppTheme.mutedForeground.opacity(0.45)
                        : (isActive ? AppTheme.accentForeground : AppTheme.mutedForeground)
                )
                .frame(width: visualSize, height: visualSize)
                .background(
                    Circle().fill(
                        disabled
                            ? Color.clear
                            : (isActive ? AppTheme.accent.opacity(0.92) : AppTheme.surfaceElevated.opacity(0.55))
                    )
                )
                .overlay(
                    Circle().stroke(
                        disabled
                            ? AppTheme.borderSubtle.opacity(0.35)
                            : (isActive ? Color.clear : AppTheme.borderSubtle.opacity(0.7)),
                        lineWidth: 0.8
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: hitSize, height: hitSize)
        .contentShape(Circle())
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
