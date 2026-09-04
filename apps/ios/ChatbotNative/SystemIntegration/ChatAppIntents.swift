import AppIntents
import Foundation

/// Intents Shortcuts minimaux Mobile 3.0 (P15).
struct NewChatIntent: AppIntent {
    static var title: LocalizedStringResource { "Nouveau chat Chatbot" }
    static var description: IntentDescription {
        IntentDescription("Ouvre Chatbot sur une nouvelle conversation.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "intent.requestNewChat")
        return .result()
    }
}

struct ChatbotAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewChatIntent(),
            phrases: [
                "Nouveau chat dans \(.applicationName)",
                "Ouvre un chat \(.applicationName)",
            ],
            shortTitle: "Nouveau chat",
            systemImageName: "bubble.left.and.bubble.right"
        )
    }
}
