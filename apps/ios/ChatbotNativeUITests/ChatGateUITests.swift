import XCTest

/// GATE Chat — P2 keyboard / P3 Thinking / P4 Agent+Stop (fixtures SSE déterministes).
final class ChatGateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testComposerKeyboardDismiss() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabChat)
        let field = app.element(id: UITestA11y.chatComposerField, timeout: 12)
        XCTAssertTrue(field.exists, "Composer field")
        field.tap()
        saveScreenshot(app, name: "chat-composer")

        let dismiss = app.element(id: UITestA11y.chatKeyboardDismiss, timeout: 6)
        XCTAssertTrue(
            dismiss.exists || app.buttons["Fermer"].exists,
            "Keyboard dismiss control above composer (P2)"
        )
        if dismiss.exists {
            dismiss.tap()
        } else {
            app.buttons["Fermer"].firstMatch.tap()
        }
        saveScreenshot(app, name: "chat-keyboard-dismissed")
    }

    func testThinkingExclusiveOfAgent() throws {
        let app = XCUIApplication()
        app.launchForUITesting(sseScenario: "thinking")
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabChat)
        let field = app.element(id: UITestA11y.chatComposerField, timeout: 12)
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText("UITest thinking")
        let send = app.element(id: UITestA11y.chatSend, timeout: 5)
        XCTAssertTrue(send.exists)
        send.tap()

        let thinking = app.element(id: UITestA11y.chatThinking, timeout: 8)
        XCTAssertTrue(thinking.exists, "ThinkingStatusView must appear during chat stream (P3)")
        XCTAssertFalse(
            app.element(id: UITestA11y.agentRoot, timeout: 1).exists,
            "Agent strip must not show while Thinking is active"
        )
        saveScreenshot(app, name: "chat-thinking")
    }

    func testAgentTimelineStopAndHumanError() throws {
        // sseScenario=agent force la timeline même si le mode UI reste « chat ».
        let app = XCUIApplication()
        app.launchForUITesting(sseScenario: "agent")
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabChat)
        let field = app.element(id: UITestA11y.chatComposerField, timeout: 10)
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText("UITest agent")
        app.element(id: UITestA11y.chatSend, timeout: 5).tap()

        let agent = app.element(id: UITestA11y.agentRoot, timeout: 10)
        XCTAssertTrue(agent.exists, "AgentActivityView must appear (P4)")
        XCTAssertFalse(
            app.element(id: UITestA11y.chatThinking, timeout: 1).exists,
            "Thinking must be hidden when Agent is visible"
        )
        saveScreenshot(app, name: "chat-agent")

        let stop = app.element(id: UITestA11y.chatStop, timeout: 3)
        if stop.exists {
            stop.tap()
            saveScreenshot(app, name: "chat-agent-stopped")
        }

        // Human-readable error path (relaunch déterministe)
        let app2 = XCUIApplication()
        app2.launchForUITesting(sseScenario: "agent-error")
        app2.assertUITestSession()
        app2.tapTab(UITestA11y.tabChat)
        let field2 = app2.element(id: UITestA11y.chatComposerField, timeout: 10)
        field2.tap()
        field2.typeText("UITest agent error")
        app2.element(id: UITestA11y.chatSend, timeout: 5).tap()
        XCTAssertTrue(app2.element(id: UITestA11y.agentRoot, timeout: 10).exists)

        let friendly = app2.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "fichier")
        ).firstMatch
        XCTAssertTrue(
            friendly.waitForExistence(timeout: 8)
                || app2.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "autorisé")).firstMatch
                    .waitForExistence(timeout: 2)
                || app2.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "échoué")).firstMatch
                    .waitForExistence(timeout: 2),
            "Human-readable agent error expected"
        )
        saveScreenshot(app2, name: "chat-agent-error")
    }
}
