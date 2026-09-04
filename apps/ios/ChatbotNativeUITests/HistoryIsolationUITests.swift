import XCTest

/// P12 — Isolation des 3 historiques : general / mail / files.
final class HistoryIsolationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMailHistoryIsNotGeneralOrFiles() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabMail)
        XCTAssertTrue(
            app.tapAssistantFAB(id: UITestA11y.mailAssistant, label: "Assistant Mail"),
            "Assistant Mail indisponible"
        )

        let history = app.element(id: UITestA11y.assistantHistory, timeout: 8)
        XCTAssertTrue(history.exists, "Bouton historique Assistant absent")
        XCTAssertTrue(app.tapFirst(id: UITestA11y.assistantHistory), "History Mail tap")
        saveScreenshot(app, name: "history-mail-scope")

        XCTAssertTrue(
            app.staticTexts["Conversations Mail"].waitForExistence(timeout: 5),
            "Titre historique Mail"
        )
        XCTAssertFalse(
            app.staticTexts["Conversations Files"].exists,
            "Mail Assistant → historique Files (isolation cassée)"
        )
        // Fixture scoped conversation visible
        XCTAssertTrue(
            app.staticTexts["Assistant Mail"].waitForExistence(timeout: 4)
                || app.staticTexts["Facture Free"].waitForExistence(timeout: 2),
            "Conversation Mail fixture attendue"
        )
    }

    func testFilesHistoryIsNotMail() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabFiles)
        XCTAssertTrue(
            app.tapAssistantFAB(id: UITestA11y.filesAssistant, label: "Assistant Files"),
            "Assistant Files indisponible"
        )

        let history = app.element(id: UITestA11y.assistantHistory, timeout: 8)
        XCTAssertTrue(history.exists, "Bouton historique Assistant absent")
        XCTAssertTrue(app.tapFirst(id: UITestA11y.assistantHistory), "History Files tap")
        saveScreenshot(app, name: "history-files-scope")

        XCTAssertTrue(
            app.staticTexts["Conversations Files"].waitForExistence(timeout: 5),
            "Titre historique Files"
        )
        XCTAssertFalse(
            app.staticTexts["Conversations Mail"].exists,
            "Files Assistant → historique Mail (isolation cassée)"
        )
        XCTAssertTrue(
            app.staticTexts["Assistant Files"].waitForExistence(timeout: 4)
                || app.staticTexts["notes.txt"].waitForExistence(timeout: 2),
            "Conversation Files fixture attendue"
        )
    }
}
