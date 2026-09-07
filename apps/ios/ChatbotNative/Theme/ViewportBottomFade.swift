import SwiftUI

/// Bande de fade ancrée au bas du viewport — calque intermédiaire uniquement
/// (devant le contenu scrollable, derrière le chrome interactif).
struct ViewportBottomFade: View {
    var height: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.22),
                    .init(color: AppTheme.background.opacity(0.12), location: 0.48),
                    .init(color: AppTheme.background.opacity(0.40), location: 0.70),
                    .init(color: AppTheme.background.opacity(0.78), location: 0.88),
                    .init(color: AppTheme.background, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("viewport.bottomFade")
    }
}
