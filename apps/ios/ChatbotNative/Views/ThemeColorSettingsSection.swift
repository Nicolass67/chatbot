import SwiftUI

/// Sélecteur de couleurs thème — une seule carte arrondie, pastilles soignées.
struct ThemeColorSettingsSection: View {
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        Section {
            themeCard
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: {
            Text("Couleurs du thème")
        } footer: {
            Text("Les textes s’adaptent automatiquement au fond. Clair / Sombre utilise la variante de chaque teinte.")
        }
    }

    private var themeCard: some View {
        VStack(spacing: 0) {
            previewBlock
                .padding(16)

            cardDivider

            ThemeSwatchGroup(
                title: "Principale",
                subtitle: appearance.primarySwatch.name,
                accentDot: appearance.primarySwatch.preview,
                swatches: ThemePaletteCatalog.primaries,
                selectedId: appearance.primaryId,
                kind: .accent
            ) { appearance.selectPrimary($0) }
            .padding(16)

            cardDivider

            ThemeSwatchGroup(
                title: "Secondaire",
                subtitle: appearance.secondarySwatch.name,
                accentDot: appearance.secondarySwatch.preview,
                swatches: ThemePaletteCatalog.secondaries,
                selectedId: appearance.secondaryId,
                kind: .accent
            ) { appearance.selectSecondary($0) }
            .padding(16)

            cardDivider

            ThemeSwatchGroup(
                title: "Fond",
                subtitle: appearance.backgroundSwatch.name,
                accentDot: appearance.backgroundSwatch.previewDark,
                swatches: ThemePaletteCatalog.backgrounds,
                selectedId: appearance.backgroundId,
                kind: .background
            ) { appearance.selectBackground($0) }
            .padding(16)

            cardDivider

            Button {
                appearance.resetThemeColors()
            } label: {
                Label("Réinitialiser les couleurs", systemImage: "arrow.counterclockwise")
                    .font(CNFont.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .foregroundStyle(AppTheme.accent)
            .accessibilityIdentifier("settings.theme.reset")
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius2xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radius2xl, style: .continuous)
                .stroke(AppTheme.border.opacity(0.35), lineWidth: 1)
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: appearance.themeRevision)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(AppTheme.border.opacity(0.35))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.accentForeground)
                    }
                    .shadow(color: AppTheme.secondary.opacity(0.35), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Aperçu")
                        .font(CNFont.headline)
                        .foregroundStyle(AppTheme.foreground)
                    Text("Principale · secondaire · fond")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                previewChip("Action", fill: AppTheme.accent, ink: AppTheme.accentForeground)
                previewChip("Secondaire", fill: AppTheme.secondary, ink: AppTheme.secondaryForeground)
                previewChip("Files", fill: AppTheme.secondarySubtle, ink: AppTheme.secondary)
                previewChip("Surface", fill: AppTheme.surfaceElevated, ink: AppTheme.foreground)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.secondarySubtle)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text("A")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.secondary)
                    }
                Text("Message exemple")
                    .font(CNFont.caption.weight(.medium))
                    .foregroundStyle(AppTheme.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.userMessage, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.border.opacity(0.4), lineWidth: 1)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aperçu du thème")
    }

    private func previewChip(_ title: String, fill: Color, ink: Color) -> some View {
        Text(title)
            .font(CNFont.caption2.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(fill, in: Capsule())
    }
}

// MARK: - Group + swatches

private enum ThemeSwatchKind {
    case accent
    case background
}

private struct ThemeSwatchGroup: View {
    let title: String
    let subtitle: String
    let accentDot: Color
    let swatches: [ThemeColorSwatch]
    let selectedId: String
    let kind: ThemeSwatchKind
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Grille régulière 5 colonnes — plus propre que adaptive « 6+4 ».
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(accentDot)
                    .frame(width: 10, height: 10)
                    .shadow(color: accentDot.opacity(0.45), radius: 3, y: 1)

                Text(title)
                    .font(CNFont.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.foreground)

                Spacer(minLength: 8)

                Text(subtitle)
                    .font(CNFont.caption.weight(.medium))
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.background.opacity(0.85), in: Capsule())
                    .lineLimit(1)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(swatches) { swatch in
                    ThemeSwatchChip(
                        swatch: swatch,
                        selected: swatch.id == selectedId,
                        kind: kind,
                        colorScheme: colorScheme
                    ) {
                        onSelect(swatch.id)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct ThemeSwatchChip: View {
    let swatch: ThemeColorSwatch
    let selected: Bool
    let kind: ThemeSwatchKind
    let colorScheme: ColorScheme
    let action: () -> Void

    private var activeHex: UInt32 {
        colorScheme == .dark ? swatch.dark : swatch.light
    }

    private var fill: Color { Color(hex: activeHex) }

    private var checkInk: Color {
        Color(hex: ThemeColorMath.accentInk(on: activeHex))
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                swatchShape
                    .frame(width: 48, height: 48)
                    .shadow(color: fill.opacity(selected ? 0.45 : 0.18), radius: selected ? 8 : 3, y: selected ? 3 : 1)
                    .scaleEffect(selected ? 1.06 : 1.0)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(checkInk)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay {
                if selected {
                    selectionRing
                        .frame(width: 48, height: 48)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.theme.swatch.\(swatch.id)")
    }

    @ViewBuilder
    private var swatchShape: some View {
        switch kind {
        case .accent:
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: swatch.light), Color(hex: swatch.dark)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .background:
            // Split clair | sombre pour voir les deux variantes du fond.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: swatch.dark))
                .overlay {
                    GeometryReader { geo in
                        Path { path in
                            path.move(to: .zero)
                            path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                            path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                            path.closeSubpath()
                        }
                        .fill(Color(hex: swatch.light))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.border.opacity(0.5), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        switch kind {
        case .accent:
            Circle()
                .strokeBorder(AppTheme.foreground.opacity(0.92), lineWidth: 2.5)
        case .background:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.accent, lineWidth: 2.5)
        }
    }
}
