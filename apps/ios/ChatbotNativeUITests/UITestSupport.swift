import XCTest

/// Helpers partagés pour les UI tests ChatbotNative (Simulator / device).
enum UITestA11y {
    static let tabChat = "navigation.tab.chat"
    static let tabMail = "navigation.tab.mail"
    static let tabFiles = "navigation.tab.files"
    static let chatComposer = "chat.composer"
    static let chatComposerField = "chat.composer.field"
    static let chatSend = "chat.send"
    static let chatStop = "chat.stop"
    static let chatKeyboardDismiss = "chat.keyboard.dismiss"
    static let chatHistory = "chat.history"
    static let chatThinking = "chat.thinking"
    static let chatAgent = "chat.agent"
    static let chatRoot = "chat.root"
    static let mailRoot = "mail.root"
    static let mailAssistant = "mail.assistant"
    static let filesRoot = "files.root"
    static let filesAssistant = "files.assistant"
    static let assistantSheet = "assistant.root"
    static let assistantClose = "assistant.close"
    static let assistantHistory = "assistant.history"
    static let assistantContext = "assistant.context"
    static let authLogin = "auth.login"
    static let agentRoot = "agent.root"
}

extension XCUIApplication {
    func launchForUITesting(extraArgs: [String] = [], sseScenario: String? = nil) {
        launchArguments += ["-UITesting"] + extraArgs
        launchEnvironment["CHATBOT_UI_TESTING"] = "1"
        if let sseScenario, !sseScenario.isEmpty {
            launchEnvironment["CHATBOT_UI_SSE_SCENARIO"] = sseScenario
        }
        launch()
    }

    func element(id: String, timeout: TimeInterval = 8) -> XCUIElement {
        let el = descendants(matching: .any)[id]
        _ = el.waitForExistence(timeout: timeout)
        return el
    }

    func tapTab(_ id: String) {
        let tab = element(id: id, timeout: 10)
        if tab.exists {
            tab.tap()
            return
        }
        // Fallback labels FR/EN tab bar
        let label: String = {
            switch id {
            case UITestA11y.tabChat: return "Chat"
            case UITestA11y.tabMail: return "Mail"
            case UITestA11y.tabFiles: return "Files"
            default: return id
            }
        }()
        tabBars.buttons[label].tap()
    }

    /// Assert session UI-test déterministe (pas d'écran login).
    func assertUITestSession(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(
            element(id: UITestA11y.authLogin, timeout: 2).exists,
            "Expected deterministic UITest session (login screen must not appear)",
            file: file,
            line: line
        )
    }
}

extension XCTestCase {
    func saveScreenshot(_ app: XCUIApplication, name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // UI test host = macOS — écrire PNG plats pour artifacts Cursor.
        // Prefer TEST_RUNNER_* forwarded env, then explicit, then workspace-relative.
        let env = ProcessInfo.processInfo.environment
        let dir = env["CHATBOT_SIM_SCREENSHOT_DIR"]
            ?? env["SRCROOT"].map { "\($0)/../../artifacts/simulator" }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("chatbot-sim-screenshots").path
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url, options: .atomic)
        // Also write under /tmp for CI diagnostics if primary path fails silently
        let tmp = URL(fileURLWithPath: "/tmp/chatbot-sim-screenshots")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: tmp.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
