import XCTest
@testable import ChatbotNative

final class OrganizationPlanValidatorTests: XCTestCase {
    private func inventory(root: String, items: [OrganizationInventoryItem]) -> OrganizationInventory {
        OrganizationInventory(
            scope: .root(rootId: "r1", relativePath: root, displayName: "Root"),
            items: items,
            scannedAt: Date()
        )
    }

    private func fileItem(path: String, fileId: String = "f1") -> OrganizationInventoryItem {
        let name = OrganizationPathUtils.basename(of: path)
        return OrganizationInventoryItem(
            fileId: fileId,
            name: name,
            relativePath: path,
            isDirectory: false,
            extensionLower: OrganizationPathUtils.fileExtension(of: name),
            sizeBytes: 10,
            mtimeMs: nil,
            parentRelativePath: OrganizationPathUtils.parent(of: path),
            depth: OrganizationPathUtils.depth(of: path)
        )
    }

    private func basePlan(
        root: String = "",
        moves: [OrganizationMove],
        protected: [ProtectedStructure] = []
    ) -> OrganizationPlan {
        OrganizationPlan(
            id: "p1",
            rootId: "r1",
            rootRelativePath: root,
            createdAt: Date(),
            summary: "test",
            protectedStructures: protected,
            proposedDirectories: ["Factures"],
            moves: moves,
            warnings: [],
            conflicts: [],
            confidence: 0.9,
            userInstruction: nil
        )
    }

    private func move(
        _ source: String,
        to dest: String,
        fileId: String = "f1",
        confidence: Double = 0.9,
        isDir: Bool = false
    ) -> OrganizationMove {
        OrganizationMove(
            sourceRelativePath: source,
            destinationRelativePath: dest,
            operation: .move,
            confidence: confidence,
            reason: "test",
            sourceFileId: fileId,
            sourceIsDirectory: isDir,
            needsReview: confidence < OrganizationConfidence.autoExecuteMinimum,
            excluded: false
        )
    }

    func testValidMove() {
        let inv = inventory(root: "", items: [fileItem(path: "facture.pdf")])
        let plan = basePlan(moves: [move("facture.pdf", to: "Factures/facture.pdf")])
        let result = OrganizationPlanValidator.validate(
            plan: plan,
            inventory: inv,
            existingRelativePaths: Set(inv.items.map(\.relativePath))
        )
        guard case .success(let ok) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(ok.moves.count, 1)
        XCTAssertFalse(ok.moves[0].needsReview)
        XCTAssertEqual(ok.moves[0].sourceRelativePath, "facture.pdf")
    }

    func testDeleteOpRejectAsUnknownOperation() {
        // OrganizationOperation n’expose que `.move` ; le validateur rejette toute autre op
        // via `.unknownOperation`. On vérifie le contrat d’erreur + qu’un plan vide échoue.
        let inv = inventory(root: "", items: [fileItem(path: "a.pdf")])
        let empty = basePlan(moves: [])
        let result = OrganizationPlanValidator.validate(
            plan: empty,
            inventory: inv,
            existingRelativePaths: ["a.pdf"]
        )
        guard case .failure(let errs) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(errs.contains(.emptyPlan) || errs.contains { if case .emptyPlan = $0 { return true }; return false })
        XCTAssertEqual(OrganizationValidationError.unknownOperation("delete").errorDescription,
                       "Opération non autorisée : delete.")
    }

    func testSourceOutsideRoot() {
        let inv = inventory(root: "docs", items: [fileItem(path: "docs/a.pdf")])
        let plan = basePlan(root: "docs", moves: [move("other/a.pdf", to: "docs/Factures/a.pdf")])
        let result = OrganizationPlanValidator.validate(
            plan: plan,
            inventory: inv,
            existingRelativePaths: ["docs/a.pdf"]
        )
        guard case .failure(let errs) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(errs.contains { if case .sourceOutsideRoot = $0 { return true }; return false })
    }

    func testDestinationOutsideRoot() {
        let inv = inventory(root: "docs", items: [fileItem(path: "docs/a.pdf")])
        let plan = basePlan(root: "docs", moves: [move("docs/a.pdf", to: "other/a.pdf")])
        let result = OrganizationPlanValidator.validate(
            plan: plan,
            inventory: inv,
            existingRelativePaths: ["docs/a.pdf"]
        )
        guard case .failure(let errs) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(errs.contains { if case .destinationOutsideRoot = $0 { return true }; return false })
    }

