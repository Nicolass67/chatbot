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
        XCTAssertTrue(assertInbox(app), "Mail inbox root")
        XCTAssertTrue(
            app.staticTexts["Votre facture Free du mois"].waitForExistence(timeout: 8),
            "Free invoice fixture in inbox"
        )
        saveScreenshot(app, name: "mail-inbox")

        // HTML-primary mail (short plain → WebView)
        openMail(app, subject: "Newsletter HTML")
        XCTAssertTrue(app.element(id: "mail.detail", timeout: 10).exists)
        let htmlBody = app.element(id: "mail.body.html", timeout: 10)
        XCTAssertTrue(
            htmlBody.exists || app.staticTexts["Version HTML"].waitForExistence(timeout: 6),
            "HTML body mode expected for newsletter fixture"
        )
        // Laisser WKWebView charger + remesurer avant le screenshot DoD.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        if htmlBody.exists {
            let value = htmlBody.value as? String ?? ""
            XCTAssertTrue(
                value.localizedCaseInsensitiveContains("Contenu")
                    || value.localizedCaseInsensitiveContains("HTML")
                    || value.localizedCaseInsensitiveContains("Newsletter")
                    || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Contenu")).firstMatch
                        .waitForExistence(timeout: 2),
                "HTML a11y value / visible content expected after sanitize"
            )
        }
        saveScreenshot(app, name: "mail-detail-html")
        popToInbox(app)

        // Plain-text fallback (long readable body)
        openMail(app, subject: "Texte brut (fallback)")
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
        popToInbox(app)

        // Summary Markdown via Free invoice
        openMail(app, subject: "Votre facture Free du mois")
        XCTAssertTrue(app.element(id: "mail.detail", timeout: 10).exists)

        let overflow = app.navigationBars.buttons["Actions du mail"]
        if overflow.waitForExistence(timeout: 4) {
            overflow.tap()
        } else if app.navigationBars.buttons.count > 0 {
            app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1).tap()
        }
        let resume = app.buttons["Résumer"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Résumer action required")
        resume.tap()

        let summary = app.element(id: "mail.summary", timeout: 10)
        XCTAssertTrue(summary.exists, "MailSummaryBlock must appear")
        XCTAssertTrue(
            app.staticTexts["Résumé"].waitForExistence(timeout: 6),
            "Summary caption / markdown heading"
        )
        XCTAssertFalse(
            app.staticTexts["## Résumé"].exists,
            "Raw markdown heading must not be shown"
        )
        saveScreenshot(app, name: "mail-summary")

        popToInbox(app)
        saveScreenshot(app, name: "mail-inbox-after-back")
    }

    @discardableResult
    private func assertInbox(_ app: XCUIApplication) -> Bool {
        // Titre large « Mail » = racine inbox (pas le détail dont le titre = sujet).
        app.navigationBars["Mail"].waitForExistence(timeout: 3)
            || (
                app.element(id: UITestA11y.mailRoot, timeout: 2).exists
                    && app.searchFields.firstMatch.exists
            )
    }

    private func openMail(_ app: XCUIApplication, subject: String) {
        if !assertInbox(app) {
            popToInbox(app)
        }
        XCTAssertTrue(app.staticTexts[subject].waitForExistence(timeout: 6), "Missing \(subject)")
        app.staticTexts[subject].tap()
    }

    private func popToInbox(_ app: XCUIApplication) {
        for _ in 0..<5 {
            if app.navigationBars["Mail"].waitForExistence(timeout: 1.2) {
                return
            }
            if app.navigationBars.buttons["Back"].exists {
                app.navigationBars.buttons["Back"].tap()
                continue
            }
            if app.navigationBars.buttons.count > 0 {
                app.navigationBars.buttons.element(boundBy: 0).tap()
                continue
            }
            break
        }
        // Dernier recours : retaper l’onglet Mail (recharge la racine).
        app.tapTab(UITestA11y.tabChat)
        app.tapTab(UITestA11y.tabMail)
        XCTAssertTrue(
            app.navigationBars["Mail"].waitForExistence(timeout: 6)
                || app.element(id: UITestA11y.mailRoot, timeout: 4).exists,
            "Back to inbox after tab bounce"
        )
    }
}
