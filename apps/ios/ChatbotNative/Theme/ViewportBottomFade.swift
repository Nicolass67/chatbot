import SwiftUI

/// Bande de fade ancrée en bas du conteneur parent — calque intermédiaire uniquement
/// (devant le contenu scrollable, derrière le chrome interactif).
///
/// Empilement attendu dans ChatScreen :
/// messages → ViewportBottomFade → composerFloatingChrome (sous la UITabBar).
///
/// Ne PAS relever avec `padding(.bottom, chromeHeight)` : ça décale toute la bande
/// et le début opaque apparaît au-dessus du composer.
struct ViewportBottomFade: View {
    var height: CGFloat = 420

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.28),
                .init(color: AppTheme.background.opacity(0.14), location: 0.48),
                .init(color: AppTheme.background.opacity(0.38), location: 0.66),
                .init(color: AppTheme.background.opacity(0.68), location: 0.84),
                .init(color: AppTheme.background.opacity(0.92), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("viewport.bottomFade")
    }
}