    func testPathTraversal() {
        let inv = inventory(root: "", items: [fileItem(path: "a.pdf")])
        let plan = basePlan(moves: [move("../a.pdf", to: "Factures/a.pdf")])
        let result = OrganizationPlanValidator.validate(
            plan: plan,
            inventory: inv,
            existingRelativePaths: ["a.pdf"]
        )
        guard case .failure(let errs) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(errs.contains { if case .pathTraversal = $0 { return true }; return false })
    }

    func testProtectedSource() {
        let inv = inventory(root: "", items: [
            OrganizationInventoryItem(
                fileId: "d1",
                name: "node_modules",
                relativePath: "node_modules",
                isDirectory: true,
                extensionLower: "",
                sizeBytes: 0,
                mtimeMs: nil,
                parentRelativePath: "",
                depth: 1
            ),
            fileItem(path: "node_modules/pkg.js", fileId: "f2"),
        ])
        let protected = [
            ProtectedStructure(
                relativePath: "node_modules",
                name: "node_modules",
                level: .protected,
                reason: "tech",
                manual: false
            ),
        ]
        let plan = basePlan(
            moves: [move("node_modules/pkg.js", to: "A classer/pkg.js", fileId: "f2")],
            protected: protected
        )
        let result = OrganizationPlanValidator.validate(
            plan: plan,
            inventory: inv,
            existingRelativePaths: Set(inv.items.map(\.relativePath))
        )
        guard case .failure(let errs) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(errs.contains { if case .protectedSource = $0 { return true }; return false })
    }

    func testCollision() {
        let inv = inventory(root: "", items: [
            fileItem(path: "a.pdf", fileId: "f1"),
            fileItem(path: "Factures/a.pdf", fileId: "f2"),
        ])
        let plan = basePlan(moves: [move("a.pdf", to: "Factures/a.pdf")])
        let result = OrganizationPlanValidator.validate(
            plan: plan,
            inventory: inv,
            existingRelativePaths: Set(inv.items.map(\.relativePath))
        )
        guard case .failure(let errs) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(errs.contains { if case .collision = $0 { return true }; return false })
    }

    func testDuplicateSource() {
        let inv = inventory(root: "", items: [fileItem(path: "a.pdf")])
        let plan = basePlan(moves: [
            move("a.pdf", to: "Factures/a.pdf"),
            move("a.pdf", to: "Contrats/a.pdf"),
        ])
        let result = OrganizationPlanValidator.validate(
            plan: plan,
            inventory: inv,
            existingRelativePaths: ["a.pdf"]
        )
        guard case .failure(let errs) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(errs.contains { if case .duplicateSource = $0 { return true }; return false })
    }

    func testContradictoryMoves() {
        let inv = inventory(root: "", items: [
            fileItem(path: "a.pdf", fileId: "f1"),
            fileItem(path: "b.pdf", fileId: "f2"),
        ])
        let plan = basePlan(moves: [
            move("a.pdf", to: "b.pdf", fileId: "f1"),
            move("b.pdf", to: "a.pdf", fileId: "f2"),
        ])
        let result = OrganizationPlanValidator.validate(
            plan: plan,
            inventory: inv,
            existingRelativePaths: ["a.pdf", "b.pdf"]
        )
        guard case .failure(let errs) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(errs.contains { if case .contradictoryMoves = $0 { return true }; return false })
    }

    func testEmptyFolderHeuristic() {
        let inv = inventory(root: "", items: [])
        XCTAssertThrowsError(
            try OrganizationHeuristicPlanner.propose(inventory: inv, protected: [])
        ) { error in
            guard let e = error as? OrganizationEngineError else {
                return XCTFail("wrong error type")
            }
            guard case .emptyFolder = e else {
                return XCTFail("expected emptyFolder, got \(e)")
            }
        }
    }

    func testHeuristicOnlyRootLevelFiles() throws {
        let inv = inventory(root: "", items: [
            fileItem(path: "facture-janvier.pdf", fileId: "f1"),
            fileItem(path: "Images/old.png", fileId: "f2"),
        ])
        let plan = try OrganizationHeuristicPlanner.propose(inventory: inv, protected: [])
        XCTAssertEqual(plan.moves.count, 1)
        XCTAssertEqual(plan.moves[0].sourceRelativePath, "facture-janvier.pdf")
        XCTAssertTrue(plan.moves[0].destinationRelativePath.hasPrefix("Factures/"))
    }
}
