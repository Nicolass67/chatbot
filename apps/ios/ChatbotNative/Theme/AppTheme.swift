import SwiftUI
import UIKit

/// Soft Graphite / Ice Blue — identité premium froide (défaut).
/// Les couleurs sémantiques suivent `ThemePaletteBridge` (réglages utilisateur).
enum AppTheme {
    // MARK: - Semantic colors (Light + Dark) — dynamiques

    /// Couleurs palette : résolution live (suit ThemePaletteBridge sans hex figé).
    static var background: Color { Color.cnLive(light: \.bgLight, dark: \.bgDark) }
    static var sidebar: Color { Color.cnLive(light: \.sidebarLight, dark: \.sidebarDark) }
    static var foreground: Color { Color.cnLive(light: \.fgLight, dark: \.fgDark) }
    static var surface: Color { Color.cnLive(light: \.surfaceLight, dark: \.surfaceDark) }
    static var surfaceElevated: Color { Color.cnLive(light: \.surfaceElevatedLight, dark: \.surfaceElevatedDark) }
    static var surfaceHover: Color { Color.cnLive(light: \.surfaceHoverLight, dark: \.surfaceHoverDark) }
    static var surfaceActive: Color { Color.cnLive(light: \.surfaceActiveLight, dark: \.surfaceActiveDark) }

    static var accent: Color { Color.cnLive(light: \.primaryLight, dark: \.primaryDark) }
    static var accentHover: Color { Color.cnLive(light: \.primaryHoverLight, dark: \.primaryHoverDark) }
    static var accentForeground: Color { Color.cnLive(light: \.primaryInkLight, dark: \.primaryInkDark) }
    static var accentSubtle: Color { accent.opacity(0.14) }

    /// Couleur secondaire du thème (réglages) — accents annexes, sources, fichiers, thinking.
    static var secondary: Color { Color.cnLive(light: \.secondaryLight, dark: \.secondaryDark) }
    static var secondarySubtle: Color { secondary.opacity(0.16) }
    static var secondaryForeground: Color { Color.cnLive(light: \.primaryInkLight, dark: \.primaryInkDark) }

    static var muted: Color { Color.cnLive(light: \.mutedLight, dark: \.mutedDark) }
    static var mutedForeground: Color { Color.cnLive(light: \.mutedFgLight, dark: \.mutedFgDark) }

    static var userMessage: Color { Color.cnLive(light: \.userMessageLight, dark: \.userMessageDark) }
    static let danger = Color.cn(light: 0xB85C58, dark: 0xC97D79)
    static let success = Color.cn(light: 0x4F7A72, dark: 0x7FA89E)
    static let warning = Color.cn(light: 0x64748B, dark: 0x94A3B8)

    static var border: Color { Color.cnLive(light: \.borderLight, dark: \.borderDark) }
    /// Séparateurs / traits secondaires — transparent en clair (plus de contours noirs).
    static let borderSubtle = Color.cn(light: 0x00000000, dark: 0xFFFFFF14)
    /// Contour glass chrome (composer, FAB, dock) — invisible en clair.
    static var glassBorder: Color {
        Color.cn(light: 0x00000000, dark: 0xFFFFFF1E)
    }
    /// Trait de contour UI : désactivé en clair, léger en sombre.
    static var chromeStroke: Color {
        Color.cn(light: 0x00000000, dark: 0xFFFFFF18)
    }
    /// Pastilles / chips : pas de trait en clair, hairline en sombre.
    static var chipStroke: Color {
        Color.cn(light: 0x00000000, dark: 0xFFFFFF16)
    }
    static var codeBg: Color { Color.cnLive(light: \.codeBgLight, dark: \.codeBgDark) }
    /// Barre assistant : mélange primaire → secondaire pour ancrer les deux teintes.
    static var assistantBar: Color { secondary }
    static var ambientCool: Color { Color.cnLive(light: \.ambientCoolLight, dark: \.ambientCoolDark) }
    static let ambientWarm = Color.cn(light: 0xA8B0BC, dark: 0x1A222C)

    /// Principale (mail / actions).
    static var mailAccent: Color { accent }
    /// Secondaire (files / accents annexes) — alias de `secondary`.
    static var filesAccent: Color { secondary }

    // MARK: - Spacing (4-pt)

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space14: CGFloat = 14
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space40: CGFloat = 40
    static let space48: CGFloat = 48
    static let space64: CGFloat = 64

    // MARK: - Radii

    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 22
    static let radius2xl: CGFloat = 28
    static let radiusPill: CGFloat = 999

    static let touchMin: CGFloat = 44

    // MARK: - Motion

    static let motionQuick: Double = 0.18
    static let motionStandard: Double = 0.28
    static let motionSheet: Double = 0.36
    static let motionSettle: Double = 0.48
}

