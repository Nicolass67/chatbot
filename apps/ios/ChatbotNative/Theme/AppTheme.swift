import SwiftUI
import UIKit

/// Soft Graphite / Ice Blue — identité premium froide (défaut).
/// Les couleurs sémantiques suivent `ThemePaletteBridge` (réglages utilisateur).
enum AppTheme {
    // MARK: - Semantic colors (Light + Dark) — dynamiques

    private static var p: ResolvedThemePalette { ThemePaletteBridge.current }

    static var background: Color { Color.cn(light: p.bgLight, dark: p.bgDark) }
    static var sidebar: Color { Color.cn(light: p.sidebarLight, dark: p.sidebarDark) }
    static var foreground: Color { Color.cn(light: p.fgLight, dark: p.fgDark) }
    static var surface: Color { Color.cn(light: p.surfaceLight, dark: p.surfaceDark) }
    static var surfaceElevated: Color { Color.cn(light: p.surfaceElevatedLight, dark: p.surfaceElevatedDark) }
    static var surfaceHover: Color { Color.cn(light: p.surfaceHoverLight, dark: p.surfaceHoverDark) }
    static var surfaceActive: Color { Color.cn(light: p.surfaceActiveLight, dark: p.surfaceActiveDark) }

    static var accent: Color { Color.cn(light: p.primaryLight, dark: p.primaryDark) }
    static var accentHover: Color { Color.cn(light: p.primaryHoverLight, dark: p.primaryHoverDark) }
    static var accentForeground: Color { Color.cn(light: p.primaryInkLight, dark: p.primaryInkDark) }
    static var accentSubtle: Color { accent.opacity(0.14) }

    static var muted: Color { Color.cn(light: p.mutedLight, dark: p.mutedDark) }
    static var mutedForeground: Color { Color.cn(light: p.mutedFgLight, dark: p.mutedFgDark) }

    static var userMessage: Color { Color.cn(light: p.userMessageLight, dark: p.userMessageDark) }
    static let danger = Color.cn(light: 0xB85C58, dark: 0xC97D79)
    static let success = Color.cn(light: 0x4F7A72, dark: 0x7FA89E)
    static let warning = Color.cn(light: 0x64748B, dark: 0x94A3B8)

    static var border: Color { Color.cn(light: p.borderLight, dark: p.borderDark) }
    static let borderSubtle = Color.cn(light: 0x00000014, dark: 0xFFFFFF14)
    static var glassBorder: Color {
        Color.cn(light: 0x00000018, dark: 0xFFFFFF22)
    }
    static var codeBg: Color { Color.cn(light: p.codeBgLight, dark: p.codeBgDark) }
    static var assistantBar: Color { accent }
    static var ambientCool: Color { Color.cn(light: p.ambientCoolLight, dark: p.ambientCoolDark) }
    static let ambientWarm = Color.cn(light: 0xA8B0BC, dark: 0x1A222C)

    /// Principale (mail / actions).
    static var mailAccent: Color { accent }
    /// Secondaire (files / accents annexes).
    static var filesAccent: Color { Color.cn(light: p.secondaryLight, dark: p.secondaryDark) }

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
}

private extension UIColor {
    /// Parse 0xRRGGBB (opaque) or 0xRRGGBBAA. Never treat AA as blue (was causing yellow borders in dark).
    static func cnHex(_ hex: UInt32) -> UIColor {
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
                    AppTheme.accent.opacity(scheme == .dark ? 0.10 : 0.08),
                    .clear,
                ],
                center: UnitPoint(x: 0.88, y: 0.02),
                startRadius: 4,
                endRadius: 420
            )
            RadialGradient(
                colors: [
                    AppTheme.ambientCool.opacity(scheme == .dark ? 0.06 : 0.05),
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
                        .stroke(AppTheme.borderSubtle, lineWidth: 1)
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
                        .stroke(AppTheme.glassBorder, lineWidth: 0.75)
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

struct RuntimeStatusPill: View {
    let status: String

    private var color: Color {
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
        HStack(spacing: AppTheme.space8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(AppTheme.surfaceElevated.opacity(0.92))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.borderSubtle, lineWidth: 0.5))
        .accessibilityLabel(label)
        .accessibilityIdentifier("chat.assistantStatus")
    }
}
