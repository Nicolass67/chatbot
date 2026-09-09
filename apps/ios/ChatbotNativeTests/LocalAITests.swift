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
    func testBuildPromptUsesChatMLAndAssistantGenerationPrompt() {
        let messages = [
            LLMChatMessage(role: .user, content: "Test"),
            LLMChatMessage(role: .assistant, content: "Salut"),
            LLMChatMessage(role: .user, content: "Suite"),
        ]
        let prompt = LocalLLMProvider.buildPrompt(
            system: "SYS",
            messages: messages,
            charBudget: 8_000
        )
        XCTAssertTrue(prompt.contains("<|im_start|>system"))
        XCTAssertTrue(prompt.contains("SYS"))
        XCTAssertTrue(prompt.contains("<|im_end|>"))
        XCTAssertTrue(prompt.contains("<|im_start|>user\nTest\n<|im_end|>"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant\nSalut\n<|im_end|>"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n"))
        XCTAssertFalse(prompt.hasPrefix("System:"))
        XCTAssertFalse(prompt.contains("\nUser: Test"))
    }

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
        XCTAssertTrue(prompt.contains("<|im_start|>system"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n"))
        XCTAssertLessThan(prompt.count, 2000)
        XCTAssertTrue(prompt.contains("u19") || prompt.contains("a19"))
    }
}

final class ChatMLStopTruncationTests: XCTestCase {
    func testStopsOnImEndAndKeepsAnswer() {
        let raw = "Bonjour, je suis l'assistant.<|im_end|>\n<|im_start|>user\nTest"
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertTrue(cut.hitStop)
        XCTAssertEqual(cut.text, "Bonjour, je suis l'assistant.")
    }

    func testStopsOnImStartNewTurn() {
        let raw = "Réponse utile\n<|im_start|>user\nEncore"
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertTrue(cut.hitStop)
        XCTAssertEqual(cut.text, "Réponse utile")
    }

    func testStopsOnLegacyUserTurnBoundary() {
        let raw = "Bonjour mode local.\nUser: Test\nAssistant: encore"
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertTrue(cut.hitStop)
        XCTAssertEqual(cut.text, "Bonjour mode local.")
    }

    func testDoesNotTruncateUserWordMidSentence() {
        let raw = "Le compte User:admin est invalide."
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertFalse(cut.hitStop)
        XCTAssertEqual(cut.text, raw)
    }

    func testNormalAnswerPreservedEntirely() {
        let raw = "Voici une réponse complète sans faux tour."
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertFalse(cut.hitStop)
        XCTAssertEqual(cut.text, raw)
    }
}

final class ChatSendGateTests: XCTestCase {
    func testSingleBeginAllowsOneGenerationSlot() {
        var sending = false
        XCTAssertTrue(ChatSendGate.tryBegin(isSending: &sending))
        XCTAssertTrue(sending)
        XCTAssertFalse(ChatSendGate.tryBegin(isSending: &sending))
        sending = false
        XCTAssertTrue(ChatSendGate.tryBegin(isSending: &sending))
    }

    func testDoubleTapSecondRejected() {
        var sending = false
        var generations = 0
        if ChatSendGate.tryBegin(isSending: &sending) { generations += 1 }
        if ChatSendGate.tryBegin(isSending: &sending) { generations += 1 }
        XCTAssertEqual(generations, 1)
        XCTAssertTrue(sending)
    }
}

final class LocalModelAutoLoadPolicyTests: XCTestCase {
    func testLoadsWhenLocalInstalledNotReady() {
        XCTAssertTrue(
            LocalModelAutoLoadPolicy.shouldAttemptLoad(
                wantsLocalExecution: true,
                isInstalled: true,
                isReady: false,
                exclusiveBusy: false,
                isLoading: false
            )
        )
    }

    func testSkipsWhenAlreadyReady() {
        XCTAssertFalse(
            LocalModelAutoLoadPolicy.shouldAttemptLoad(
                wantsLocalExecution: true,
                isInstalled: true,
                isReady: true,
                exclusiveBusy: false,
                isLoading: false
            )
        )
    }

    func testSkipsWhenNotInstalledNoDownload() {
        XCTAssertFalse(
            LocalModelAutoLoadPolicy.shouldAttemptLoad(
                wantsLocalExecution: true,
                isInstalled: false,
                isReady: false,
                exclusiveBusy: false,
                isLoading: false
            )
        )
    }

