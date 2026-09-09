import XCTest
@testable import ChatbotNative

final class RuntimeTemporalContextTests: XCTestCase {
    func testSilentClockIncludesCurrentYearWithoutUserFacingWording() {
        let fixed = ISO8601DateFormatter().date(from: "2026-09-10T10:00:00Z")!
        let block = RuntimeTemporalContext.silentClockBlock(now: fixed)
        XCTAssertTrue(block.contains("2026"))
        XCTAssertTrue(block.contains("Année en cours"))
        XCTAssertTrue(block.contains("ne le mentionne pas"))
        XCTAssertFalse(block.lowercased().contains("bonjour"))
    }

    func testGroundWebQueryAppendsYearForCurrentHints() {
        let fixed = ISO8601DateFormatter().date(from: "2026-09-10T10:00:00Z")!
        let q = RuntimeTemporalContext.groundWebQuery(
            "meilleur prix carte graphique actuelle",
            now: fixed
        )
        XCTAssertTrue(q.contains("2026"))
        let already = RuntimeTemporalContext.groundWebQuery("prix RTX 2025", now: fixed)
        XCTAssertEqual(already, "prix RTX 2025")
        let plain = RuntimeTemporalContext.groundWebQuery("histoire de Rome", now: fixed)
        XCTAssertEqual(plain, "histoire de Rome")
    }

    func testClampPlanToFourSteps() {
        let many = (1...7).map {
            AgentPlanStep(id: "s\($0)", title: "Étape numéro \($0) concrète", status: "pending")
        }
        let clamped = AgentWorkflow.clampPlanSteps(many)
        XCTAssertLessThanOrEqual(clamped.count, 4)
        XCTAssertGreaterThanOrEqual(clamped.count, 1)
    }

    func testCompareFallbackIsThreeSteps() {
        let plan = AgentWorkflow.goalAwareFallbackPlan(
            userText: "Quelle est la meilleure option A vs B ?",
            firstTool: AIToolCall(action: "web_search", arguments: ["query": "A vs B"])
        )
        XCTAssertEqual(plan.count, 3)
    }
}
