import SwiftUI
import UIKit

/// Retours haptiques centralisés — actions utilisateur significatives uniquement.
/// Respecte le toggle app (`enabledKey`) et les Réglages système iOS (générateurs no-op si désactivés).
/// `@MainActor` : les UIFeedbackGenerator sont isolés au main thread (Swift 6).
@MainActor
enum AppHaptics {
    nonisolated static let enabledKey = "hapticsEnabled"

    /// Défaut ON. `nil` dans UserDefaults = activé.
    nonisolated static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    // Générateurs réutilisés (évite alloc à chaque tap).
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    private static func gated(_ fire: () -> Void) {
        guard isEnabled else { return }
        fire()
    }

    /// Changement de sélection (filtre, tri, toggle mode).
    static func selection() {
        gated {
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        }
    }

    /// Action discrète (envoi, stop, ouverture assistant, navigation).
    static func light() {
        gated {
            lightImpact.impactOccurred()
            lightImpact.prepare()
        }
    }

    /// Action un peu plus marquée (login, confirmation forte).
    static func medium() {
        gated {
            mediumImpact.impactOccurred()
            mediumImpact.prepare()
        }
    }

    static func warning() {
        gated {
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        }
    }

    static func success() {
        gated {
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        }
    }

    static func error() {
        gated {
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
        }
    }
}

enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Chrome navigation des onglets racine (Chat / Mail / Files) :
/// titre + contrôles sur **une** barre inline — pas de large title
/// (qui place le bouton en haut et le titre beaucoup plus bas).
struct TabRootNavigationChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func tabRootNavigationChrome() -> some View {
        modifier(TabRootNavigationChrome())
    }
}

struct KeyboardDismissButton: View {
    var title: String = "Fermer"

    var body: some View {
        Button {
            Keyboard.dismiss()
        } label: {
            Text(title)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 40)
        }
        .accessibilityLabel(title)
    }
}

extension View {
    /// Bouton « Fermer » au-dessus du clavier, avec air pour ne pas coller aux touches.
    func keyboardDismissToolbar(title: String = "Fermer") -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissButton(title: title)
            }
        }
    }
}

struct SoftEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .font(CNFont.title)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating.speed(0.4))
            }
        } description: {
            Text(message)
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.muted)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .frame(minHeight: AppTheme.touchMin)
            }
        }
        .padding(AppTheme.space24)
    }
}

struct SoftLoadingBlock: View {
    var label: String = "Chargement…"

    var body: some View {
        VStack(spacing: AppTheme.space16) {
            ProgressView()
                .controlSize(.regular)
                .tint(AppTheme.accent)
            Text(label)
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// Overlay plein écran : bloque les interactions pendant une mutation Files
/// (suppression / déplacement). Spinner uniquement — pas de texte visible.
struct FilesBlockingBusyOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .scaleEffect(reduceMotion ? 1 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opération en cours")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Barre horizontale indéterminée — entre chrome (filtres) et liste, sans overlay.
/// Hauteur fixe (2pt) pour éviter tout saut de layout.
struct MailListLoadingIndicator: View {
    var isActive: Bool
    var tint: Color = AppTheme.mailAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.borderSubtle.opacity(isActive ? 0.7 : 0))
            if isActive {
                if reduceMotion {
                    Rectangle()
                        .fill(tint.opacity(0.55))
                        .frame(maxWidth: .infinity)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                        GeometryReader { geo in
                            let cycle = 1.05
                            let t = context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: cycle) / cycle
                            let band = max(72.0, geo.size.width * 0.36)
                            let x = -band + CGFloat(t) * (geo.size.width + band)
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            tint.opacity(0),
                                            tint.opacity(0.95),
                                            tint.opacity(0),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: band, height: 2)
                                .offset(x: x)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 2)
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: AppTheme.motionQuick), value: isActive)
        .accessibilityHidden(!isActive)
        .accessibilityLabel(isActive ? "Mise à jour de la boîte mail" : "")
        .accessibilityAddTraits(isActive ? .updatesFrequently : [])
    }
}

struct SoftSkeletonList: View {
    var rows: Int = 6

    var body: some View {
        VStack(spacing: AppTheme.space12) {
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                    .fill(AppTheme.surfaceElevated)
                    .frame(height: 64)
                    .opacity(0.55)
            }
        }
        .padding(AppTheme.space16)
        .redacted(reason: .placeholder)
        .shimmering()
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 200
                }
            }
    }
}

extension View {
    fileprivate func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

struct SoftErrorBanner: View {
    let message: String
    var retryTitle: String = "Réessayer"
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.space12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.danger)
                .frame(width: AppTheme.touchMin / 2, height: AppTheme.touchMin / 2)
            VStack(alignment: .leading, spacing: AppTheme.space4) {
                Text(message)
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let onRetry {
                    Button(retryTitle, action: onRetry)
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(minHeight: AppTheme.touchMin / 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.space16)
        .background(AppTheme.danger.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

struct SoftOfflineBanner: View {
    var body: some View {
        HStack(spacing: AppTheme.space8) {
            Image(systemName: "wifi.slash")
            Text("Hors ligne — certaines actions sont indisponibles.")
                .font(CNFont.caption.weight(.medium))
        }
        .foregroundStyle(AppTheme.muted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.space12)
        .padding(.horizontal, AppTheme.space16)
        .background(AppTheme.surfaceElevated.opacity(0.9))
    }
}

struct ContextUsageMeter: View {
    let usedPercent: Double
    let usedTokens: Int
    let maxTokens: Int
    @State private var showDetail = false

    private var color: Color {
        if usedPercent >= 85 { return AppTheme.danger }
        if usedPercent >= 70 { return AppTheme.warning }
        return AppTheme.muted
    }

    private var label: String {
        let used = formatTokens(usedTokens)
        let max = formatTokens(maxTokens)
        return "\(used)/\(max)"
    }

    var body: some View {
        Button {
            showDetail.toggle()
            AppHaptics.light()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.bottomhalf.filled")
                    .font(.caption2)
                Text(label)
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.touchMin * 0.7)
        .popover(isPresented: $showDetail) {
            VStack(alignment: .leading, spacing: AppTheme.space8) {
                Text("Contexte")
                    .font(CNFont.title)
                ProgressView(value: min(1, usedPercent / 100))
                    .tint(color)
                Text(String(format: "%.0f%% utilisé", usedPercent))
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(AppTheme.space16)
            .frame(width: 220)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }
}

struct FilesFoundFileDTO: Identifiable, Hashable {
    let id: String
    let filename: String
    let relativePath: String?
    let rootId: String?
    let sizeBytes: Int?
    let mtimeMs: Double?
    let extensionHint: String?
}

struct MessageChromeMeta: Equatable {
    var sources: [SearchSourceDTO] = []
    var mailHandoff: MailHandoffDTO?
    var filesHandoff: FilesHandoffDTO?
    var filesFound: [FilesFoundFileDTO] = []
    /// Panel agent Cursor-like — reste attaché au message après la génération.
    var agentRun: AgentRunSnapshot?
}

struct AppearFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown && !reduceMotion ? 0 : (reduceMotion ? 0 : 8))
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.spring(response: AppTheme.motionStandard, dampingFraction: 0.86)) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func appearFade() -> some View {
        modifier(AppearFade())
    }
}
