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
