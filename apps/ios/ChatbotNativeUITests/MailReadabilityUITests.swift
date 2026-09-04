import XCTest

/// P1b Mail readability — fixtures UITest uniquement (pas de réseau / Gmail).
final class MailReadabilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMailHtmlTextSummaryAndBack() throws {
        let app = XCUIApplication()
        app.launchForUITesting()
        app.assertUITestSession()

        app.tapTab(UITestA11y.tabMail)
        XCTAssertTrue(
            app.element(id: UITestA11y.mailRoot, timeout: 10).exists
                || app.navigationBars["Mail"].waitForExistence(timeout: 5),
            "Mail inbox root"
        )
        XCTAssertTrue(
            app.staticTexts["Votre facture Free du mois"].waitForExistence(timeout: 8),
            "Free invoice fixture in inbox"
        )
        saveScreenshot(app, name: "mail-inbox")

        // HTML-primary mail (short plain → WebView)
        XCTAssertTrue(app.staticTexts["Newsletter HTML"].waitForExistence(timeout: 6))
        app.staticTexts["Newsletter HTML"].tap()
        XCTAssertTrue(app.element(id: "mail.detail", timeout: 10).exists)
        XCTAssertTrue(
            app.element(id: "mail.body.html", timeout: 10).exists
                || app.staticTexts["Version HTML"].waitForExistence(timeout: 6),
            "HTML body mode expected for newsletter fixture"
        )
        // Contraste : le texte forcé sombre d’origine ne doit pas rester #000 brut non sanitisé côté a11y label —
        // on vérifie la présence du mode HTML + caption.
        saveScreenshot(app, name: "mail-detail-html")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Mail"].waitForExistence(timeout: 6))

        // Plain-text fallback (long readable body)
        XCTAssertTrue(app.staticTexts["Texte brut (fallback)"].waitForExistence(timeout: 6))
        app.staticTexts["Texte brut (fallback)"].tap()
        XCTAssertTrue(app.element(id: "mail.detail", timeout: 10).exists)
        XCTAssertTrue(
            app.element(id: "mail.body.plain", timeout: 10).exists
                || app.staticTexts["Version texte"].waitForExistence(timeout: 6),
            "Plain body mode expected"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "plusieurs paragraphes")).firstMatch
                .waitForExistence(timeout: 6),
            "Long plain fixture content must be visible"
        )
        saveScreenshot(app, name: "mail-detail-text")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Mail"].waitForExistence(timeout: 6))

        // Summary Markdown via Free invoice
        XCTAssertTrue(app.staticTexts["Votre facture Free du mois"].waitForExistence(timeout: 6))
        app.staticTexts["Votre facture Free du mois"].tap()
        XCTAssertTrue(app.element(id: "mail.detail", timeout: 10).exists)

        // Open overflow → Résumer
        let overflow = app.navigationBars.buttons["Actions du mail"]
        if overflow.waitForExistence(timeout: 4) {
            overflow.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1).tap()
        }
        let resume = app.buttons["Résumer"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Résumer action required")
        resume.tap()

        let summary = app.element(id: "mail.summary", timeout: 10)
        XCTAssertTrue(summary.exists, "MailSummaryBlock must appear")
        // Markdown rendered: heading text without raw "##" as only content
        XCTAssertTrue(
            app.staticTexts["Résumé"].waitForExistence(timeout: 6),
            "Summary caption / markdown heading"
        )
        XCTAssertFalse(
            app.staticTexts["## Résumé"].exists,
            "Raw markdown heading must not be shown"
        )
        saveScreenshot(app, name: "mail-summary")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.navigationBars["Mail"].waitForExistence(timeout: 6)
                || app.element(id: UITestA11y.mailRoot, timeout: 6).exists,
            "Back to inbox"
        )
        saveScreenshot(app, name: "mail-inbox-after-back")
    }
}
