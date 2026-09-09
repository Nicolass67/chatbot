import XCTest
import SwiftUI
import UIKit
@testable import ChatbotNative

final class ChatSSEParserTests: XCTestCase {
    func testIgnoresCommentLines() {
        XCTAssertNil(ChatSSEParser.parseLine(": heartbeat"))
    }

    func testIgnoresNonDataLines() {
        XCTAssertNil(ChatSSEParser.parseLine("event: token"))
        XCTAssertNil(ChatSSEParser.parseLine(""))
    }

    func testParsesTokenEvent() throws {
        let line = #"data: {"type":"token","content":"Bonjour"}"#
        let event = try XCTUnwrap(ChatSSEParser.parseLine(line))
        XCTAssertEqual(event.type, "token")
        XCTAssertEqual(event.payload["content"] as? String, "Bonjour")
    }

    func testParsesDoneEvent() throws {
        let line = #"data: {"type":"done"}"#
        let event = try XCTUnwrap(ChatSSEParser.parseLine(line))
        XCTAssertEqual(event.type, "done")
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(ChatSSEParser.parseLine("data: {not-json"))
        XCTAssertNil(ChatSSEParser.parseLine(#"data: {"foo":1}"#))
    }
}

final class MarkdownBlockParserTests: XCTestCase {
    func testParsesCodeFence() {
        let md = """
        Intro
        ```swift
        let x = 1
        ```
        Fin
        """
        let blocks = MarkdownBlockParser.parse(md)
        XCTAssertTrue(blocks.contains { if case .code(let lang, let code) = $0 { return lang == "swift" && code.contains("let x") } else { return false } })
    }

    func testParsesHeadingAndBullet() {
        let blocks = MarkdownBlockParser.parse("# Titre\n\n- un\n- deux")
        XCTAssertTrue(blocks.contains { if case .heading(1, let t) = $0 { return t == "Titre" } else { return false } })
        XCTAssertTrue(blocks.contains { if case .bullet(let items) = $0 { return items == ["un", "deux"] } else { return false } })
    }

    func testParsesTable() {
        let md = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
        let blocks = MarkdownBlockParser.parse(md)
        XCTAssertTrue(blocks.contains { if case .table(let h, let rows) = $0 { return h == ["A", "B"] && rows.first == ["1", "2"] } else { return false } })
    }

    func testLongBulletKeepsFullTextWithoutEllipsis() {
        let item = "Sujet principal : un chat long dormant sur un canapé beige près d'une grande fenêtre ensoleillée"
        let blocks = MarkdownBlockParser.parse("## En résumé\n\n- \(item)")
        guard case .bullet(let items) = blocks.last else {
            return XCTFail("attendu un bloc liste")
        }
        XCTAssertEqual(items.first, item)
        XCTAssertFalse(items[0].contains("..."))
        XCTAssertTrue(items[0].contains("fenêtre"))
    }

    func testMixedParagraphListParagraphKeepsAllText() {
        let md = """
        Intro assez longue pour occuper une ligne complète du message assistant.

        - Élément **gras** avec *italique* et une suite très longue qui doit rester entière
        - Second point

        Conclusion après la liste, également assez longue pour plusieurs lignes.
        """
        let blocks = MarkdownBlockParser.parse(md)
        XCTAssertEqual(blocks.count, 3)
        guard case .paragraph(let intro) = blocks[0] else { return XCTFail("intro") }
        guard case .bullet(let items) = blocks[1] else { return XCTFail("liste") }
        guard case .paragraph(let outro) = blocks[2] else { return XCTFail("outro") }
        XCTAssertTrue(intro.contains("Intro assez longue"))
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].contains("**gras**"))
        XCTAssertTrue(items[0].contains("rester entière"))
        XCTAssertTrue(outro.contains("Conclusion"))
    }

    func testNumberedAndQuoteKeepFullText() {
        let numbered = "Une ligne numérotée très longue qui décrit le chat dormant sur le canapé beige"
        let quote = "Citation longue qui doit aussi pouvoir revenir à la ligne dans le message"
        let blocks = MarkdownBlockParser.parse("1. \(numbered)\n\n> \(quote)")
        XCTAssertTrue(blocks.contains { if case .numbered(let items) = $0 { return items == [numbered] } else { return false } })
        XCTAssertTrue(blocks.contains { if case .quote(let text) = $0 { return text == quote } else { return false } })
    }
}

