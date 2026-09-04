import XCTest

/// MVP Fast Simulator — Chat / Mail / Files roots avec session déterministe.
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
        let composer = app.element(id: UITestA11y.chatComposer, timeout: 12)
        XCTAssertTrue(
            chatRoot.exists || composer.exists || app.element(id: UITestA11y.chatComposerField, timeout: 4).exists,
            "Chat root / composer must be visible with UITest fixtures"
        )
        saveScreenshot(app, name: "chat-empty")

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
}
