import XCTest

/// P9 Mail draft — Modifier / Réessayer / Envoyer (fixtures UITest, pas d’envoi réel).
final class MailDraftUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSuggestReplyDraftEditAndConfirm() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabMail)
        XCTAssertTrue(app.staticTexts["Votre facture Free du mois"].waitForExistence(timeout: 8))
        app.staticTexts["Votre facture Free du mois"].tap()
        XCTAssertTrue(app.element(id: "mail.detail", timeout: 10).exists)

        let overflow = app.navigationBars.buttons.matching(identifier: "mail.overflow").firstMatch
        if overflow.waitForExistence(timeout: 4) {
            overflow.tap()
        } else {
            let byLabel = app.navigationBars.buttons["Actions du mail"]
            if byLabel.waitForExistence(timeout: 3) {
                byLabel.tap()
            } else if app.navigationBars.buttons.count > 0 {
                app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1).tap()
            }
        }

        let suggest = app.buttons["Préparer une réponse"]
        XCTAssertTrue(suggest.waitForExistence(timeout: 5), "Préparer une réponse")
        suggest.tap()

        let draft = app.element(id: "mail.draft", timeout: 10)
        XCTAssertTrue(draft.exists, "MailDraftProposal must appear")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "brouillon UITest")).firstMatch
                .waitForExistence(timeout: 6),
            "Draft body fixture visible"
        )
        saveScreenshot(app, name: "mail-draft")

        let edit = app.buttons["Modifier"]
        XCTAssertTrue(edit.waitForExistence(timeout: 4), "Modifier control")
        edit.tap()
        let editor = app.element(id: "mail.draft.editor", timeout: 6)
        XCTAssertTrue(
            editor.exists
                || app.textViews.firstMatch.waitForExistence(timeout: 4)
                || app.textFields.firstMatch.waitForExistence(timeout: 2),
            "Draft editor"
        )
        saveScreenshot(app, name: "mail-draft-editing")
        if app.buttons["OK"].exists {
            app.buttons["OK"].tap()
        } else if edit.exists {
            edit.tap()
        }

        let send = app.buttons["Envoyer"].firstMatch
        XCTAssertTrue(
            send.waitForExistence(timeout: 6)
                || app.element(id: "mail.send", timeout: 3).exists,
            "Envoyer"
        )
        if send.exists {
            send.tap()
        } else {
            app.tapFirst(id: "mail.send")
        }
        // Confirm alert
        let confirm = app.alerts.buttons["Envoyer"]
        if confirm.waitForExistence(timeout: 4) {
            confirm.tap()
        }
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "envoyé")).firstMatch
                .waitForExistence(timeout: 8)
                || app.staticTexts["Message envoyé."].waitForExistence(timeout: 4),
            "Send confirmation status expected (UITest stub)"
        )
        saveScreenshot(app, name: "mail-draft-sent")
    }
}
