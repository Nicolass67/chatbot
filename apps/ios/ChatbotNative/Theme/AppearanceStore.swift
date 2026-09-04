import SwiftUI
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
