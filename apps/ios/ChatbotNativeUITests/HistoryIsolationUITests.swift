import XCTest

/// Isolation des 3 historiques : general / mail / files.
final class HistoryIsolationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMailHistoryIsNotGeneralOrFiles() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabMail)
        let assistant = app.element(id: UITestA11y.mailAssistant, timeout: 8)
        if assistant.exists {
            assistant.tap()
        } else {
            let fab = app.element(id: "assistant.open", timeout: 3)
            XCTAssertTrue(fab.exists, "Assistant Mail indisponible")
            fab.tap()
        }

        let history = app.element(id: UITestA11y.assistantHistory, timeout: 8)
        XCTAssertTrue(history.exists, "Bouton historique Assistant absent")
        history.tap()
        saveScreenshot(app, name: "history-mail-scope")

        if app.staticTexts["Conversations Files"].waitForExistence(timeout: 2) {
            XCTFail("Mail Assistant → historique Files (isolation cassée)")
        }
        let mailTitle = app.staticTexts["Conversations Mail"]
        if mailTitle.waitForExistence(timeout: 3) {
            XCTAssertTrue(mailTitle.exists)
        }
    }

    func testFilesHistoryIsNotMail() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabFiles)
        let assistant = app.element(id: UITestA11y.filesAssistant, timeout: 8)
        if assistant.exists {
            assistant.tap()
        } else {
            let fab = app.element(id: "assistant.open", timeout: 3)
            XCTAssertTrue(fab.exists, "Assistant Files indisponible")
            fab.tap()
        }

        let history = app.element(id: UITestA11y.assistantHistory, timeout: 8)
        XCTAssertTrue(history.exists, "Bouton historique Assistant absent")
        history.tap()
        saveScreenshot(app, name: "history-files-scope")

        if app.staticTexts["Conversations Mail"].waitForExistence(timeout: 2) {
            XCTFail("Files Assistant → historique Mail (isolation cassée)")
        }
    }
}
