import SwiftUI
import UIKit

// MARK: - Swatches

struct ThemeColorSwatch: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Hex 0xRRGGBB — mode clair.
    let light: UInt32
    /// Hex 0xRRGGBB — mode sombre.
    let dark: UInt32

    var preview: Color { Color(hex: light) }
    var previewDark: Color { Color(hex: dark) }
}

enum ThemePaletteCatalog {
    /// Défauts = palette Soft Graphite / Ice Blue actuelle.
    static let defaultPrimaryId = "ice-blue"
    static let defaultSecondaryId = "cyan"
    static let defaultBackgroundId = "graphite"

    /// Couleurs principales (accents boutons, tabs, CTA).
    static let primaries: [ThemeColorSwatch] = [
        .init(id: "ice-blue", name: "Bleu glacier", light: 0x3B82F6, dark: 0x7DD3FC),
        .init(id: "indigo", name: "Indigo", light: 0x6366F1, dark: 0xA5B4FC),
        .init(id: "violet", name: "Violet", light: 0x8B5CF6, dark: 0xC4B5FD),
        .init(id: "rose", name: "Rose", light: 0xE11D48, dark: 0xFB7185),
        .init(id: "orange", name: "Orange", light: 0xEA580C, dark: 0xFB923C),
        .init(id: "emerald", name: "Émeraude", light: 0x059669, dark: 0x34D399),
        .init(id: "teal", name: "Sarcelle", light: 0x0D9488, dark: 0x2DD4BF),
        .init(id: "sky", name: "Ciel", light: 0x0284C7, dark: 0x38BDF8),
        .init(id: "slate", name: "Ardoise", light: 0x475569, dark: 0x94A3B8),
        .init(id: "gold", name: "Or doux", light: 0xB45309, dark: 0xFBBF24),
        // Nouvelles
        .init(id: "cobalt", name: "Cobalt", light: 0x2563EB, dark: 0x60A5FA),
        .init(id: "electric", name: "Électrique", light: 0x4F46E5, dark: 0x818CF8),
        .init(id: "fuchsia", name: "Fuchsia", light: 0xC026D3, dark: 0xE879F9),
        .init(id: "crimson", name: "Cramoisi", light: 0xBE123C, dark: 0xFB7185),
        .init(id: "terracotta", name: "Terracotta", light: 0xC2410C, dark: 0xFB923C),
        .init(id: "saffron", name: "Safran", light: 0xCA8A04, dark: 0xFACC15),
        .init(id: "jade", name: "Jade", light: 0x047857, dark: 0x34D399),
        .init(id: "aqua", name: "Aqua", light: 0x0891B2, dark: 0x22D3EE),
        .init(id: "arctic", name: "Arctique", light: 0x0E7490, dark: 0x67E8F9),
        .init(id: "charcoal", name: "Charbon", light: 0x334155, dark: 0xE2E8F0),
    ]

    /// Couleurs secondaires (accents Files, ambient, highlights).
    static let secondaries: [ThemeColorSwatch] = [
        .init(id: "cyan", name: "Cyan", light: 0x0EA5E9, dark: 0x67E8F9),
        .init(id: "mint", name: "Menthe", light: 0x10B981, dark: 0x6EE7B7),
        .init(id: "lavender", name: "Lavande", light: 0x7C3AED, dark: 0xC4B5FD),
        .init(id: "coral", name: "Corail", light: 0xF43F5E, dark: 0xFDA4AF),
        .init(id: "amber", name: "Ambre", light: 0xD97706, dark: 0xFCD34D),
        .init(id: "lime", name: "Citron vert", light: 0x65A30D, dark: 0xA3E635),
        .init(id: "blue-soft", name: "Bleu doux", light: 0x60A5FA, dark: 0x93C5FD),
        .init(id: "magenta", name: "Magenta", light: 0xDB2777, dark: 0xF9A8D4),
        .init(id: "steel", name: "Acier", light: 0x64748B, dark: 0xCBD5E1),
        .init(id: "peach", name: "Pêche", light: 0xE07A5F, dark: 0xF4A261),
        // Nouvelles
        .init(id: "periwinkle", name: "Pervenche", light: 0x818CF8, dark: 0xA5B4FC),
        .init(id: "orchid", name: "Orchidée", light: 0xA855F7, dark: 0xD8B4FE),
        .init(id: "flamingo", name: "Flamant", light: 0xEC4899, dark: 0xF9A8D4),
        .init(id: "tangerine", name: "Tangerine", light: 0xF97316, dark: 0xFDBA74),
        .init(id: "honey", name: "Miel", light: 0xEAB308, dark: 0xFDE047),
        .init(id: "spring", name: "Printemps", light: 0x84CC16, dark: 0xBEF264),
        .init(id: "seafoam", name: "Écume", light: 0x14B8A6, dark: 0x5EEAD4),
        .init(id: "glacier", name: "Glacier", light: 0x38BDF8, dark: 0x7DD3FC),
        .init(id: "denim", name: "Denim", light: 0x3B82F6, dark: 0x93C5FD),
        .init(id: "smoke", name: "Fumée", light: 0x94A3B8, dark: 0xE2E8F0),
    ]

