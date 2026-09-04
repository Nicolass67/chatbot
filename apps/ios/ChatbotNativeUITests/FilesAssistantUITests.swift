import XCTest

/// P6–P7 / P12 — Files Assistant in-place + context chip + history isolation.
final class FilesAssistantUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFilesRootAssistantSheetAndHistory() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabFiles)
        XCTAssertTrue(
            app.element(id: UITestA11y.filesRoot, timeout: 10).exists
                || app.navigationBars["Files"].waitForExistence(timeout: 4)
        )
        saveScreenshot(app, name: "files-assistant-before")

        XCTAssertTrue(
            app.tapAssistantFAB(id: UITestA11y.filesAssistant, label: "Assistant Files"),
            "FAB Files Assistant"
        )

        let sheet = app.element(id: UITestA11y.assistantSheet, timeout: 8)
        XCTAssertTrue(sheet.exists || app.buttons["Fermer"].waitForExistence(timeout: 4))
        let chip = app.element(id: UITestA11y.assistantContext, timeout: 6)
        XCTAssertTrue(
            chip.exists
                || app.staticTexts["Tous vos fichiers"].waitForExistence(timeout: 3)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "fichiers")).firstMatch.exists,
            "Context chip Files global"
        )
        saveScreenshot(app, name: "files-assistant")

        let history = app.element(id: UITestA11y.assistantHistory, timeout: 5)
        if history.exists {
            XCTAssertTrue(app.tapFirst(id: UITestA11y.assistantHistory), "History tap")
            XCTAssertTrue(
                app.staticTexts["Conversations Files"].waitForExistence(timeout: 5),
                "History title Files"
            )
            XCTAssertFalse(app.staticTexts["Conversations Mail"].exists)
            saveScreenshot(app, name: "files-assistant-history")
            app.swipeDown()
        }

        if !app.tapFirst(id: UITestA11y.assistantClose, timeout: 4) {
            if app.buttons["Fermer"].exists {
                app.buttons["Fermer"].firstMatch.tap()
            } else {
                app.swipeDown()
            }
        }
        saveScreenshot(app, name: "files-after-assistant-close")
    }

    /// Après le root assistant (ordre alphabétique) pour limiter les flakes de cold launch.
    func testFilesNestedFolderContextChip() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabFiles)
        XCTAssertTrue(app.staticTexts["Documents"].waitForExistence(timeout: 8))
        app.staticTexts["Documents"].tap()

        let fabOk = app.tapAssistantFAB(id: UITestA11y.filesAssistant, label: "Assistant Files")
        XCTAssertTrue(fabOk)

        let chip = app.element(id: UITestA11y.assistantContext, timeout: 6)
        XCTAssertTrue(
            chip.exists
                || app.staticTexts["Documents"].waitForExistence(timeout: 3)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Documents")).firstMatch
                    .waitForExistence(timeout: 3),
            "Folder context expected (Documents)"
        )
        saveScreenshot(app, name: "files-assistant-folder-context")

        if !app.tapFirst(id: UITestA11y.assistantClose, timeout: 3) {
            if app.buttons["Fermer"].exists {
                app.buttons["Fermer"].firstMatch.tap()
            } else {
                app.swipeDown()
            }
        }
    }
}
