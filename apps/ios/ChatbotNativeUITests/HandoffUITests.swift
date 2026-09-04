import XCTest

/// P13 — handoffs mail/files depuis stream chat (fixture SSE).
final class HandoffUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMailAndFilesHandoffBanners() throws {
        let app = XCUIApplication()
        app.launchForUITesting(sseScenario: "handoff")
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabChat)
        let field = try requireComposer(app)
        field.tap()
        field.typeText("UITest handoff")
        let send = app.element(id: UITestA11y.chatSend, timeout: 8)
        XCTAssertTrue(send.exists)
        send.tap()

        let mailHandoff = app.element(id: "assistant.handoff.mail", timeout: 16)
        XCTAssertTrue(
            mailHandoff.exists
                || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ouvrir dans Mail")).firstMatch
                    .waitForExistence(timeout: 6)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Free")).firstMatch
                    .waitForExistence(timeout: 4),
            "Mail handoff banner expected (P13)"
        )
        saveScreenshot(app, name: "chat-handoff-mail")

        let filesHandoff = app.element(id: "assistant.handoff.files", timeout: 10)
        XCTAssertTrue(
            filesHandoff.exists
                || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ouvrir dans Files")).firstMatch
                    .waitForExistence(timeout: 5)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Documents")).firstMatch
                    .waitForExistence(timeout: 3),
            "Files handoff banner expected (P13)"
        )
        saveScreenshot(app, name: "chat-handoff-files")
    }

    private func requireComposer(_ app: XCUIApplication) throws -> XCUIElement {
        let byId = app.descendants(matching: .any)[UITestA11y.chatComposerField]
        if byId.waitForExistence(timeout: 4) { return byId }
        let tf = app.textFields["Message"]
        if tf.waitForExistence(timeout: 10) { return tf }
        let tv = app.textViews["Message"]
        if tv.waitForExistence(timeout: 4) { return tv }
        XCTFail("Composer missing")
        return byId
    }
}
