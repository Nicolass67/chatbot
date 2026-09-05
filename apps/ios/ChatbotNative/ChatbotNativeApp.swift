import SwiftUI

@main
struct ChatbotNativeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AppSessionStore()
    @StateObject private var appearance = AppearanceStore()
    @StateObject private var infrastructure = InfrastructureStore()
    @State private var nav = AppNavigation()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(appearance)
                .environmentObject(infrastructure)
                .environment(nav)
                .environment(\.themeRevision, appearance.themeRevision)
                .tint(AppTheme.accent)
                // Style via `AppearanceStore.applyWindowInterfaceStyle` (UIKit) —
                // `preferredColorScheme` sur WindowGroup remountait la sheet Réglages.
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    infrastructure.bind(session: session)
                    AppearanceStore.applyWindowInterfaceStyle(appearance.mode.uiUserInterfaceStyle)
                    appearance.republishThemeToWidgets()
                    Task {
                        await WidgetMailSync.syncIfNeeded(session: session, force: true)
                        if session.isAuthenticated {
                            await infrastructure.refresh()
                        }
                    }
                }
                .onChange(of: session.token) { _, token in
                    infrastructure.bind(session: session)
                    if token != nil {
                        appearance.republishThemeToWidgets()
                        Task {
                            await WidgetMailSync.syncIfNeeded(session: session, force: true)
                            await infrastructure.refresh()
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    appearance.republishThemeToWidgets()
                    Task {
                        await WidgetMailSync.syncIfNeeded(session: session)
                        if session.isAuthenticated {
                            await infrastructure.refresh()
                        }
                    }
                }
        }
    }

    /// Deep links QA / product. Never bypass auth — intents are applied only after login.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "chatbot-native" else { return }
        let host = (url.host ?? "").lowercased()
        let parts = url.path.split(separator: "/").map { $0.lowercased() }

        // Product shortcuts (non-qa)
        switch host {
        case "oauth":
            nav.openSettings()
            return
        case "chat":
            nav.selectedTab = .chat
            if parts.first == "new" || parts.isEmpty {
                nav.openConversationId = "__new__"
            }
            return
        case "settings":
            nav.openSettings()
            return
        default:
            break
        }

        // Normalise: chatbot-native://qa/...  OR  chatbot-native://tab/... etc.
        let route: [String]
        if host == "qa" {
            route = parts
        } else if host == "tab" || host == "assistant" || host == "mail" || host == "files" {
            route = [host] + parts
        } else {
            route = [host] + parts
        }

        guard let head = route.first else { return }
        let rest = Array(route.dropFirst())

        // Require auth for QA navigation intents (except login screen stays as-is).
        guard session.isAuthenticated else { return }

        switch head {
        case "chat":
            nav.applyQaIntent(.chat)
            if rest.first == "new" { nav.openConversationId = "__new__" }
        case "composer":
            nav.applyQaIntent(.composer)
        case "agent":
            nav.applyQaIntent(.agent)
            nav.chatComposerPrefill = nav.chatComposerPrefill ?? ""
        case "thinking":
            nav.applyQaIntent(.thinking)
        case "tab":
            switch rest.first {
            case "mail": nav.selectedTab = .mail
            case "files": nav.selectedTab = .files
            default: nav.selectedTab = .chat
            }
        case "mail":
            switch rest.first {
            case "detail":
                nav.applyQaIntent(.mailDetail)
            case "assistant":
                nav.applyQaIntent(.mailAssistant)
            default:
                nav.applyQaIntent(.mail)
            }
        case "files":
            switch rest.first {
            case "documents":
                nav.applyQaIntent(.filesDocuments)
            case "nested":
                nav.applyQaIntent(.filesNested)
            case "file":
                nav.applyQaIntent(.filesFile)
            case "assistant":
                nav.applyQaIntent(.filesAssistant)
            default:
                nav.applyQaIntent(.files)
            }
        case "assistant":
            switch rest.first {
            case "files":
                nav.applyQaIntent(.filesAssistant)
            default:
                nav.applyQaIntent(.mailAssistant)
            }
        case "settings":
            nav.openSettings()
        default:
            break
        }
    }
}
