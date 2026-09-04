import SwiftUI

/// Hub Réglages / Mémoire / À propos (ex-tab « Plus » — désormais sheet).
struct SettingsHubView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(AppNavigation.self) private var nav
    @EnvironmentObject private var appearance: AppearanceStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AmbientBackground()
                List {
                    Section {
                        NavigationLink {
                            MemoryListView()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: AppTheme.space4) {
                                    Text("Souvenirs")
                                        .font(CNFont.body.weight(.medium))
                                    Text("Ce que l’assistant retient pour mieux t’aider")
                                        .font(CNFont.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                            } icon: {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(AppTheme.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .listRowBackground(AppTheme.surface)
                        .accessibilityHint("Ouvre la liste des souvenirs")
                    } header: {
                        Text("Mémoire")
                    }

                    Section {
                        NavigationLink {
                            SettingsView(embedded: true)
                        } label: {
                            Label("Réglages & session", systemImage: "gearshape.fill")
                        }
                        .listRowBackground(AppTheme.surface)
                    } header: {
                        Text("Compte")
                    }

                    Section {
                        LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        LabeledContent("Client", value: "ios · Mobile 3.0")
                    } header: {
                        Text("À propos")
                    }
                    .listRowBackground(AppTheme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Réglages")
            .tabRootNavigationChrome()
            .onChange(of: nav.memoryDeepLink) { _, link in
                guard link != nil else { return }
                path.append(MemoryRoute.list)
            }
            .navigationDestination(for: MemoryRoute.self) { _ in
                MemoryListView()
            }
        }
        .chatbotSheetAppearance(appearance.mode)
        .animation(.easeInOut(duration: AppTheme.motionQuick), value: appearance.mode)
        .id(appearance.mode)
    }
}

/// Compat: ancien nom Plus hub.
typealias MoreHubView = SettingsHubView

private enum MemoryRoute: Hashable {
    case list
}
