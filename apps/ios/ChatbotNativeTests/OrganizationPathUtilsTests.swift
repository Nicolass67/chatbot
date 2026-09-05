import XCTest
@testable import ChatbotNative

final class OrganizationPathUtilsTests: XCTestCase {
    func testNormalizeSlashesAndDots() {
        XCTAssertEqual(OrganizationPathUtils.normalize("a//b/./c"), "a/b/c")
        XCTAssertEqual(OrganizationPathUtils.normalize("/a/b/"), "a/b")
        XCTAssertEqual(OrganizationPathUtils.normalize("a/b/../c"), "a/c")
        XCTAssertEqual(OrganizationPathUtils.normalize(""), "")
    }

    func testContainsTraversal() {
        XCTAssertTrue(OrganizationPathUtils.containsTraversal("../secret"))
        XCTAssertTrue(OrganizationPathUtils.containsTraversal("/abs"))
        XCTAssertTrue(OrganizationPathUtils.containsTraversal("foo://bar"))
        XCTAssertFalse(OrganizationPathUtils.containsTraversal("docs/file.pdf"))
    }

    func testIsWithin() {
        XCTAssertTrue(OrganizationPathUtils.isWithin(root: "docs", path: "docs/a.pdf"))
        XCTAssertTrue(OrganizationPathUtils.isWithin(root: "docs", path: "docs"))
        XCTAssertTrue(OrganizationPathUtils.isWithin(root: "", path: "a.pdf"))
        XCTAssertFalse(OrganizationPathUtils.isWithin(root: "docs", path: "other/a.pdf"))
        XCTAssertFalse(OrganizationPathUtils.isWithin(root: "docs", path: "../docs/a.pdf"))
    }

    func testParentJoinDepthBasenameExtension() {
        XCTAssertEqual(OrganizationPathUtils.parent(of: "a/b/c.pdf"), "a/b")
        XCTAssertEqual(OrganizationPathUtils.parent(of: "alone.pdf"), "")
        XCTAssertEqual(OrganizationPathUtils.join("a", "b/c"), "a/b/c")
        XCTAssertEqual(OrganizationPathUtils.join("", "b"), "b")
        XCTAssertEqual(OrganizationPathUtils.depth(of: "a/b/c"), 3)
        XCTAssertEqual(OrganizationPathUtils.depth(of: ""), 0)
        XCTAssertEqual(OrganizationPathUtils.basename(of: "a/b/c.pdf"), "c.pdf")
        XCTAssertEqual(OrganizationPathUtils.fileExtension(of: "Photo.JPEG"), "jpeg")
        XCTAssertEqual(OrganizationPathUtils.fileExtension(of: "Makefile"), "")
    }

    func testParentChildNormalizeRemovesNestedUnderMovedDir() {
        let moves = [
            OrganizationMove(
                sourceRelativePath: "Album",
                destinationRelativePath: "Images/Album",
                operation: .move,
                confidence: 0.9,
                reason: "dir",
                sourceFileId: "1",
                sourceIsDirectory: true,
                needsReview: false,
                excluded: false
            ),
            OrganizationMove(
                sourceRelativePath: "Album/photo.jpg",
                destinationRelativePath: "Images/photo.jpg",
                operation: .move,
                confidence: 0.9,
                reason: "nested",
                sourceFileId: "2",
                sourceIsDirectory: false,
                needsReview: false,
                excluded: false
            ),
        ]
        let normalized = OrganizationPlanValidator.normalizeParentChild(moves: moves)
        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized.first?.sourceRelativePath, "Album")
    }
}
