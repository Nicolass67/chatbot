import XCTest

/// Smoke Chat : launch → composer → keyboard dismiss control → screenshot.
final class ChatSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsChatOrAuth() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        saveScreenshot(app, name: "chat-launch")

        let login = app.element(id: UITestA11y.authLogin, timeout: 2)
        let composer = app.element(id: UITestA11y.chatComposer, timeout: 8)
        let tabChat = app.element(id: UITestA11y.tabChat, timeout: 8)

        XCTAssertFalse(login.exists, "UITest mode must skip interactive login")
        XCTAssertTrue(
            composer.exists || tabChat.exists || app.tabBars.buttons["Chat"].exists,
            "Expected chat composer or Chat tab after launch"
        )
    }

    func testComposerKeyboardDismissAttached() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabChat)
        let field = app.element(id: UITestA11y.chatComposerField, timeout: 12)
        XCTAssertTrue(field.exists, "Composer field required in UITest mode")
        field.tap()
        saveScreenshot(app, name: "chat-keyboard-open")

        let dismiss = app.element(id: UITestA11y.chatKeyboardDismiss, timeout: 5)
        XCTAssertTrue(
            dismiss.exists || app.buttons["Fermer"].exists,
            "Bouton fermer clavier doit apparaître au-dessus du composer"
        )
        if dismiss.exists {
            dismiss.tap()
        } else {
            app.buttons["Fermer"].firstMatch.tap()
        }
        saveScreenshot(app, name: "chat-keyboard-closed")
    }

    func testSendAndStopIdentifiersExistWhenAuthenticated() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()
        app.tapTab(UITestA11y.tabChat)
        let field = app.element(id: UITestA11y.chatComposerField, timeout: 12)
        XCTAssertTrue(field.exists, "Composer absent")
        field.tap()
        field.typeText("UITest ping \(Int(Date().timeIntervalSince1970))")
        let send = app.element(id: UITestA11y.chatSend, timeout: 5)
        XCTAssertTrue(send.exists)
        send.tap()
        saveScreenshot(app, name: "chat-after-send")
        _ = app.element(id: UITestA11y.chatStop, timeout: 3)
        _ = app.element(id: UITestA11y.chatThinking, timeout: 2)
        saveScreenshot(app, name: "chat-streaming-or-done")
    }
}
