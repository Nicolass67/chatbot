import XCTest
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
}
