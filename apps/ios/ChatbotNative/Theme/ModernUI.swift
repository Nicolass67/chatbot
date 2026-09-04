import SwiftUI
import UIKit

enum AppHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
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
        .background(AppTheme.danger.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .stroke(AppTheme.danger.opacity(0.35), lineWidth: 1)
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
        .foregroundStyle(AppTheme.warning)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.space12)
        .padding(.horizontal, AppTheme.space16)
        .background(AppTheme.warning.opacity(0.12))
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

struct MessageChromeMeta: Equatable {
    var sources: [SearchSourceDTO] = []
    var mailHandoff: MailHandoffDTO?
    var filesHandoff: FilesHandoffDTO?
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