    /// Familles de fond (clair + sombre dérivés).
    static let backgrounds: [ThemeColorSwatch] = [
        .init(id: "graphite", name: "Graphite", light: 0xF3F5F9, dark: 0x0B0F14),
        .init(id: "pure", name: "Blanc / Noir", light: 0xFFFFFF, dark: 0x000000),
        .init(id: "silver", name: "Argent", light: 0xECEFF3, dark: 0x14181E),
        .init(id: "slate-bg", name: "Ardoise", light: 0xE8EDF4, dark: 0x0F172A),
        .init(id: "navy", name: "Bleu nuit", light: 0xE8EEF8, dark: 0x0A1628),
        .init(id: "ocean", name: "Océan", light: 0xE6F2F5, dark: 0x0B1C22),
        .init(id: "cyan-mist", name: "Brume cyan", light: 0xE8F7F8, dark: 0x0C1A1C),
        .init(id: "beige", name: "Beige", light: 0xF5F0E8, dark: 0x1A1712),
        .init(id: "sand", name: "Sable", light: 0xF3EDE4, dark: 0x1C1810),
        .init(id: "mocha", name: "Mocha", light: 0xF0E9E2, dark: 0x1A1410),
        .init(id: "forest", name: "Forêt", light: 0xEAF2EC, dark: 0x0C1610),
        .init(id: "plum", name: "Prune", light: 0xF0EAF2, dark: 0x140F18),
        // Nouvelles
        .init(id: "ink", name: "Encre", light: 0xEEF1F6, dark: 0x070A0F),
        .init(id: "midnight", name: "Minuit", light: 0xE9ECF4, dark: 0x080B14),
        .init(id: "twilight", name: "Crépuscule", light: 0xECE8F4, dark: 0x100E1A),
        .init(id: "aurora", name: "Aurore", light: 0xE8F4F0, dark: 0x0A1614),
        .init(id: "lagoon", name: "Lagon", light: 0xE4F3F6, dark: 0x071820),
        .init(id: "pine", name: "Pin", light: 0xE7F0EA, dark: 0x0A120E),
        .init(id: "wine", name: "Vin", light: 0xF3E9EC, dark: 0x160A10),
        .init(id: "ember", name: "Braise", light: 0xF5EBE6, dark: 0x160E0A),
        .init(id: "olive", name: "Olive", light: 0xEEF0E6, dark: 0x12140C),
        .init(id: "stone", name: "Pierre", light: 0xF0EEEA, dark: 0x121110),
        .init(id: "fog", name: "Brouillard", light: 0xF2F4F7, dark: 0x101418),
        .init(id: "dusk", name: "Pénombre", light: 0xEDEAF2, dark: 0x0E0C14),
    ]

    static func primary(id: String) -> ThemeColorSwatch {
        primaries.first { $0.id == id } ?? primaries[0]
    }

