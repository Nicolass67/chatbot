import XCTest

/// Files : navigation drill-in / back + Assistant contextuel.
final class FilesNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFilesRootAssistantAndDrillIn() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabFiles)
        saveScreenshot(app, name: "files-root")

        let root = app.element(id: UITestA11y.filesRoot, timeout: 10)
        XCTAssertTrue(
            root.exists || app.navigationBars["Files"].exists,
            "Files root attendu"
        )

        let assistant = app.element(id: UITestA11y.filesAssistant, timeout: 5)
        if assistant.exists {
            assistant.tap()
            saveScreenshot(app, name: "files-assistant-root")
            let sheet = app.element(id: UITestA11y.assistantSheet, timeout: 6)
            XCTAssertTrue(sheet.exists || app.buttons["Fermer"].exists)
            let close = app.element(id: UITestA11y.assistantClose, timeout: 4)
            if close.exists { close.tap() } else { app.buttons["Fermer"].firstMatch.tap() }
        }

        let documents = app.staticTexts["Documents"]
        XCTAssertTrue(documents.waitForExistence(timeout: 8), "Documents fixture required")
        documents.tap()
        saveScreenshot(app, name: "files-folder-documents")
        if app.navigationBars.buttons.count > 0 {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
            saveScreenshot(app, name: "files-back-to-root")
            XCTAssertTrue(
                app.navigationBars["Files"].waitForExistence(timeout: 5)
                    || app.element(id: UITestA11y.filesRoot, timeout: 5).exists,
                "Retour root Files attendu (régression navigation)"
            )
        }
    }
}
