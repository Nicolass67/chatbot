import SwiftUI

/// Sélecteur de couleurs thème — grilles de pastilles + aperçu live.
struct ThemeColorSettingsSection: View {
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        Section {
            themePreviewCard
                .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                .listRowBackground(Color.clear)

            ThemeSwatchPickerRow(
                title: "Principale",
                subtitle: appearance.primarySwatch.name,
                swatches: ThemePaletteCatalog.primaries,
                selectedId: appearance.primaryId,
                style: .accent
            ) { appearance.selectPrimary($0) }

            ThemeSwatchPickerRow(
                title: "Secondaire",
                subtitle: appearance.secondarySwatch.name,
                swatches: ThemePaletteCatalog.secondaries,
                selectedId: appearance.secondaryId,
                style: .accent
            ) { appearance.selectSecondary($0) }

            ThemeSwatchPickerRow(
                title: "Fond",
                subtitle: appearance.backgroundSwatch.name,
                swatches: ThemePaletteCatalog.backgrounds,
                selectedId: appearance.backgroundId,
                style: .background
            ) { appearance.selectBackground($0) }

            Button {
                appearance.resetThemeColors()
            } label: {
                Label("Réinitialiser les couleurs", systemImage: "arrow.counterclockwise")
                    .font(CNFont.callout.weight(.medium))
            }
            .foregroundStyle(AppTheme.accent)
            .accessibilityIdentifier("settings.theme.reset")
        } header: {
            Text("Couleurs du thème")
        } footer: {
            Text("Les textes s’adaptent automatiquement au fond pour rester lisibles. Clair / Sombre utilise la variante de chaque teinte.")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var themePreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppTheme.accentForeground)
                    }
                VStack(alignment: .leading, spacing: 2) {
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
                previewChip("Files", fill: AppTheme.filesAccent.opacity(0.22), ink: AppTheme.filesAccent)
                previewChip("Surface", fill: AppTheme.surfaceElevated, ink: AppTheme.foreground)
            }

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.userMessage)
                .frame(height: 36)
                .overlay(alignment: .leading) {
                    Text("Message exemple")
                        .font(CNFont.caption.weight(.medium))
                        .foregroundStyle(AppTheme.foreground)
                        .padding(.horizontal, 12)
                }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .fill(AppTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                        .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aperçu du thème")
    }

    private func previewChip(_ title: String, fill: Color, ink: Color) -> some View {
        Text(title)
            .font(CNFont.caption2.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(fill, in: Capsule())
    }
}

private enum ThemeSwatchPickerStyle {
    case accent
    case background
}

private struct ThemeSwatchPickerRow: View {
    let title: String
    let subtitle: String
    let swatches: [ThemeColorSwatch]
    let selectedId: String
    let style: ThemeSwatchPickerStyle
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(CNFont.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.foreground)
                Spacer(minLength: 8)
                Text(subtitle)
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(swatches) { swatch in
                    ThemeSwatchButton(
                        swatch: swatch,
                        selected: swatch.id == selectedId,
                        style: style,
                        colorScheme: colorScheme
                    ) {
                        onSelect(swatch.id)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct ThemeSwatchButton: View {
    let swatch: ThemeColorSwatch
    let selected: Bool
    let style: ThemeSwatchPickerStyle
    let colorScheme: ColorScheme
    let action: () -> Void

    private var fillHex: UInt32 {
        colorScheme == .dark ? swatch.dark : swatch.light
    }

    private var fill: Color { Color(hex: fillHex) }

    private var checkInk: Color {
        Color(hex: ThemeColorMath.accentInk(on: fillHex))
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if style == .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fill)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.border.opacity(0.45), lineWidth: 1)
                        )
                } else {
                    Circle()
                        .fill(fill)
                        .frame(width: 44, height: 44)
                        .shadow(color: fill.opacity(0.35), radius: selected ? 6 : 2, y: 2)
                }

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(checkInk)
                }
            }
            .overlay {
                if selected {
                    Group {
                        if style == .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.accent, lineWidth: 2.5)
                        } else {
                            Circle()
                                .stroke(AppTheme.foreground.opacity(0.85), lineWidth: 2.5)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: AppTheme.touchMin, minHeight: AppTheme.touchMin)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.theme.swatch.\(swatch.id)")
    }
}
