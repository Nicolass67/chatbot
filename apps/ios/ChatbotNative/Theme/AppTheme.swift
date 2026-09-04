import SwiftUI
import UIKit

/// Nocturne Ink — identité Chatbot 3.1
/// Encre profonde, accent teal signal, typo système hiérarchisée.
/// Glass / material : navigation & contrôles uniquement (jamais le contenu).
enum AppTheme {
    // MARK: - Semantic colors (Light + Dark)

    static let background = Color.cn(light: 0xF3F4F6, dark: 0x0A0B0D)
    static let sidebar = Color.cn(light: 0xECEEF1, dark: 0x101116)
    static let foreground = Color.cn(light: 0x14161A, dark: 0xF0F1F3)
    static let surface = Color.cn(light: 0xFFFFFF, dark: 0x14161A)
    static let surfaceElevated = Color.cn(light: 0xFFFFFF, dark: 0x1B1E24)
    static let surfaceHover = Color.cn(light: 0xE8EAEE, dark: 0x242830)
    static let surfaceActive = Color.cn(light: 0xDDE1E7, dark: 0x2E333C)

    /// Accent signal — teal, distinct du bleu « AI SaaS » générique.
    static let accent = Color.cn(light: 0x0D8F82, dark: 0x3ECFBE)
    static let accentHover = Color.cn(light: 0x0B7A6F, dark: 0x5AD9CB)
    static let accentForeground = Color.cn(light: 0xFFFFFF, dark: 0x06201C)
    static let accentSubtle = accent.opacity(0.14)

    static let muted = Color.cn(light: 0x5C6370, dark: 0xA4A9B4)
    static let mutedForeground = Color.cn(light: 0x8B929E, dark: 0x6E7480)

    static let userMessage = Color.cn(light: 0xE7F5F3, dark: 0x1A2422)
    static let danger = Color.cn(light: 0xC4574E, dark: 0xE08B84)
    static let success = Color.cn(light: 0x2F8F6B, dark: 0x5FCB9A)
    static let warning = Color.cn(light: 0xB07A2E, dark: 0xD4A65A)

    static let border = Color.cn(light: 0xD5D9E0, dark: 0x2F343D)
    static let borderSubtle = Color.cn(light: 0x00000018, dark: 0xFFFFFF12)
    static let glassBorder = Color.cn(light: 0x00000020, dark: 0xFFFFFF28)
    static let codeBg = Color.cn(light: 0xEEF0F3, dark: 0x0C0D10)
    static let assistantBar = accent
    static let ambientCool = Color.cn(light: 0x8AABB8, dark: 0x4A7A88)
    static let ambientWarm = Color.cn(light: 0xC4B5A0, dark: 0x3A342C)

    /// Scopes
    static let mailAccent = Color.cn(light: 0x3B6EA5, dark: 0x6BA3D9)
    static let filesAccent = Color.cn(light: 0x8A6A3D, dark: 0xC4A06A)

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
            let b = CGFloat(hex & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}

/// Fond encre — ambient discret, pas de glow kitsch.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AppTheme.background
            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(scheme == .dark ? 0.10 : 0.09),
                    .clear,
                ],
                center: UnitPoint(x: 0.88, y: 0.02),
                startRadius: 4,
                endRadius: 420
            )
            RadialGradient(
                colors: [
                    AppTheme.ambientWarm.opacity(scheme == .dark ? 0.05 : 0.07),
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
        case "BUSY", "LOADING", "LOADING_MODEL", "SWITCHING": return AppTheme.warning
        case "ERROR", "OFFLINE": return AppTheme.danger
        default: return AppTheme.mutedForeground
        }
    }

    private var label: String {
        switch status.uppercased() {
        case "READY": return "Prêt"
        case "BUSY": return "Occupé"
        case "LOADING", "LOADING_MODEL", "SWITCHING": return "Chargement…"
        case "OFFLINE": return "Aucun modèle"
        case "ERROR": return "Erreur"
        default: return status
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.space8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(CNFont.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppTheme.surfaceElevated.opacity(0.92))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.borderSubtle, lineWidth: 0.5))
    }
}
