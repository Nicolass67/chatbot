import XCTest

/// MVP Fast Simulator — suites découpées pour TEST_PLAN (chat / mail / files / all).
final class SimulatorMVPUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Chat empty + P2 keyboard (pas de Mail/Files — plan `chat` rapide).
    func testChatEmptyAndKeyboardScreenshots() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabChat)
        let chatRoot = app.element(id: UITestA11y.chatRoot, timeout: 12)
        let composer = app.element(id: UITestA11y.chatComposer, timeout: 8)
        XCTAssertTrue(
            chatRoot.exists
                || composer.exists
                || app.textFields["Message"].waitForExistence(timeout: 8)
                || app.navigationBars["Nouveau chat"].waitForExistence(timeout: 4),
            "Chat root / composer must be visible with UITest fixtures"
        )
        saveScreenshot(app, name: "chat-empty")
        try assertKeyboardDismiss(app)
    }

    /// Roots Mail + Files (plan `all` / smoke cross-tab).
    func testMailFilesRootsScreenshots() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

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

    /// P3 Thinking + P4 Agent — relaunch avec scénario SSE.
    func testChatThinkingAndAgentScreenshots() throws {
        let app = XCUIApplication()
        app.launchForUITesting(sseScenario: "thinking")
        app.assertUITestSession()
        app.tapTab(UITestA11y.tabChat)
        let field = try requireComposerField(app)
        field.tap()
        // Send armé en UITestMode même si le binding draft n’a pas suivi typeText.
        field.typeText("UITest thinking")
        let send = app.element(id: UITestA11y.chatSend, timeout: 8)
        XCTAssertTrue(send.exists)
        send.tap()
        // ThinkingStatusView dès isSending (.reflecting) puis fixture SSE.
        let thinking = app.element(id: UITestA11y.chatThinking, timeout: 14)
        XCTAssertTrue(thinking.exists, "ThinkingStatusView (P3)")
        XCTAssertFalse(app.element(id: UITestA11y.agentRoot, timeout: 1).exists)
        saveScreenshot(app, name: "chat-thinking")

        let app2 = XCUIApplication()
        app2.launchForUITesting(sseScenario: "agent")
        app2.assertUITestSession()
        app2.tapTab(UITestA11y.tabChat)
        let field2 = try requireComposerField(app2)
        field2.tap()
        field2.typeText("UITest agent")
        let send2 = app2.element(id: UITestA11y.chatSend, timeout: 8)
        if send2.exists {
            send2.tap()
        } else {
            sendOrArrow(app2).tap()
        }
        let agent = app2.element(id: UITestA11y.agentRoot, timeout: 12)
        XCTAssertTrue(agent.exists, "AgentActivityView (P4)")
        XCTAssertFalse(app2.element(id: UITestA11y.chatThinking, timeout: 1).exists)
        saveScreenshot(app2, name: "chat-agent")
        if app2.element(id: UITestA11y.chatStop, timeout: 2).exists {
            app2.element(id: UITestA11y.chatStop).tap()
            saveScreenshot(app2, name: "chat-agent-stopped")
        }
    }

    private func sendOrArrow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "envoyer")).firstMatch
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
        let byId = app.descendants(matching: .any)[UITestA11y.chatComposerField]
        if byId.waitForExistence(timeout: 4) { return byId }

        let tf = app.textFields["Message"]
        if tf.waitForExistence(timeout: 10) { return tf }
        let tv = app.textViews["Message"]
        if tv.waitForExistence(timeout: 4) { return tv }
        let anyMsg = app.descendants(matching: .any)["Message"]
        if anyMsg.waitForExistence(timeout: 4), anyMsg.isHittable {
            return anyMsg
        }

        let composer = app.descendants(matching: .any)[UITestA11y.chatComposer]
        if composer.waitForExistence(timeout: 3) {
            composer.tap()
            if tf.waitForExistence(timeout: 2) { return tf }
            if byId.waitForExistence(timeout: 2) { return byId }
        }

        XCTFail("Composer field not found (id / Message / capsule)")
        return byId
    }
}
