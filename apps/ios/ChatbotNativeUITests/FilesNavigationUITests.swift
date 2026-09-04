import XCTest

/// Files : navigation drill-in / nested / back + Assistant contextuel.
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
            XCTAssertTrue(sheet.exists || app.buttons["Fermer"].exists || app.buttons["OK"].exists)
            let close = app.element(id: UITestA11y.assistantClose, timeout: 4)
            if close.exists {
                close.tap()
            } else if app.buttons["Fermer"].exists {
                app.buttons["Fermer"].firstMatch.tap()
            } else if app.buttons["OK"].exists {
                app.buttons["OK"].firstMatch.tap()
            } else {
                app.swipeDown()
            }
        }

        let documents = app.staticTexts["Documents"]
        XCTAssertTrue(documents.waitForExistence(timeout: 8), "Documents fixture required")
        documents.tap()
        saveScreenshot(app, name: "files-folder-documents")

        // Nested folder (P1 / Files nav DoD)
        let projects = app.staticTexts["Projets"]
        XCTAssertTrue(projects.waitForExistence(timeout: 6), "Projets nested folder")
        projects.tap()
        saveScreenshot(app, name: "files-nested")
        let spec = app.staticTexts["spec.md"]
        XCTAssertTrue(
            spec.waitForExistence(timeout: 6)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "spec")).firstMatch
                    .waitForExistence(timeout: 3),
            "Nested file fixture expected"
        )

        // P11 — preview fichier
        if spec.exists {
            spec.tap()
        } else {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "spec")).firstMatch.tap()
        }
        let preview = app.element(id: "files.preview", timeout: 8)
        XCTAssertTrue(
            preview.exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "UITest fixture")).firstMatch
                    .waitForExistence(timeout: 4)
                || app.navigationBars["spec.md"].waitForExistence(timeout: 3),
            "Files preview (P11)"
        )
        saveScreenshot(app, name: "files-preview")

        // Back preview → nested → Documents → root
        for _ in 0..<4 {
            if app.navigationBars["Files"].waitForExistence(timeout: 1)
                || app.element(id: UITestA11y.filesRoot, timeout: 1).exists {
                break
            }
            if app.navigationBars.buttons.count > 0 {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                break
            }
        }
        saveScreenshot(app, name: "files-back-to-root")
        XCTAssertTrue(
            app.navigationBars["Files"].waitForExistence(timeout: 5)
                || app.element(id: UITestA11y.filesRoot, timeout: 5).exists,
            "Retour root Files attendu (régression navigation)"
        )
    }
}