final class MarkdownListRowLayoutTests: XCTestCase {
    func testTextWidthLeavesRoomForMarker() {
        let available = MarkdownListRowLayout.textWidth(containerWidth: 320, markerWidth: 10)
        XCTAssertEqual(available, 320 - 10 - MarkdownListRowLayout.markerSpacing)
        XCTAssertGreaterThan(available, 280)
        XCTAssertLessThan(available, 320)
    }

    func testLayoutContractForbidsSingleLineClip() {
        XCTAssertNil(MarkdownListRowLayout.textLineLimit)
        XCTAssertFalse(MarkdownListRowLayout.clipsOverflow)
        XCTAssertGreaterThan(MarkdownListRowLayout.numberedMarkerMinWidth, 0)
    }

    @MainActor
    func testLongBulletWrapsLikeParagraphOnNarrowWidths() {
        let long = "Sujet principal : un chat long dormant sur un canapé beige près d'une grande fenêtre ensoleillée"
        let widths: [CGFloat] = [280, 320, 375, 430]
        for width in widths {
            let oneLine = MarkdownViewLayoutProbe.height(
                of: MarkdownMessageView(markdown: "Court"),
                width: width
            )
            let paragraph = MarkdownViewLayoutProbe.height(
                of: MarkdownMessageView(markdown: long),
                width: width
            )
            let bullet = MarkdownViewLayoutProbe.height(
                of: MarkdownMessageView(markdown: "- \(long)"),
                width: width
            )
            let numbered = MarkdownViewLayoutProbe.height(
                of: MarkdownMessageView(markdown: "1. \(long)"),
                width: width
            )
            let quote = MarkdownViewLayoutProbe.height(
                of: MarkdownMessageView(markdown: "> \(long)"),
                width: width
            )

            XCTAssertGreaterThan(paragraph, oneLine + 6, "paragraphe doit wrapper à \(width)pt")
            XCTAssertGreaterThan(bullet, oneLine + 6, "li puce doit wrapper à \(width)pt, pas rester sur une ligne")
            XCTAssertGreaterThan(numbered, oneLine + 6, "li numéroté doit wrapper à \(width)pt")
            XCTAssertGreaterThan(quote, oneLine + 6, "citation doit wrapper à \(width)pt")
            XCTAssertEqual(bullet, paragraph, accuracy: 64, "hauteur puce proche du paragraphe à \(width)pt")
        }
    }

    @MainActor
    func testBoldItalicAndLongURLWrapInList() {
        let md = """
        - Texte **gras** et *italique* dans une puce très longue qui doit revenir à la ligne
        - https://example.com/very/long/path/that/has/no-spaces/and-keeps-going/for-a-while/index.html
        """
        let oneLine = MarkdownViewLayoutProbe.height(
            of: MarkdownMessageView(markdown: "- Court"),
            width: 280
        )
        let mixed = MarkdownViewLayoutProbe.height(
            of: MarkdownMessageView(markdown: md),
            width: 280
        )
        XCTAssertGreaterThan(mixed, oneLine * 1.6)
    }

    @MainActor
    func testLongResponseGrowsVerticallyWithoutWidening() {
        var lines = ["Paragraphe d'ouverture assez long pour occuper plusieurs lignes du message assistant."]
        for index in 1...12 {
            lines.append("- Point \(index) : un chat long dormant sur un canapé beige près d'une grande fenêtre ensoleillée")
        }
        lines.append("Conclusion après une longue liste.")
        let size = MarkdownViewLayoutProbe.size(
            of: MarkdownMessageView(markdown: lines.joined(separator: "\n")),
            width: 320
        )
        XCTAssertLessThanOrEqual(size.width, 321)
        XCTAssertGreaterThan(size.height, 240)
    }
}

@MainActor
enum MarkdownViewLayoutProbe {
    static func size(of view: some View, width: CGFloat) -> CGSize {
        let host = UIHostingController(
            rootView: view
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        )
        let target = CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: 10)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: target)
    }

    static func height(of view: some View, width: CGFloat) -> CGFloat {
        size(of: view, width: width).height
    }
}
