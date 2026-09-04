import SwiftUI
import UIKit

/// Ink Indigo — identité premium (recherche 2025/2026 : indigo ardoise + corail mat désaturé).
/// Pas de teal / vert / jaune comme identité principale. Accent indigo cool, surfaces froides.
enum AppTheme {
    // MARK: - Semantic colors (Light + Dark)

    static let background = Color.cn(light: 0xF3F4F8, dark: 0x0E1016)
    static let sidebar = Color.cn(light: 0xE8EAF0, dark: 0x151822)
    static let foreground = Color.cn(light: 0x14161F, dark: 0xE6E8EF)
    static let surface = Color.cn(light: 0xFFFFFF, dark: 0x1A1D28)
    static let surfaceElevated = Color.cn(light: 0xFFFFFF, dark: 0x222633)
    static let surfaceHover = Color.cn(light: 0xE4E7EF, dark: 0x2A2F3E)
    static let surfaceActive = Color.cn(light: 0xD8DCE8, dark: 0x343A4C)

    /// Accent Indigo ardoise — distinct Mist Teal / violet néon / bleu Apple flashy.
    static let accent = Color.cn(light: 0x4A5680, dark: 0x9AA6D4)
    static let accentHover = Color.cn(light: 0x3D476C, dark: 0xB0BAE0)
    static let accentForeground = Color.cn(light: 0xFFFFFF, dark: 0x0E1016)
    static let accentSubtle = accent.opacity(0.14)

    static let muted = Color.cn(light: 0x5A5F70, dark: 0xA0A6B8)
    static let mutedForeground = Color.cn(light: 0x858A9A, dark: 0x6E7488)

    static let userMessage = Color.cn(light: 0xE8EBF5, dark: 0x252A3A)
    static let danger = Color.cn(light: 0xB85C58, dark: 0xC97D79)
    /// Succès sémantique uniquement (pas identité).
    static let success = Color.cn(light: 0x4F7A72, dark: 0x7FA89E)
    /// Alerte froide (ardoise) — jamais jaune / ambre d’identité.
    static let warning = Color.cn(light: 0x6B738A, dark: 0x9AA3B8)

    static let border = Color.cn(light: 0xD0D4E0, dark: 0x2E3344)
    static let borderSubtle = Color.cn(light: 0x00000014, dark: 0xFFFFFF0A)
    static let glassBorder = Color.cn(light: 0x00000018, dark: 0xFFFFFF18)
    static let codeBg = Color.cn(light: 0xEBEDF4, dark: 0x12141C)
    static let assistantBar = accent
    static let ambientCool = Color.cn(light: 0x8A94B8, dark: 0x3A4260)
    /// Chaleur secondaire très désaturée (corail gris) — pas jaune.
    static let ambientWarm = Color.cn(light: 0xA89894, dark: 0x2E2A2C)

    /// Scopes
    static let mailAccent = Color.cn(light: 0x4A6280, dark: 0x8AADC8)
    static let filesAccent = Color.cn(light: 0x7A6A8A, dark: 0xB0A0C0)

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

    /// Adaptive light/dark from hex (alpha nibble optional in light/dark as RGB only).
    static func cn(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat((hex >> 0) & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}

/// Fond Ink Indigo — ambient indigo + corail mat discret.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
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
    }
}

/// Chrome glass — tab / toolbar / composer / FAB uniquement.
struct ChromeGlass: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.radiusXl
    var opacity: Double = 0.55
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
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
        case "READY": return "Assistant prêt"
        case "BUSY": return "Assistant occupé"
        case "LOADING", "LOADING_MODEL": return "Chargement du modèle…"
        case "SWITCHING": return "Changement de modèle…"
        case "OFFLINE": return "Aucun modèle chargé"
        case "ERROR": return "Modèle indisponible"
        default: return status
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.space8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(CNFont.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppTheme.surfaceElevated.opacity(0.92))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.borderSubtle, lineWidth: 0.5))
        .accessibilityLabel(label)
        .accessibilityIdentifier("chat.assistantStatus")
    }
}
