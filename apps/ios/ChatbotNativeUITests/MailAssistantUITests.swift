import XCTest

/// Mail Assistant : doit rester in-place (sheet), jamais basculer vers Chat général.
final class MailAssistantUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMailTabAndAssistantSheet() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabMail)
        saveScreenshot(app, name: "mail-root")

        let mailRoot = app.element(id: UITestA11y.mailRoot, timeout: 10)
        XCTAssertTrue(
            mailRoot.exists || app.navigationBars["Mail"].exists,
            "Mail root doit être visible"
        )

        let assistant = app.element(id: UITestA11y.mailAssistant, timeout: 8)
        if assistant.exists {
            assistant.tap()
        } else {
            let fab = app.element(id: "assistant.open", timeout: 4)
            XCTAssertTrue(fab.exists, "Bouton Assistant Mail introuvable")
            fab.tap()
        }

        let sheet = app.element(id: UITestA11y.assistantSheet, timeout: 8)
        XCTAssertTrue(
            sheet.exists || app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS[c] 'Mail' OR label CONTAINS[c] 'Assistant'")).firstMatch.exists,
            "Sheet Assistant Mail attendue"
        )
        saveScreenshot(app, name: "mail-assistant")

        let history = app.element(id: UITestA11y.assistantHistory, timeout: 4)
        if history.exists {
            history.tap()
            saveScreenshot(app, name: "mail-assistant-history")
            let mailHistoryTitle = app.staticTexts["Conversations Mail"]
            if mailHistoryTitle.waitForExistence(timeout: 3) {
                XCTAssertFalse(
                    app.staticTexts["Conversations Files"].exists,
                    "Historique Mail ne doit pas afficher Files"
                )
            }
        }

        let close = app.element(id: UITestA11y.assistantClose, timeout: 4)
        if close.exists { close.tap() }
        saveScreenshot(app, name: "mail-after-assistant-close")
    }
}
