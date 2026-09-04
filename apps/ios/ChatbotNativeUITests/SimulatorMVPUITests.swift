import XCTest

/// MVP Fast Simulator — roots + GATE Chat P2–P4 (une session chaude, fixtures déterministes).
final class SimulatorMVPUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChatMailFilesRootsAndScreenshots() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        // CHAT root (empty composer)
        app.tapTab(UITestA11y.tabChat)
        let chatRoot = app.element(id: UITestA11y.chatRoot, timeout: 12)
        let composer = app.element(id: UITestA11y.chatComposer, timeout: 16)
        XCTAssertTrue(
            chatRoot.exists || composer.exists || app.element(id: UITestA11y.chatComposerField, timeout: 4).exists,
            "Chat root / composer must be visible with UITest fixtures"
        )
        saveScreenshot(app, name: "chat-empty")

        // P2 — keyboard dismiss (session déjà chaude)
        try assertKeyboardDismiss(app)

        // MAIL inbox
        app.tapTab(UITestA11y.tabMail)
        let mailRoot = app.element(id: UITestA11y.mailRoot, timeout: 12)
        XCTAssertTrue(
            mailRoot.exists || app.navigationBars["Mail"].waitForExistence(timeout: 5),
            "Mail root must be visible"
        )
        XCTAssertTrue(
            app.staticTexts["Votre facture Free du mois"].waitForExistence(timeout: 8)
                || app.element(id: "mail.message", timeout: 8).exists,
            "Fixture mail (Free invoice) must appear in inbox"
        )
        saveScreenshot(app, name: "mail-inbox")

        // FILES root
        app.tapTab(UITestA11y.tabFiles)
        let filesRoot = app.element(id: UITestA11y.filesRoot, timeout: 12)
        XCTAssertTrue(
            filesRoot.exists || app.navigationBars["Files"].waitForExistence(timeout: 5),
            "Files root must be visible"
        )
        XCTAssertTrue(
            app.staticTexts["Documents"].waitForExistence(timeout: 8)
                || app.element(id: "files.folder", timeout: 8).exists,
            "Fixture Documents root must appear"
        )
        saveScreenshot(app, name: "files-root")
    }

    /// P3 Thinking + P4 Agent — relaunch avec scénario SSE (évite conflit d’état dans le même process).
    func testChatThinkingAndAgentScreenshots() throws {
        // Thinking
        let app = XCUIApplication()
        app.launchForUITesting(sseScenario: "thinking")
        app.assertUITestSession()
        app.tapTab(UITestA11y.tabChat)
        let field = try requireComposerField(app)
        field.tap()
        field.typeText("UITest thinking")
        let send = app.element(id: UITestA11y.chatSend, timeout: 8)
        XCTAssertTrue(send.exists)
        send.tap()
        let thinking = app.element(id: UITestA11y.chatThinking, timeout: 12)
        XCTAssertTrue(thinking.exists, "ThinkingStatusView (P3)")
        XCTAssertFalse(app.element(id: UITestA11y.agentRoot, timeout: 1).exists)
        saveScreenshot(app, name: "chat-thinking")

        // Agent
        let app2 = XCUIApplication()
        app2.launchForUITesting(sseScenario: "agent")
        app2.assertUITestSession()
        app2.tapTab(UITestA11y.tabChat)
        let field2 = try requireComposerField(app2)
        field2.tap()
        field2.typeText("UITest agent")
        app2.element(id: UITestA11y.chatSend, timeout: 8).tap()
        let agent = app2.element(id: UITestA11y.agentRoot, timeout: 12)
        XCTAssertTrue(agent.exists, "AgentActivityView (P4)")
        XCTAssertFalse(app2.element(id: UITestA11y.chatThinking, timeout: 1).exists)
        saveScreenshot(app2, name: "chat-agent")
        if app2.element(id: UITestA11y.chatStop, timeout: 2).exists {
            app2.element(id: UITestA11y.chatStop).tap()
            saveScreenshot(app2, name: "chat-agent-stopped")
        }
    }

    private func assertKeyboardDismiss(_ app: XCUIApplication) throws {
        let field = try requireComposerField(app)
        field.tap()
        saveScreenshot(app, name: "chat-composer")
        let dismiss = app.element(id: UITestA11y.chatKeyboardDismiss, timeout: 6)
        XCTAssertTrue(
            dismiss.exists || app.buttons["Fermer"].exists,
            "Keyboard dismiss (P2)"
        )
        if dismiss.exists {
            dismiss.tap()
        } else {
            app.buttons["Fermer"].firstMatch.tap()
        }
        saveScreenshot(app, name: "chat-keyboard-dismissed")
    }

    private func requireComposerField(_ app: XCUIApplication) throws -> XCUIElement {
        // 1) Identifiant dédié
        let byId = app.descendants(matching: .any)[UITestA11y.chatComposerField]
        if byId.waitForExistence(timeout: 8) { return byId }

        // 2) Capsule composer puis TextField / TextView « Message »
        let composer = app.descendants(matching: .any)[UITestA11y.chatComposer]
        XCTAssertTrue(composer.waitForExistence(timeout: 16), "chat.composer capsule required")
        composer.tap()

        let tf = app.textFields["Message"]
        if tf.waitForExistence(timeout: 4) { return tf }
        let tv = app.textViews["Message"]
        if tv.waitForExistence(timeout: 4) { return tv }

        // 3) Premier champ éditable sous la capsule
        let anyField = composer.textFields.firstMatch
        if anyField.waitForExistence(timeout: 2) { return anyField }
        let anyView = composer.textViews.firstMatch
        if anyView.waitForExistence(timeout: 2) { return anyView }

        // 4) Query globale last resort
        if byId.waitForExistence(timeout: 3) { return byId }
        XCTFail("Composer field not found (tried id, Message, capsule children)")
        return byId
    }
}
