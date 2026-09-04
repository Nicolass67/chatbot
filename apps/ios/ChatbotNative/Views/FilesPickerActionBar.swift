import SwiftUI

/// Barre d’action compacte pour les sélecteurs Files (Enregistrer / Déplacer).
/// Évite le gros bouton pleine largeur — layout type dock : infos à gauche, CTA à droite.
struct FilesPickerActionBar: View {
    let title: String
    let subtitle: String
    var detail: String? = nil
    let systemImage: String
    var tint: Color = AppTheme.accent
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(AppTheme.borderSubtle)

            HStack(alignment: .center, spacing: AppTheme.space12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.14))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subtitle)
                        .font(CNFont.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: action) {
                    Group {
                        if busy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(AppTheme.accentForeground)
                        } else {
                            Text(title)
                                .font(CNFont.callout.weight(.semibold))
                        }
                    }
                    .foregroundStyle(AppTheme.accentForeground)
                    .padding(.horizontal, AppTheme.space14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint)
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel(title)
            }
            .padding(.horizontal, AppTheme.space14)
            .padding(.vertical, AppTheme.space10)
        }
        .background(.ultraThinMaterial)
    }
}