    static func secondary(id: String) -> ThemeColorSwatch {
        secondaries.first { $0.id == id } ?? secondaries[0]
    }

    static func background(id: String) -> ThemeColorSwatch {
        backgrounds.first { $0.id == id } ?? backgrounds[0]
    }
}

// MARK: - Contrast / derived colors

enum ThemeColorMath {
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255.0
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = channel((hex >> 16) & 0xFF)
        let g = channel((hex >> 8) & 0xFF)
        let b = channel(hex & 0xFF)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    static func isDark(_ hex: UInt32) -> Bool {
        relativeLuminance(hex) < 0.42
    }

    /// Texte lisible sur `hex` (noir ou blanc légèrement teinté).
    static func contrastingInk(on hex: UInt32) -> UInt32 {
        isDark(hex) ? 0xE8EEF6 : 0x12161E
    }

    static func mutedInk(on hex: UInt32) -> UInt32 {
        isDark(hex) ? 0x9AA8BC : 0x5A6478
    }

    static func mutedForeground(on hex: UInt32) -> UInt32 {
        isDark(hex) ? 0x6B7A90 : 0x8490A4
    }

    static func mix(_ a: UInt32, _ b: UInt32, t: Double) -> UInt32 {
        let t = min(1, max(0, t))
        func ch(_ hex: UInt32, shift: UInt32) -> Double {
            Double((hex >> shift) & 0xFF)
        }
        let r = Int(ch(a, shift: 16) * (1 - t) + ch(b, shift: 16) * t)
        let g = Int(ch(a, shift: 8) * (1 - t) + ch(b, shift: 8) * t)
        let bl = Int(ch(a, shift: 0) * (1 - t) + ch(b, shift: 0) * t)
        return UInt32((r << 16) | (g << 8) | bl)
    }

    static func elevate(_ bg: UInt32, amount: Double) -> UInt32 {
        let toward: UInt32 = isDark(bg) ? 0xFFFFFF : 0x000000
        // Surfaces : un peu plus claires en dark, un peu plus « carte » en light (vers blanc).
        if isDark(bg) {
            return mix(bg, toward, t: amount)
        }
        return mix(bg, 0xFFFFFF, t: min(1, amount * 1.4))
    }

    static func hover(_ bg: UInt32) -> UInt32 {
        let toward: UInt32 = isDark(bg) ? 0xFFFFFF : 0x000000
        return mix(bg, toward, t: isDark(bg) ? 0.12 : 0.06)
    }

    static func border(on bg: UInt32) -> UInt32 {
        let toward: UInt32 = isDark(bg) ? 0xFFFFFF : 0x000000
        // Clair : quasi invisible (0.03) — les strokes UI utilisent chromeStroke / chipStroke.
        return mix(bg, toward, t: isDark(bg) ? 0.18 : 0.03)
    }

    static func accentInk(on accent: UInt32) -> UInt32 {
        isDark(accent) ? 0xE8EEF6 : 0xFFFFFF
    }

    static func tintedSurface(bg: UInt32, accent: UInt32, amount: Double) -> UInt32 {
        mix(elevate(bg, amount: 0.08), accent, t: amount)
    }
}

/// Snapshot résolu consommé par `AppTheme` (mis à jour par `AppearanceStore`).
struct ResolvedThemePalette: Equatable, Sendable {
    var primaryLight: UInt32
    var primaryDark: UInt32
    var primaryHoverLight: UInt32
    var primaryHoverDark: UInt32
    var primaryInkLight: UInt32
    var primaryInkDark: UInt32

    var secondaryLight: UInt32
    var secondaryDark: UInt32

    var bgLight: UInt32
    var bgDark: UInt32
    var sidebarLight: UInt32
    var sidebarDark: UInt32
    var surfaceLight: UInt32
    var surfaceDark: UInt32
    var surfaceElevatedLight: UInt32
    var surfaceElevatedDark: UInt32
    var surfaceHoverLight: UInt32
    var surfaceHoverDark: UInt32
    var surfaceActiveLight: UInt32
    var surfaceActiveDark: UInt32

