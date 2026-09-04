import SwiftUI

/// Graphite Depth — Mobile 2.0 design tokens (ADN Soft Graphite, expression iOS 2026).
enum AppTheme {
    // MARK: - Colors (semantic)
    static let background = Color(hex: 0x121214)
    static let sidebar = Color(hex: 0x1A1A1D)
    static let foreground = Color(hex: 0xE8E8EC)
    static let surface = Color(hex: 0x1F1F23)
    static let surfaceElevated = Color(hex: 0x28282D)
    static let surfaceHover = Color(hex: 0x303036)
    static let surfaceActive = Color(hex: 0x3A3A40)
    static let accent = Color(hex: 0x5B8FD4)
    static let accentHover = Color(hex: 0x74A3E0)
    static let accentForeground = Color(hex: 0xEEF3FA)
    static let accentSubtle = Color(hex: 0x5B8FD4).opacity(0.16)
    static let muted = Color(hex: 0xA8A8B0)
    static let mutedForeground = Color(hex: 0x7A7A84)
    static let userMessage = Color(hex: 0x2C2C32)
    static let danger = Color(hex: 0xD48884)
    static let success = Color(hex: 0x6FBA92)
    static let warning = Color(hex: 0xD0A872)
    static let border = Color(hex: 0x3E3E46)
    static let borderSubtle = Color.white.opacity(0.07)
    static let glassBorder = Color.white.opacity(0.16)
    static let codeBg = Color(hex: 0x0E0E10)
    static let assistantBar = Color(hex: 0x6E6E76)
    static let ambientCool = Color(hex: 0x8A9BB0)

    // MARK: - Spacing (4-pt grid)
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space40: CGFloat = 40
    static let space48: CGFloat = 48

    // MARK: - Radii
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 22
    static let radius2xl: CGFloat = 22
    static let radiusPill: CGFloat = 999

    static let touchMin: CGFloat = 44

    // MARK: - Motion
    static let motionQuick: Double = 0.18
    static let motionStandard: Double = 0.28
    static let motionSheet: Double = 0.36
}

enum CNFont {
    static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.caption
    static let caption2 = Font.caption2
    static let mono = Font.system(.body, design: .monospaced)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// Fond profond — ambient discret (pas de glow kitsch).
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            AppTheme.background
            RadialGradient(
                colors: [AppTheme.accent.opacity(0.12), .clear],
                center: UnitPoint(x: 0.92, y: 0.06),
                startRadius: 8,
                endRadius: 380
            )
            RadialGradient(
                colors: [AppTheme.ambientCool.opacity(0.06), .clear],
                center: UnitPoint(x: 0.12, y: 0.88),
                startRadius: 16,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

/// Chrome glass — navigation / composer / FAB uniquement (jamais contenu message).
/// Mobile 3.0 : préférer glass système (bars) + `glassEffect` custom sur le composer uniquement.
struct ChromeGlass: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.radiusXl
    var opacity: Double = 0.42
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.surface.opacity(opacity))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.glassBorder, lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .blur(radius: 0.4)
                        .mask(
                            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                        )
                }
        }
    }
}

typealias GlassChrome = ChromeGlass

extension View {
    func chromeGlass(cornerRadius: CGFloat = AppTheme.radiusXl, opacity: Double = 0.42) -> some View {
        modifier(ChromeGlass(cornerRadius: cornerRadius, opacity: opacity))
    }

    /// Compat Soft Graphite 0.6
    func glassChrome(cornerRadius: CGFloat = AppTheme.radiusXl, opacity: Double = 0.42) -> some View {
        chromeGlass(cornerRadius: cornerRadius, opacity: opacity)
    }
}

struct RuntimeStatusPill: View {
    let status: String

    private var color: Color {
        switch status.uppercased() {
        case "READY": return AppTheme.success
        case "BUSY", "LOADING", "SWITCHING": return AppTheme.warning
        case "ERROR": return AppTheme.danger
        default: return AppTheme.mutedForeground
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.space8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(status.uppercased())
                .font(CNFont.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppTheme.surfaceElevated.opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.borderSubtle, lineWidth: 1))
    }
}
