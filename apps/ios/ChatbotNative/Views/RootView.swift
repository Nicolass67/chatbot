import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.isAuthenticated {
                if session.isUnlocked {
                    MainTabView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    BiometricLockView()
                        .accessibilityIdentifier(A11yID.Auth.lockScreen)
                        .transition(.opacity)
                }
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: AppTheme.motionStandard), value: session.isAuthenticated)
        .animation(.smooth(duration: AppTheme.motionQuick), value: session.isUnlocked)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, session.biometricLockEnabled, session.isAuthenticated {
                session.isUnlocked = false
            }
        }
    }
}

struct BiometricLockView: View {
    @EnvironmentObject private var session: AppSessionStore

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: AppTheme.space24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
                Text("Chatbot est verrouillé")
                    .font(CNFont.title)
                    .foregroundStyle(AppTheme.foreground)
                Text("Utilise Face ID ou le code de l’appareil pour continuer.")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.space32)
                if let err = session.lastError {
                    SoftErrorBanner(message: err) {
                        Task { await session.unlockWithBiometrics() }
                    }
                    .padding(.horizontal, AppTheme.space32)
                }
                Button {
                    Task { await session.unlockWithBiometrics() }
                } label: {
                    Text("Déverrouiller")
                        .font(CNFont.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.touchMin)
                        .background(AppTheme.accent)
                        .foregroundStyle(AppTheme.accentForeground)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusXl, style: .continuous))
                }
                .padding(.horizontal, AppTheme.space32)
                .accessibilityIdentifier(A11yID.Auth.unlock)
                .accessibilityLabel("Déverrouiller avec Face ID")
            }
        }
        .task {
            await session.unlockWithBiometrics()
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: AppTheme.space32) {
                Spacer()
                VStack(spacing: AppTheme.space16) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .modifier(PulseIfNeeded(reduceMotion: reduceMotion))
                        .accessibilityHidden(true)
                    Text("Chatbot")
                        .font(CNFont.brand)
                        .foregroundStyle(AppTheme.foreground)
                    Text("Ton assistant personnel.")
                        .font(CNFont.callout)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .appearFade()

                if session.isMisconfiguredBaseURL {
                    SoftErrorBanner(
                        message: "Build incorrect : origin \(AppSessionStore.placeholderHost). Réinstalle l’IPA Flash."
                    )
                    .padding(.horizontal, AppTheme.space32)
                    .appearFade()
                } else if let err = session.lastError {
                    SoftErrorBanner(message: err)
                        .padding(.horizontal, AppTheme.space32)
                        .appearFade()
                }

                Button {
                    AppHaptics.medium()
                    session.login()
                } label: {
                    HStack(spacing: AppTheme.space12) {
                        if session.isBusy {
                            ProgressView().tint(AppTheme.accentForeground)
                        }
                        Text(session.isBusy ? "Connexion…" : "Se connecter")
                            .font(CNFont.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.touchMin)
                    .padding(.horizontal, AppTheme.space16)
                    .background(AppTheme.accent)
                    .foregroundStyle(AppTheme.accentForeground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusXl, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.22), radius: 16, y: 6)
                }
                .disabled(session.isBusy || session.isMisconfiguredBaseURL)
                .padding(.horizontal, AppTheme.space32)
                .accessibilityIdentifier(A11yID.Auth.login)
                .accessibilityLabel("Se connecter avec Cloudflare Access")

                Text("Cloudflare Access · session sécurisée sur cet appareil")
                    .font(CNFont.caption2)
                    .foregroundStyle(AppTheme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.space40)

                Spacer()
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(AppNavigation.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        VStack(spacing: 0) {
            ZStack {
                // Toujours montés : évite destroy/@State wipe + rejeu des `.task` à chaque switch.
                ChatRootView()
                    .opacity(nav.selectedTab == .chat ? 1 : 0)
                    .allowsHitTesting(nav.selectedTab == .chat)
                    .accessibilityHidden(nav.selectedTab != .chat)
                    .zIndex(nav.selectedTab == .chat ? 1 : 0)

                MailInboxView()
                    .opacity(nav.selectedTab == .mail ? 1 : 0)
                    .allowsHitTesting(nav.selectedTab == .mail)
                    .accessibilityHidden(nav.selectedTab != .mail)
                    .zIndex(nav.selectedTab == .mail ? 1 : 0)

                FilesBrowserView()
                    .opacity(nav.selectedTab == .files ? 1 : 0)
                    .allowsHitTesting(nav.selectedTab == .files)
                    .accessibilityHidden(nav.selectedTab != .files)
                    .zIndex(nav.selectedTab == .files ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PrimaryTabBar(selection: $nav.selectedTab)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .tint(AppTheme.accent)
        .accessibilityIdentifier(A11yID.Navigation.tabBar)
        .sheet(isPresented: $nav.showSettings) {
            SettingsHubView()
                .environmentObject(session)
                .environmentObject(appearance)
                .environment(nav)
                .chatbotSheetAppearance(appearance.mode)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Tab bar dédiée — hors TabView pour garder Chat/Mail/Files en vie.
private struct PrimaryTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    AppHaptics.light()
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab ? AppTheme.accent : AppTheme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier(tabA11y(tab))
            }
        }
        .padding(.horizontal, 8)
        .background {
            Group {
                if reduceTransparency {
                    AppTheme.surfaceElevated
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppTheme.borderSubtle)
                    .frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tabA11y(_ tab: AppTab) -> String {
        switch tab {
        case .chat: return A11yID.Navigation.tabChat
        case .mail: return A11yID.Navigation.tabMail
        case .files: return A11yID.Navigation.tabFiles
        }
    }
}

private struct PulseIfNeeded: ViewModifier {
    let reduceMotion: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.pulse, options: .repeating.speed(0.35))
        }
    }
}
