import XCTest
@testable import ChatbotNative

final class LocalModelDescriptorTests: XCTestCase {
    func testPrimaryIsQwen3Q4KM() {
        let m = LocalModelDescriptor.primary
        XCTAssertEqual(m.id, "qwen3-1.7b-q4_k_m")
        XCTAssertEqual(m.filename, "Qwen3-1.7B-Q4_K_M.gguf")
        XCTAssertTrue(m.isDownloadable)
        XCTAssertNotNil(m.downloadURL)
        XCTAssertTrue(m.downloadURL!.absoluteString.contains("Qwen3-1.7B-Q4_K_M.gguf"))
        XCTAssertTrue(m.downloadURL!.absoluteString.contains("second-state"))
        XCTAssertEqual(m.expectedBytes, 1_282_439_264)
    }

    func testFutureModelsNotDownloadableYet() {
        let stubs = LocalModelDescriptor.catalog.filter { $0.id != LocalModelDescriptor.primary.id }
        XCTAssertFalse(stubs.isEmpty)
        for stub in stubs {
            XCTAssertFalse(stub.isDownloadable, stub.id)
            XCTAssertNil(stub.downloadURL, stub.id)
        }
    }
}

final class LocalLLMProviderPromptTests: XCTestCase {
    func testBuildPromptTruncatesOldestMessages() {
        var messages: [LLMChatMessage] = []
        for i in 0..<20 {
            messages.append(LLMChatMessage(role: .user, content: String(repeating: "u\(i)", count: 200)))
            messages.append(LLMChatMessage(role: .assistant, content: String(repeating: "a\(i)", count: 200)))
        }
        let prompt = LocalLLMProvider.buildPrompt(
            system: "SYS",
            messages: messages,
            charBudget: 800
        )
        XCTAssertTrue(prompt.hasPrefix("System: SYS"))
        XCTAssertTrue(prompt.hasSuffix("Assistant:"))
        XCTAssertLessThan(prompt.count, 2000)
        // Les messages les plus récents doivent rester.
        XCTAssertTrue(prompt.contains("u19") || prompt.contains("a19"))
    }
}

final class ExecutionModePreferenceTests: XCTestCase {
    func testPreferenceTitlesExist() {
        for mode in ExecutionModePreference.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.helpText.isEmpty)
        }
    }
}

final class GmailOAuthConfigTests: XCTestCase {
    func testRedirectAndScopes() {
        XCTAssertTrue(GmailOAuthConfig.scopes.contains(where: { $0.contains("gmail.readonly") }))
        XCTAssertTrue(GmailOAuthConfig.scopes.contains(where: { $0.contains("gmail.send") }))
        XCTAssertTrue(GmailOAuthConfig.scopes.contains(where: { $0.contains("gmail.compose") }))
    }

    func testReversedClientIDDerivation() {
        let client = "123-abc.apps.googleusercontent.com"
        XCTAssertEqual(
            GmailOAuthConfig.reversedClientID(from: client),
            "com.googleusercontent.apps.123-abc"
        )
        XCTAssertEqual(
            GmailOAuthConfig.reversedClientID(from: ""),
            ""
        )
    }
}

@MainActor
final class LocalChatStoreTests: XCTestCase {
    func testCreateAppendAndReload() {
        let store = LocalChatStore.shared
        let before = store.conversations.count
        let conv = store.createConversation(title: "UnitTest Conv", scope: .general)
        XCTAssertEqual(conv.title, "UnitTest Conv")
        let msg = store.appendMessage(conversationId: conv.id, role: .user, content: "bonjour")
        XCTAssertNotNil(msg)
        let loaded = store.messages(for: conv.id)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "bonjour")
        store.deleteConversation(id: conv.id)
        XCTAssertEqual(store.conversations.count, before)
    }
}

final class LocalModelStateTests: XCTestCase {
    func testStatusLabels() {
        XCTAssertEqual(LocalModelInstallState.notInstalled.statusLabel, "Non installé")
        XCTAssertTrue(LocalModelInstallState.downloading(progress: 0.5).isBusy)
        XCTAssertFalse(LocalModelInstallState.ready.isBusy)
        XCTAssertEqual(EffectiveExecutionMode.local.rawValue, "local")
    }
}

