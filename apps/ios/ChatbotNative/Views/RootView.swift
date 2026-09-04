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
    @Environment(AppNavigation.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        TabView(selection: $nav.selectedTab) {
            Tab(AppTab.chat.title, systemImage: AppTab.chat.systemImage, value: AppTab.chat) {
                ChatRootView()
            }
            .accessibilityIdentifier(A11yID.Navigation.tabChat)

            Tab(AppTab.mail.title, systemImage: AppTab.mail.systemImage, value: AppTab.mail) {
                MailInboxView()
            }
            .accessibilityIdentifier(A11yID.Navigation.tabMail)

            Tab(AppTab.files.title, systemImage: AppTab.files.systemImage, value: AppTab.files) {
                FilesBrowserView()
            }
            .accessibilityIdentifier(A11yID.Navigation.tabFiles)
        }
        .tint(AppTheme.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .accessibilityIdentifier(A11yID.Navigation.tabBar)
        .sheet(isPresented: $nav.showSettings) {
            SettingsHubView()
                .environmentObject(session)
                .environment(nav)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
