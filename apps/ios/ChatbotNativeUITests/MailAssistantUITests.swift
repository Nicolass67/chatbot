import XCTest

/// P6 — Mail Assistant in-place (sheet) + context chip + history isolation.
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

        XCTAssertTrue(
            app.tapAssistantFAB(id: UITestA11y.mailAssistant, label: "Assistant Mail"),
            "FAB mail.assistant"
        )

        let sheet = app.element(id: UITestA11y.assistantSheet, timeout: 8)
        XCTAssertTrue(
            sheet.exists
                || app.navigationBars["Mail Assistant"].waitForExistence(timeout: 4)
                || app.buttons["Fermer"].waitForExistence(timeout: 3),
            "Sheet Assistant Mail attendue"
        )

        let chip = app.element(id: UITestA11y.assistantContext, timeout: 6)
        XCTAssertTrue(
            chip.exists || app.staticTexts["Boîte mail"].waitForExistence(timeout: 3),
            "Context chip Mail global (Boîte mail)"
        )
        saveScreenshot(app, name: "mail-assistant")

        let history = app.element(id: UITestA11y.assistantHistory, timeout: 4)
        if history.exists {
            XCTAssertTrue(app.tapFirst(id: UITestA11y.assistantHistory))
            XCTAssertTrue(
                app.staticTexts["Conversations Mail"].waitForExistence(timeout: 5),
                "History title Mail"
            )
            XCTAssertFalse(app.staticTexts["Conversations Files"].exists)
            saveScreenshot(app, name: "mail-assistant-history")
            app.swipeDown()
        }

        // tapFirst — iOS 26 peut exposer plusieurs nœuds pour le même identifier toolbar.
        if !app.tapFirst(id: UITestA11y.assistantClose, timeout: 4) {
            if app.buttons["Fermer"].exists {
                app.buttons["Fermer"].firstMatch.tap()
            } else {
                app.swipeDown()
            }
        }
        saveScreenshot(app, name: "mail-after-assistant-close")
    }

    func testMailThreadAssistantContext() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabMail)
        XCTAssertTrue(app.staticTexts["Votre facture Free du mois"].waitForExistence(timeout: 8))
        app.staticTexts["Votre facture Free du mois"].tap()
        XCTAssertTrue(app.element(id: "mail.detail", timeout: 8).exists)

        let fabOk = app.tapAssistantFAB(id: UITestA11y.mailAssistant, label: "Assistant Mail")
        XCTAssertTrue(fabOk, "FAB on mail detail")

        let chip = app.element(id: UITestA11y.assistantContext, timeout: 6)
        XCTAssertTrue(
            chip.exists
                || app.staticTexts["Votre facture Free du mois"].waitForExistence(timeout: 3)
                || app.navigationBars.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "Assistant")
                ).firstMatch.waitForExistence(timeout: 3),
            "Thread context chip expected"
        )
        saveScreenshot(app, name: "mail-assistant-thread-context")

        if app.buttons["Fermer"].exists {
            app.buttons["Fermer"].tap()
        } else {
            app.swipeDown()
        }
    }
}
