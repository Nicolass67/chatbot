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
    /// Apparence forcée pour le contenu d’une sheet (chaque bascule, pas seulement la 1ʳᵉ).
    @ViewBuilder
    func chatbotSheetAppearance(_ mode: AppAppearanceMode) -> some View {
        switch mode {
        case .system:
            preferredColorScheme(nil)
                .background(InterfaceStyleBridge(style: .unspecified))
        case .light:
            preferredColorScheme(.light)
                .environment(\.colorScheme, .light)
                .background(InterfaceStyleBridge(style: .light))
        case .dark:
            preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
                .background(InterfaceStyleBridge(style: .dark))
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    private static let defaultsKey = "appAppearanceMode"

    @Published var mode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let parsed = AppAppearanceMode(rawValue: raw)
        {
            mode = parsed
        } else {
            mode = .system
        }
    }
}
