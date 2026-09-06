import SwiftUI

/// Empty Chat — calme, éditorial, invite à écrire (pas un dashboard).
struct EmptyChatCanvas: View {
    let onSuggestion: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let suggestions: [(icon: String, text: String)] = [
        ("pencil.and.outline", "Aide-moi à rédiger un message"),
        ("lightbulb", "Explique-moi un concept simplement"),
        ("list.bullet.clipboard", "Aide-moi à planifier ma journée"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppTheme.space16) {
                Text("Chatbot")
                    .font(CNFont.brand)
                    .foregroundStyle(AppTheme.foreground)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 10)

                Text("Dis-moi ce dont tu as besoin.")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, AppTheme.space32)
            .padding(.top, AppTheme.space24)
            .padding(.bottom, AppTheme.space40)

            VStack(spacing: AppTheme.space8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                    Button {
                        AppHaptics.light()
                        onSuggestion(item.text)
                    } label: {
                        HStack(spacing: AppTheme.space12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 28)
                            Text(item.text)
                                .font(CNFont.body)
                                .foregroundStyle(AppTheme.foreground)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.mutedForeground)
                        }
                        .padding(.horizontal, AppTheme.space16)
                        .padding(.vertical, AppTheme.space14)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                                .fill(AppTheme.surfaceElevated.opacity(0.92))
                        )
                        // Pas de contour en clair — le relief vient du fill uniquement.
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.text)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : CGFloat(8 + index * 4))
                }
            }
            .padding(.horizontal, AppTheme.space24)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: AppTheme.motionSettle, dampingFraction: 0.86)) {
                    appeared = true
                }
            }
        }
    }
}
