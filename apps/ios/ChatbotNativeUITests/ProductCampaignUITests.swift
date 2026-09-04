import XCTest

/// Campagne produit Mobile 3.0 — SIMULATOR (XCUITest).
final class ProductCampaignUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testP6_MailAssistantInPlace() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabMail)
        saveScreenshot(app, name: "SIMULATOR-mail-root")

        let message = app.element(id: "mail.message", timeout: 8)
        if message.exists {
            message.firstMatch.tap()
            saveScreenshot(app, name: "SIMULATOR-mail-detail")
        }

        let assistant = app.element(id: UITestA11y.mailAssistant, timeout: 8)
        if assistant.exists {
            assistant.tap()
        } else if app.element(id: "assistant.open", timeout: 3).exists {
            app.element(id: "assistant.open").tap()
        } else {
            XCTFail("SIMULATOR: Assistant Mail FAB absent")
            return
        }

        XCTAssertTrue(
            app.element(id: UITestA11y.assistantSheet, timeout: 8).exists
                || app.buttons["Fermer"].exists,
            "SIMULATOR: sheet Assistant Mail attendue (pas switch Chat)"
        )
        saveScreenshot(app, name: "SIMULATOR-mail-assistant")

        let hist = app.element(id: UITestA11y.assistantHistory, timeout: 4)
        if hist.exists {
            hist.tap()
            if app.staticTexts["Conversations Files"].waitForExistence(timeout: 2) {
                XCTFail("SIMULATOR FAIL: Mail Assistant → historique Files")
            }
            saveScreenshot(app, name: "SIMULATOR-mail-assistant-history")
        }

        let close = app.element(id: UITestA11y.assistantClose, timeout: 4)
        if close.exists { close.tap() } else { app.buttons["Fermer"].firstMatch.tap() }
        saveScreenshot(app, name: "SIMULATOR-mail-after-assistant")
    }

    func testFilesDrillInAndBack() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabFiles)
        saveScreenshot(app, name: "SIMULATOR-files-root")

        let folder = app.element(id: "files.folder", timeout: 8)
        if folder.exists {
            folder.firstMatch.tap()
            saveScreenshot(app, name: "SIMULATOR-files-folder")
        } else if app.staticTexts["Documents"].exists {
            app.staticTexts["Documents"].tap()
            saveScreenshot(app, name: "SIMULATOR-files-folder")
        } else {
            XCTFail("SIMULATOR: aucun dossier Files")
            return
        }

        if app.navigationBars.buttons.count > 0 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            saveScreenshot(app, name: "SIMULATOR-files-back")
            XCTAssertTrue(
                app.navigationBars["Files"].waitForExistence(timeout: 5)
                    || app.element(id: UITestA11y.filesRoot, timeout: 5).exists,
                "SIMULATOR: retour root Files (régression navigation)"
            )
        }
    }

    func testChatComposerSendSmoke() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabChat)
        saveScreenshot(app, name: "SIMULATOR-chat-empty")

        let field = app.element(id: UITestA11y.chatComposerField, timeout: 12)
        XCTAssertTrue(field.exists, "SIMULATOR: composer absent")
        field.tap()
        saveScreenshot(app, name: "SIMULATOR-chat-composer")
        field.typeText("SIMULATOR ping \(Int(Date().timeIntervalSince1970))")

        let send = app.element(id: UITestA11y.chatSend, timeout: 5)
        XCTAssertTrue(send.exists)
        send.tap()
        saveScreenshot(app, name: "SIMULATOR-chat-after-send")
        _ = app.element(id: "chat.thinking", timeout: 3)
        _ = app.element(id: UITestA11y.chatStop, timeout: 2)
        saveScreenshot(app, name: "SIMULATOR-chat-streaming-or-done")
    }

    func testScopeIsolationMailVsFiles() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabMail)
        if app.element(id: UITestA11y.mailAssistant, timeout: 5).exists {
            app.element(id: UITestA11y.mailAssistant).tap()
        } else if app.element(id: "assistant.open", timeout: 3).exists {
            app.element(id: "assistant.open").tap()
        } else {
            XCTFail("SIMULATOR: assistant mail absent")
            return
        }
        if app.element(id: UITestA11y.assistantHistory, timeout: 5).exists {
            app.element(id: UITestA11y.assistantHistory).tap()
            if app.staticTexts["Conversations Files"].waitForExistence(timeout: 2) {
                XCTFail("SIMULATOR FAIL: isolation Mail/Files cassee")
            }
            saveScreenshot(app, name: "SIMULATOR-scope-mail-history")
            app.buttons["Fermer"].firstMatch.tap()
        }
        if app.element(id: UITestA11y.assistantClose, timeout: 3).exists {
            app.element(id: UITestA11y.assistantClose).tap()
        }

        app.tapTab(UITestA11y.tabFiles)
        if app.element(id: UITestA11y.filesAssistant, timeout: 5).exists {
            app.element(id: UITestA11y.filesAssistant).tap()
        } else if app.element(id: "assistant.open", timeout: 3).exists {
            app.element(id: "assistant.open").tap()
        }
        if app.element(id: UITestA11y.assistantHistory, timeout: 5).exists {
            app.element(id: UITestA11y.assistantHistory).tap()
            if app.staticTexts["Conversations Mail"].waitForExistence(timeout: 2) {
                XCTFail("SIMULATOR FAIL: isolation Files/Mail cassee")
            }
            saveScreenshot(app, name: "SIMULATOR-scope-files-history")
        }
    }
}