final class LocalModelFileAuditTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalModelFileAuditTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    /// État « installé » présent conceptuellement mais fichier GGUF absent → non installé.
    func testMissingFileIsNotInstalled() {
        let url = tempDir.appendingPathComponent("Qwen3-1.7B-Q4_K_M.gguf")
        let expected = LocalModelDescriptor.primary.expectedBytes
        let probe = LocalModelFileAudit.probe(at: url, expectedBytes: expected)
        XCTAssertEqual(probe, .missing)
        XCTAssertFalse(probe.isFullyInstalled)
        // Charger doit être impossible tant que isFullyInstalled == false (aucun appel llama).
    }

    /// Téléchargement terminé : fichier présent, taille correcte, magic GGUF → installed.
    func testValidGGUFFileIsInstalled() throws {
        let expected: Int64 = 1_024
        let url = tempDir.appendingPathComponent("model.gguf")
        var data = Data("GGUF".utf8)
        data.append(Data(repeating: 0xAB, count: Int(expected) - 4))
        try data.write(to: url)

        let probe = LocalModelFileAudit.probe(at: url, expectedBytes: expected)
        guard case .installed(let size) = probe else {
            return XCTFail("expected installed, got \(probe)")
        }
        XCTAssertEqual(size, expected)
        XCTAssertTrue(probe.isFullyInstalled)
        XCTAssertTrue(LocalModelFileAudit.isGGUFMagic(at: url))
    }

    func testWrongMagicIsInvalidNotInstalled() throws {
        let expected: Int64 = 1_024
        let url = tempDir.appendingPathComponent("bad.gguf")
        var data = Data("XXXX".utf8)
        data.append(Data(repeating: 0x00, count: Int(expected) - 4))
        try data.write(to: url)

        let probe = LocalModelFileAudit.probe(at: url, expectedBytes: expected)
        guard case .invalid(_, let sizeOK, let magicOK) = probe else {
            return XCTFail("expected invalid, got \(probe)")
        }
        XCTAssertTrue(sizeOK)
        XCTAssertFalse(magicOK)
        XCTAssertFalse(probe.isFullyInstalled)
    }

    func testWrongSizeIsInvalidNotInstalled() throws {
        let expected: Int64 = 10_000
        let url = tempDir.appendingPathComponent("small.gguf")
        try Data("GGUF".utf8).write(to: url) // 4 bytes only

        let probe = LocalModelFileAudit.probe(at: url, expectedBytes: expected)
        guard case .invalid(_, let sizeOK, let magicOK) = probe else {
            return XCTFail("expected invalid, got \(probe)")
        }
        XCTAssertFalse(sizeOK)
        XCTAssertTrue(magicOK)
        XCTAssertFalse(probe.isFullyInstalled)
    }

    func testValidateSizeTolerance() {
        let expected: Int64 = 1_000_000
        XCTAssertTrue(LocalModelFileAudit.validateSize(1_000_000, expected: expected))
        XCTAssertTrue(LocalModelFileAudit.validateSize(1_049_000, expected: expected)) // +4.9%
        XCTAssertFalse(LocalModelFileAudit.validateSize(1_100_000, expected: expected)) // +10%
        XCTAssertFalse(LocalModelFileAudit.validateSize(0, expected: expected))
    }

    func testGGUFMagicPrefixHelper() {
        XCTAssertTrue(LocalModelFileAudit.isGGUFMagic(dataPrefix: Data("GGUF....".utf8)))
        XCTAssertFalse(LocalModelFileAudit.isGGUFMagic(dataPrefix: Data("GGU".utf8)))
        XCTAssertFalse(LocalModelFileAudit.isGGUFMagic(dataPrefix: Data("HTML".utf8)))
    }
}

@MainActor
final class LocalModelManagerPresenceTests: XCTestCase {
    /// Si le disque n’a pas le GGUF, `isInstalled` est false même si l’état UI avait pu être « Installé ».
    func testSharedManagerReportsNotInstalledWhenFileAbsent() {
        let mgr = LocalModelManager.shared
        mgr.refreshInstalledState()
        // Sur machine de test / simulateur CI, le GGUF n’est pas livré avec l’IPA.
        if !FileManager.default.fileExists(atPath: mgr.modelFilePath) {
            XCTAssertFalse(mgr.isInstalled)
            XCTAssertEqual(mgr.state, .notInstalled)
            XCTAssertEqual(mgr.installedBytes, 0)
        }
    }
}
