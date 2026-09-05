import SwiftUI
import UIKit
import Combine

/// Préférence d’apparence persistée — Clair / Sombre / Système.
enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Système"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var uiUserInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// `preferredColorScheme` sur une sheet iOS ne se réapplique souvent qu’une fois.
/// On force aussi `overrideUserInterfaceStyle` sur la chaîne de VC (couleurs `UIColor` dynamiques).
struct InterfaceStyleBridge: UIViewRepresentable {
    var style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let apply = { [style] in
            guard let start = uiView.findHostingViewController() else { return }
            var node: UIViewController? = start
            while let current = node {
                current.overrideUserInterfaceStyle = style
                node = current.parent
            }
            start.navigationController?.overrideUserInterfaceStyle = style
            var root = start
            while let parent = root.parent {
                root = parent
            }
            root.overrideUserInterfaceStyle = style
            root.setNeedsStatusBarAppearanceUpdate()
        }
        if Thread.isMainThread {
            apply()
            DispatchQueue.main.async(execute: apply)
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

private extension UIView {
    func findHostingViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

extension View {
    /// Apparence sheet — chaîne de modifiers **fixe** (pas de `switch` ViewBuilder).
    /// Le vrai basculement Clair/Sombre passe par `AppearanceStore.applyWindowInterfaceStyle`
    /// pour éviter le remount de NavigationStack.
    func chatbotSheetAppearance(_ mode: AppAppearanceMode) -> some View {
        background(InterfaceStyleBridge(style: mode.uiUserInterfaceStyle))
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    private static let modeKey = "appAppearanceMode"
    private static let primaryKey = "themePrimaryId"
    private static let secondaryKey = "themeSecondaryId"
    private static let backgroundKey = "themeBackgroundId"

    @Published var mode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            // UIKit window : change Clair/Sombre sans remount SwiftUI (preferredColorScheme
            // sur WindowGroup / sheet reconstruit parfois NavigationStack).
            Self.applyWindowInterfaceStyle(mode.uiUserInterfaceStyle)
        }
    }

    @Published var primaryId: String {
        didSet { persistPalette() }
    }

    @Published var secondaryId: String {
        didSet { persistPalette() }
    }

    @Published var backgroundId: String {
        didSet { persistPalette() }
    }

    /// Incrémenté à chaque changement de palette (les vues qui le lisent se rafraîchissent
    /// sans détruire la navigation / les sheets — ne jamais l’utiliser comme `.id` racine).
    @Published private(set) var themeRevision: Int = 0

    private var isHydrating = true

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let parsed = AppAppearanceMode(rawValue: raw)
        {
            mode = parsed
        } else {
            mode = .system
        }

        let primary = UserDefaults.standard.string(forKey: Self.primaryKey)
            ?? ThemePaletteCatalog.defaultPrimaryId
        let secondary = UserDefaults.standard.string(forKey: Self.secondaryKey)
            ?? ThemePaletteCatalog.defaultSecondaryId
        let background = UserDefaults.standard.string(forKey: Self.backgroundKey)
            ?? ThemePaletteCatalog.defaultBackgroundId

        primaryId = ThemePaletteCatalog.primaries.contains(where: { $0.id == primary })
            ? primary : ThemePaletteCatalog.defaultPrimaryId
        secondaryId = ThemePaletteCatalog.secondaries.contains(where: { $0.id == secondary })
            ? secondary : ThemePaletteCatalog.defaultSecondaryId
        backgroundId = ThemePaletteCatalog.backgrounds.contains(where: { $0.id == background })
            ? background : ThemePaletteCatalog.defaultBackgroundId

        isHydrating = false
        applyPaletteToBridge(bumpRevision: false)
        Self.applyWindowInterfaceStyle(mode.uiUserInterfaceStyle)
    }

    /// Applique Clair/Sombre au niveau fenêtre — pas de reconstruction de hiérarchie SwiftUI.
    static func applyWindowInterfaceStyle(_ style: UIUserInterfaceStyle) {
        let apply = {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    var primarySwatch: ThemeColorSwatch { ThemePaletteCatalog.primary(id: primaryId) }
    var secondarySwatch: ThemeColorSwatch { ThemePaletteCatalog.secondary(id: secondaryId) }
    var backgroundSwatch: ThemeColorSwatch { ThemePaletteCatalog.background(id: backgroundId) }

    func selectPrimary(_ id: String) {
        guard primaryId != id else { return }
        primaryId = id
        AppHaptics.light()
    }

    func selectSecondary(_ id: String) {
        guard secondaryId != id else { return }
        secondaryId = id
        AppHaptics.light()
    }

    func selectBackground(_ id: String) {
        guard backgroundId != id else { return }
        backgroundId = id
        AppHaptics.light()
    }

    func resetThemeColors() {
        primaryId = ThemePaletteCatalog.defaultPrimaryId
        secondaryId = ThemePaletteCatalog.defaultSecondaryId
        backgroundId = ThemePaletteCatalog.defaultBackgroundId
        AppHaptics.success()
    }

    private func persistPalette() {
        guard !isHydrating else { return }
        UserDefaults.standard.set(primaryId, forKey: Self.primaryKey)
        UserDefaults.standard.set(secondaryId, forKey: Self.secondaryKey)
        UserDefaults.standard.set(backgroundId, forKey: Self.backgroundKey)
        applyPaletteToBridge(bumpRevision: true)
    }

    private func applyPaletteToBridge(bumpRevision: Bool) {
        ThemePaletteBridge.current = .resolve(
            primaryId: primaryId,
            secondaryId: secondaryId,
            backgroundId: backgroundId
        )
        let primary = ThemePaletteCatalog.primary(id: primaryId)
        let secondary = ThemePaletteCatalog.secondary(id: secondaryId)
        let background = ThemePaletteCatalog.background(id: backgroundId)
        // force: le sideload remappe l’App Group — republier garantit le pont widget.
        WidgetSharedStore.publishTheme(
            accentLight: primary.light,
            accentDark: primary.dark,
            secondaryLight: secondary.light,
            secondaryDark: secondary.dark,
            backgroundLight: background.light,
            backgroundDark: background.dark,
            force: true
        )
        if bumpRevision {
            themeRevision &+= 1
        }
    }

    /// Republie le thème vers les widgets (retour premier plan / après login).
    func republishThemeToWidgets() {
        applyPaletteToBridge(bumpRevision: false)
    }
}
