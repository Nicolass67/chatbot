import SwiftUI
import UIKit

/// Partage natif iOS (UIActivityViewController) — pas de sheet SwiftUI quasi vide.
enum NativeShare {
    @MainActor
    static func present(url: URL, title: String? = nil) {
        Task { @MainActor in
            // Attendre la fermeture d’une sheet SwiftUI éventuelle.
            for _ in 0..<12 {
                if topViewController()?.presentedViewController == nil { break }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.excludedActivityTypes = [
                .addToReadingList,
                .assignToContact,
            ]
            guard let presenter = topViewController() else { return }
            if let pop = activity.popoverPresentationController {
                pop.sourceView = presenter.view
                pop.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 1,
                    height: 1
                )
                pop.permittedArrowDirections = []
            }
            presenter.present(activity, animated: true)
        }
    }

    @MainActor
    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