    func testSkipsWhenRemoteMode() {
        XCTAssertFalse(
            LocalModelAutoLoadPolicy.shouldAttemptLoad(
                wantsLocalExecution: false,
                isInstalled: true,
                isReady: false,
                exclusiveBusy: false,
                isLoading: false
            )
        )
    }

    func testSkipsWhenExclusiveOrLoading() {
        XCTAssertFalse(
            LocalModelAutoLoadPolicy.shouldAttemptLoad(
                wantsLocalExecution: true,
                isInstalled: true,
                isReady: false,
                exclusiveBusy: true,
                isLoading: false
            )
        )
        XCTAssertFalse(
            LocalModelAutoLoadPolicy.shouldAttemptLoad(
                wantsLocalExecution: true,
                isInstalled: true,
                isReady: false,
                exclusiveBusy: false,
                isLoading: true
            )
        )
    }
}

final class ExecutionModePreferenceTests: XCTestCase {
    func testPreferenceTitlesExist() {
        for mode in ExecutionModePreference.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.helpText.isEmpty)
        }
    }

    func testPrefersOnDeviceWhenForceLocalEvenIfNotReady() {
        // forceLocal → prefersOnDevice indépendamment de isReady (boot local sans PC).
        XCTAssertEqual(ExecutionModePreference.forceLocal.title, "Toujours local")
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

@MainActor
final class LocalModelManagerConcurrencyTests: XCTestCase {
    private var mgr: LocalModelManager { LocalModelManager.shared }

    override func tearDown() async throws {
        // Libère tout verrou de test pour ne pas polluer les autres suites.
        if let op = mgr.exclusiveOperation {
            mgr.endExclusive(op)
        }
        try await super.tearDown()
    }

    /// load tenu → delete refusé ; fichier inchangé (pas de suppression silencieuse).
    func testDeleteRefusedWhileLoadExclusive() async {
        let existed = mgr.actualFileExists
        let sizeBefore = mgr.actualFileSize
        let stateBefore = mgr.state
        XCTAssertTrue(mgr.beginExclusive(.load))
        XCTAssertEqual(mgr.exclusiveOperation, .load)

        await mgr.deleteModel()

        XCTAssertEqual(mgr.exclusiveOperation, .load)
        XCTAssertEqual(mgr.actualFileExists, existed)
        XCTAssertEqual(mgr.actualFileSize, sizeBefore)
        XCTAssertEqual(mgr.state, stateBefore)
        guard let err = mgr.lastError else {
            return XCTFail("expected lastError on refused delete")
        }
        XCTAssertTrue(err.contains("load"), err)
        XCTAssertTrue(err.contains("delete"), err)
        mgr.endExclusive(.load)
    }

    /// delete tenu → load refusé (déterministe).
    func testLoadRefusedWhileDeleteExclusive() async {
        XCTAssertTrue(mgr.beginExclusive(.delete))
        await mgr.loadIntoEngine()
        XCTAssertEqual(mgr.exclusiveOperation, .delete)
        guard let err = mgr.lastError else {
            return XCTFail("expected lastError on refused load")
        }
        XCTAssertTrue(err.contains("delete"), err)
        XCTAssertTrue(err.contains("load"), err)
        mgr.endExclusive(.delete)
    }

    /// load tenu → install refusé (pas de replace/remove pendant load).
    func testInstallRefusedWhileLoadExclusive() async {
        let existed = mgr.actualFileExists
        let sizeBefore = mgr.actualFileSize
        XCTAssertTrue(mgr.beginExclusive(.load))
        await mgr.install()
        XCTAssertEqual(mgr.exclusiveOperation, .load)
        XCTAssertEqual(mgr.actualFileExists, existed)
        XCTAssertEqual(mgr.actualFileSize, sizeBefore)
        guard let err = mgr.lastError else {
            return XCTFail("expected lastError on refused install")
        }
        XCTAssertTrue(err.contains("load"), err)
        XCTAssertTrue(err.contains("install"), err)
        mgr.endExclusive(.load)
    }

    /// Deux delete : un seul peut tenir le verrou et supprimer.
    func testSecondDeleteRefusedWhileFirstHoldsExclusive() async {
        XCTAssertTrue(mgr.beginExclusive(.delete))
        await mgr.deleteModel()
        XCTAssertEqual(mgr.exclusiveOperation, .delete)
        guard let err = mgr.lastError else {
            return XCTFail("expected lastError on second delete")
        }
        XCTAssertTrue(err.contains("delete"), err)
        mgr.endExclusive(.delete)
    }

    /// Deux load : le second est refusé tant que le premier tient le verrou.
    func testSecondLoadRefusedWhileFirstHoldsExclusive() async {
        XCTAssertTrue(mgr.beginExclusive(.load))
        await mgr.loadIntoEngine()
        XCTAssertEqual(mgr.exclusiveOperation, .load)
        guard let err = mgr.lastError else {
            return XCTFail("expected lastError on second load")
        }
        XCTAssertTrue(err.contains("load"), err)
        mgr.endExclusive(.load)
    }

    /// busyAction UI n’existe pas sur le manager — la protection est `exclusiveOperation`.
    func testExclusiveGateIsManagerOwnedNotBusyAction() {
        XCTAssertNil(mgr.exclusiveOperation)
        XCTAssertTrue(mgr.beginExclusive(.unload))
        XCTAssertEqual(mgr.exclusiveOperation, .unload)
        XCTAssertFalse(mgr.beginExclusive(.delete))
        mgr.endExclusive(.unload)
        XCTAssertNil(mgr.exclusiveOperation)
    }

    /// Task UI concurrente : même sans busyAction, le 2ᵉ entrée manager est refusée.
    func testConcurrentTasksCannotBypassExclusiveGate() async {
        XCTAssertTrue(mgr.beginExclusive(.load))
        async let deniedDelete: Void = mgr.deleteModel()
        async let deniedInstall: Void = mgr.install()
        _ = await (deniedDelete, deniedInstall)
        XCTAssertEqual(mgr.exclusiveOperation, .load)
        XCTAssertNotNil(mgr.lastError)
        mgr.endExclusive(.load)
    }
}

/// Concurrence UI / exclusive — inchangé par le fix hit-test `.borderless` (List row).
final class LocalAISettingsActionGateTests: XCTestCase {
    func testBusyActionBlocksBeforeTaskWouldStart() {
        XCTAssertFalse(
            LocalAISettingsActionGate.allowsNewMutationTask(
                busyAction: true,
                exclusiveOperation: nil,
                state: .installed
            )
        )
    }

    func testExclusiveDeleteBlocksCharger() {
        XCTAssertFalse(
            LocalAISettingsActionGate.allowsNewMutationTask(
                busyAction: false,
                exclusiveOperation: .delete,
                state: .installed
            )
        )
    }

    func testExclusiveLoadBlocksDelete() {
        XCTAssertFalse(
            LocalAISettingsActionGate.allowsNewMutationTask(
                busyAction: false,
                exclusiveOperation: .load,
                state: .loading
            )
        )
    }

    func testUnloadingDisablesMutations() {
        XCTAssertFalse(
            LocalAISettingsActionGate.allowsNewMutationTask(
                busyAction: false,
                exclusiveOperation: nil,
                state: .unloading
            )
        )
    }

    func testInstalledIdleAllowsMutation() {
        XCTAssertTrue(
            LocalAISettingsActionGate.allowsNewMutationTask(
                busyAction: false,
                exclusiveOperation: nil,
                state: .installed
            )
        )
    }

    /// Simule double-tap : 1er pose busy, 2ᵉ refuse — un seul Task serait créé.
    func testSecondTapRejectedAfterBusySetSynchronously() {
        var busy = false
        func beginUIAction() -> Bool {
            guard LocalAISettingsActionGate.allowsNewMutationTask(
                busyAction: busy,
                exclusiveOperation: nil,
                state: .installed
            ) else { return false }
            busy = true
            return true
        }
        XCTAssertTrue(beginUIAction())
        XCTAssertTrue(busy)
        XCTAssertFalse(beginUIAction())
    }

    /// Supprimer puis Charger : busy posé → 2ᵉ action refusée (même contrat que beginUIAction).
    func testDeleteThenChargeBlockedByBusy() {
        var busy = false
        func begin() -> Bool {
            guard LocalAISettingsActionGate.allowsNewMutationTask(
                busyAction: busy,
                exclusiveOperation: nil,
                state: .installed
            ) else { return false }
            busy = true
            return true
        }
        XCTAssertTrue(begin()) // Supprimer
        XCTAssertFalse(begin()) // Charger immédiat
    }

    /// Charger puis Supprimer bloqué idem.
    func testChargeThenDeleteBlockedByBusy() {
        var busy = false
        func begin() -> Bool {
            guard LocalAISettingsActionGate.allowsNewMutationTask(
                busyAction: busy,
                exclusiveOperation: nil,
                state: .installed
            ) else { return false }
            busy = true
            return true
        }
        XCTAssertTrue(begin()) // Charger
        XCTAssertFalse(begin()) // Supprimer immédiat
    }
}


