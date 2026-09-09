import SwiftUI

/// Bannière fine — mode d’exécution (IA locale / PC indisponible).
struct ExecutionModeBanner: View {
    let label: String
    var systemImage: String = "cpu"

    @Environment(\.themeRevision) private var themeRevision

    var body: some View {
        let _ = themeRevision
        HStack(spacing: AppTheme.space8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text(label)
                .font(CNFont.caption.weight(.medium))
                .foregroundStyle(AppTheme.foreground)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.space12)
        .padding(.vertical, AppTheme.space8)
        .background(AppTheme.surfaceElevated.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