    var fgLight: UInt32
    var fgDark: UInt32
    var mutedLight: UInt32
    var mutedDark: UInt32
    var mutedFgLight: UInt32
    var mutedFgDark: UInt32

    var userMessageLight: UInt32
    var userMessageDark: UInt32
    var borderLight: UInt32
    var borderDark: UInt32
    var codeBgLight: UInt32
    var codeBgDark: UInt32
    var ambientCoolLight: UInt32
    var ambientCoolDark: UInt32

    static func resolve(primaryId: String, secondaryId: String, backgroundId: String) -> ResolvedThemePalette {
        let primary = ThemePaletteCatalog.primary(id: primaryId)
        let secondary = ThemePaletteCatalog.secondary(id: secondaryId)
        let background = ThemePaletteCatalog.background(id: backgroundId)

        let bgL = background.light
        let bgD = background.dark

        return ResolvedThemePalette(
            primaryLight: primary.light,
            primaryDark: primary.dark,
            primaryHoverLight: ThemeColorMath.mix(primary.light, 0x000000, t: 0.12),
            primaryHoverDark: ThemeColorMath.mix(primary.dark, 0xFFFFFF, t: 0.18),
            primaryInkLight: ThemeColorMath.accentInk(on: primary.light),
            primaryInkDark: ThemeColorMath.accentInk(on: primary.dark),
            secondaryLight: secondary.light,
            secondaryDark: secondary.dark,
            bgLight: bgL,
            bgDark: bgD,
            sidebarLight: ThemeColorMath.mix(bgL, 0x000000, t: 0.04),
            sidebarDark: ThemeColorMath.elevate(bgD, amount: 0.05),
            surfaceLight: ThemeColorMath.elevate(bgL, amount: 0.85),
            surfaceDark: ThemeColorMath.elevate(bgD, amount: 0.07),
            surfaceElevatedLight: ThemeColorMath.elevate(bgL, amount: 0.95),
            surfaceElevatedDark: ThemeColorMath.elevate(bgD, amount: 0.11),
            surfaceHoverLight: ThemeColorMath.hover(bgL),
            surfaceHoverDark: ThemeColorMath.hover(bgD),
            surfaceActiveLight: ThemeColorMath.mix(bgL, 0x000000, t: 0.10),
            surfaceActiveDark: ThemeColorMath.elevate(bgD, amount: 0.16),
            fgLight: ThemeColorMath.contrastingInk(on: bgL),
            fgDark: ThemeColorMath.contrastingInk(on: bgD),
            mutedLight: ThemeColorMath.mutedInk(on: bgL),
            mutedDark: ThemeColorMath.mutedInk(on: bgD),
            mutedFgLight: ThemeColorMath.mutedForeground(on: bgL),
            mutedFgDark: ThemeColorMath.mutedForeground(on: bgD),
            userMessageLight: ThemeColorMath.tintedSurface(bg: bgL, accent: primary.light, amount: 0.12),
            userMessageDark: ThemeColorMath.tintedSurface(bg: bgD, accent: primary.dark, amount: 0.16),
            borderLight: ThemeColorMath.border(on: bgL),
            borderDark: ThemeColorMath.border(on: bgD),
            codeBgLight: ThemeColorMath.mix(bgL, 0x000000, t: 0.05),
            codeBgDark: ThemeColorMath.mix(bgD, 0x000000, t: 0.25),
            ambientCoolLight: ThemeColorMath.mix(secondary.light, 0xFFFFFF, t: 0.35),
            ambientCoolDark: ThemeColorMath.mix(secondary.dark, bgD, t: 0.55)
        )
    }

    static let `default` = resolve(
        primaryId: ThemePaletteCatalog.defaultPrimaryId,
        secondaryId: ThemePaletteCatalog.defaultSecondaryId,
        backgroundId: ThemePaletteCatalog.defaultBackgroundId
    )
}

/// Source de vérité lue par `AppTheme` (mise à jour sur le main thread).
enum ThemePaletteBridge {
    nonisolated(unsafe) static var current: ResolvedThemePalette = .default
}
