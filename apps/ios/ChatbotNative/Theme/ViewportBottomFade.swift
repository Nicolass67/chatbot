import SwiftUI

/// Bande de fade ancrée en bas du conteneur parent — calque intermédiaire uniquement
/// (devant le contenu scrollable, derrière le chrome interactif).
///
/// Ne pas mettre `.ignoresSafeArea` ici : le parent gère le lift au-dessus du chrome
/// via `padding(.bottom, chromeHeight)`. Un ignoresSafeArea re-étendrait le fade sous le verre.
struct ViewportBottomFade: View {
    var height: CGFloat = 360

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("viewport.bottomFade")
    }
}
