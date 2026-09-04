import XCTest

/// Gate ≤5 min : **un seul** launch → Chat empty + Mail inbox + Files root.
final class SmokeGateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSmokeChatMailFilesScreenshots() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabChat)
        let chatRoot = app.element(id: UITestA11y.chatRoot, timeout: 12)
        let composer = app.element(id: UITestA11y.chatComposer, timeout: 8)
        XCTAssertTrue(
            chatRoot.exists
                || composer.exists
                || app.textFields["Message"].waitForExistence(timeout: 8),
            "Chat root / composer must be visible"
        )
        // Empty canvas (fixtures : uitest-conv-empty sans messages)
        XCTAssertFalse(
            app.staticTexts["Bonjour UITest"].waitForExistence(timeout: 1),
            "Empty chat must not show sample fixture messages"
        )
        XCTAssertTrue(
            app.staticTexts["Dis-moi ce dont tu as besoin."].waitForExistence(timeout: 6)
                || app.staticTexts["Chatbot"].waitForExistence(timeout: 4)
                || composer.exists,
            "EmptyChatCanvas (or composer) expected on new chat"
        )
        saveScreenshot(app, name: "chat-empty")

        app.tapTab(UITestA11y.tabMail)
        let mailRoot = app.element(id: UITestA11y.mailRoot, timeout: 12)
        XCTAssertTrue(
            mailRoot.exists || app.navigationBars["Mail"].waitForExistence(timeout: 5),
            "Mail root must be visible"
        )
        XCTAssertTrue(
            app.staticTexts["Votre facture Free du mois"].waitForExistence(timeout: 8)
                || app.element(id: "mail.message", timeout: 8).exists,
            "Fixture mail must appear in inbox"
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
}