/// Typographie Dynamic Type — hiérarchie courte et intentionnelle.
enum CNFont {
    static let display = Font.system(.largeTitle, design: .default).weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline.weight(.semibold)
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.caption
    static let caption2 = Font.caption2
    static let mono = Font.system(.body, design: .monospaced)
    /// Marque / empty hero uniquement.
    static let brand = Font.system(size: 34, weight: .bold, design: .serif)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// Adaptive light/dark. Accepts 0xRRGGBB or 0xRRGGBBAA (alpha in low byte).
    static func cn(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor.cnHex(hex)
        })
    }

    /// Lit ThemePaletteBridge.current au moment du rendu (suit le thème app).
    static func cnLive(
        light: KeyPath<ResolvedThemePalette, UInt32>,
        dark: KeyPath<ResolvedThemePalette, UInt32>
    ) -> Color {
        Color(UIColor { traits in
            let palette = ThemePaletteBridge.current
            let hex = traits.userInterfaceStyle == .dark
                ? palette[keyPath: dark]
                : palette[keyPath: light]
            return UIColor.cnHex(hex)
        })
    }
}

private extension UIColor {
    /// Parse 0xRRGGBB (opaque) or 0xRRGGBBAA. Never treat AA as blue (was causing yellow borders in dark).
    /// `0` = transparent (les tokens « pas de trait » en clair), pas du noir opaque.
    static func cnHex(_ hex: UInt32) -> UIColor {
        if hex == 0 {
            return .clear
        }
        if hex > 0x00FF_FFFF {
            let r = CGFloat((hex >> 24) & 0xFF) / 255
            let g = CGFloat((hex >> 16) & 0xFF) / 255
            let b = CGFloat((hex >> 8) & 0xFF) / 255
            let a = CGFloat(hex & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

extension EnvironmentValues {
    /// Révision palette thème — invalide les fonds / chrome sans remount navigation.
    var themeRevision: Int {
        get { self[ThemeRevisionKey.self] }
        set { self[ThemeRevisionKey.self] = newValue }
    }
}

private struct ThemeRevisionKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

/// Fond Ice Blue — ambient bleu clair moderne.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.themeRevision) private var themeRevision

    var body: some View {
        let _ = themeRevision
        ZStack {
            AppTheme.background
            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(scheme == .dark ? 0.11 : 0.09),
                    .clear,
                ],
                center: UnitPoint(x: 0.88, y: 0.02),
                startRadius: 4,
                endRadius: 420
            )
            RadialGradient(
                colors: [
                    AppTheme.secondary.opacity(scheme == .dark ? 0.14 : 0.11),
                    .clear,
                ],
                center: UnitPoint(x: 0.12, y: 0.78),
                startRadius: 8,
                endRadius: 460
            )
            RadialGradient(
                colors: [
                    AppTheme.ambientCool.opacity(scheme == .dark ? 0.08 : 0.07),
                    .clear,
                ],
                center: UnitPoint(x: 0.08, y: 0.95),
                startRadius: 20,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Chrome glass — tab / toolbar / composer / FAB uniquement.
struct ChromeGlass: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.radiusXl
    var opacity: Double = 0.55
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.themeRevision) private var themeRevision

    func body(content: Content) -> some View {
        let _ = themeRevision
        if reduceTransparency {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.chromeStroke, lineWidth: 0.5)
                )
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(AppTheme.surface.opacity(scheme == .dark ? opacity * 0.35 : 0.55))
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.chromeStroke, lineWidth: scheme == .dark ? 0.75 : 0)
                )
        }
    }
}

typealias GlassChrome = ChromeGlass

extension View {
    func chromeGlass(cornerRadius: CGFloat = AppTheme.radiusXl, opacity: Double = 0.55) -> some View {
        modifier(ChromeGlass(cornerRadius: cornerRadius, opacity: opacity))
    }

    func glassChrome(cornerRadius: CGFloat = AppTheme.radiusXl, opacity: Double = 0.55) -> some View {
        chromeGlass(cornerRadius: cornerRadius, opacity: opacity)
    }
}


/// Force le recalcul des vues qui peignent AppTheme.* après un changement de palette.
private struct AppThemeSyncModifier: ViewModifier {
    @Environment(\.themeRevision) private var themeRevision

    func body(content: Content) -> some View {
        let _ = themeRevision
        content
    }
}

extension View {
    /// À appliquer sur les écrans / composants qui affichent l'accent.
    func syncsAppTheme() -> some View {
        modifier(AppThemeSyncModifier())
    }
}

struct RuntimeStatusPill: View {
    let status: String
    @Environment(\.themeRevision) private var themeRevision

    private var color: Color {
        let _ = themeRevision
        switch status.uppercased() {
        case "READY": return AppTheme.accent
        case "BUSY", "LOADING", "LOADING_MODEL", "SWITCHING": return AppTheme.accent.opacity(0.85)
        case "ERROR", "OFFLINE": return AppTheme.danger
        default: return AppTheme.mutedForeground
        }
    }

    private var label: String {
        switch status.uppercased() {
        case "READY": return "Disponible"
        case "BUSY": return "En cours de réponse…"
        case "LOADING", "LOADING_MODEL": return "Chargement du modèle…"
        case "SWITCHING": return "Changement de modèle…"
        case "OFFLINE": return "Aucun modèle chargé"
        case "ERROR": return "Modèle indisponible"
        default: return status
        }
    }

    var body: some View {
        let _ = themeRevision
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityLabel(label)
        .accessibilityIdentifier("chat.assistantStatus")
    }
}

