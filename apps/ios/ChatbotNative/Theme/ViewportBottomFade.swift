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
    var height: CGFloat = 360

    var body: some View {
        // Tête longue quasi claire : densification surtout dans le bas (derrière chrome).
        // Évite la « ligne » sombre horizontale au milieu du fil.
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.42),
                .init(color: AppTheme.background.opacity(0.08), location: 0.58),
                .init(color: AppTheme.background.opacity(0.28), location: 0.74),
                .init(color: AppTheme.background.opacity(0.55), location: 0.88),
                .init(color: AppTheme.background.opacity(0.82), location: 1.0)
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
