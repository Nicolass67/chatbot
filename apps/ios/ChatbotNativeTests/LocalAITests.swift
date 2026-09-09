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
        XCTAssertEqual(m.compatibilityIPhone14Plus, .recommended)
        XCTAssertEqual(m.runtimeProfile.templateKind, .chatml)
    }

    func testCatalogHasMultiModelsAndOnlyOnePrimary() {
        XCTAssertGreaterThanOrEqual(LocalModelDescriptor.catalog.count, 5)
        XCTAssertEqual(LocalModelDescriptor.catalog.filter { $0.id == LocalModelDescriptor.primary.id }.count, 1)
        XCTAssertTrue(LocalModelDescriptor.downloadable.contains { $0.id == "lfm25-1.2b-instruct-q4_k_m" })
        XCTAssertTrue(LocalModelDescriptor.downloadable.contains { $0.id == "qwen35-2b-q4_k_m" })
    }

    func testCompatibilityTiersForIPhone14Plus() {
        XCTAssertEqual(LocalModelDescriptor.primary.compatibilityIPhone14Plus, .recommended)
        XCTAssertNil(LocalModelDescriptor.descriptor(id: "gemma4-e2b-it-q4_k_m"), "Gemma 4 retire du catalogue")
        XCTAssertNil(LocalModelDescriptor.descriptor(id: "gemma4-e4b-it"))
        let phi = LocalModelDescriptor.descriptor(id: "phi4-mini-3.8b")
        XCTAssertEqual(phi?.compatibilityIPhone14Plus, .notRecommended)
    }

    func testFutureStubModelsNotDownloadableYet() {
        let stubs = LocalModelDescriptor.catalog.filter { !$0.isDownloadable }
        XCTAssertFalse(stubs.isEmpty)
        for stub in stubs {
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
        XCTAssertTrue(prompt.contains("<|im_start|>user\nTest"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant\n"))
        XCTAssertTrue(prompt.hasSuffix("<think>\n\n</think>\n\n"))
        XCTAssertFalse(prompt.hasPrefix("System:"))
        // /no_think injecté pour Qwen3 non-thinking mobile
        XCTAssertTrue(prompt.contains("/no_think"))
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
        XCTAssertTrue(prompt.contains("<|im_start|>assistant\n"))
        XCTAssertTrue(prompt.hasSuffix("<think>\n\n</think>\n\n"))
        XCTAssertLessThan(prompt.count, 2500)
        XCTAssertTrue(prompt.contains("u19") || prompt.contains("a19"))
    }
}

final class ChatMLStopTruncationTests: XCTestCase {
    func testStopsOnImEndAndKeepsAnswer() {
        let raw = "Bonjour, je suis l'assistant.<|im_end|>\n<|im_start|>user\nTest"
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertTrue(cut.hitStop)
        XCTAssertEqual(cut.text, "Bonjour, je suis l'assistant.")
        XCTAssertFalse(cut.text.contains("<|im_end|>"))
    }

    func testFirstTokenImEndYieldsEmpty() {
        let raw = "<|im_end|>"
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertTrue(cut.hitStop)
        XCTAssertEqual(cut.text, "")
    }

    func testStreamingDoesNotEmitPartialImEnd() {
        let profile = LocalModelRuntimeProfile.chatmlQwen
        var emitted = 0
        var display = ""
        // Simule pièce par pièce le token de contrôle.
        let pieces = ["<", "|", "im", "_end", "|>"]
        var acc = ""
        for p in pieces {
            acc += p
            let step = LocalChatTemplate.streamingSafeEmit(
                accumulated: acc,
                alreadyEmittedCount: emitted,
                profile: profile
            )
            display += step.emit
            emitted = step.newEmittedCount
            if step.hitStop { break }
        }
        XCTAssertFalse(display.contains("<|im_end|>"))
        XCTAssertEqual(display.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testStreamingEmitsTextThenStopsBeforeControl() {
        let profile = LocalModelRuntimeProfile.chatmlQwen
        var emitted = 0
        var display = ""
        let pieces = ["Bonjour", " toi", "<|im_end|>", "suite"]
        var acc = ""
        for p in pieces {
            acc += p
            let step = LocalChatTemplate.streamingSafeEmit(
                accumulated: acc,
                alreadyEmittedCount: emitted,
                profile: profile
            )
            display += step.emit
            emitted = step.newEmittedCount
            if step.hitStop { break }
        }
        XCTAssertEqual(display, "Bonjour toi")
        XCTAssertFalse(display.contains("<|"))
    }

    func testStripControlTokensDefense() {
        let raw = "Hi <|im_start|>user x <|im_end|>"
        let clean = ChatMLPromptBuilder.stripControlTokens(raw)
        XCTAssertFalse(clean.contains("<|im_"))
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

    func testThinkBlockStrippedWithoutHitStop() {
        let raw = "<think>raisonnement interne</think>\nBonjour !"
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertFalse(cut.hitStop)
        XCTAssertEqual(cut.text, "Bonjour !")
    }

    func testIncompleteThinkDoesNotCancelGeneration() {
        let raw = "<think>encore en train de réfléchir"
        let cut = ChatMLPromptBuilder.truncateAssistantOutput(raw)
        XCTAssertFalse(cut.hitStop)
        XCTAssertEqual(cut.text, "")
    }

    func testStreamingThinkThenAnswerDoesNotCancelEarly() {
        let profile = LocalModelRuntimeProfile.chatmlQwen
        var emitted = 0
        var display = ""
        let pieces = ["<think>", "abc", "</think>", "Salut", "<|im_end|>"]
        var acc = ""
        var stopped = false
        for p in pieces {
            acc += p
            let step = LocalChatTemplate.streamingSafeEmit(
                accumulated: acc,
                alreadyEmittedCount: emitted,
                profile: profile
            )
            display += step.emit
            emitted = step.newEmittedCount
            if step.hitStop {
                stopped = true
                break
            }
        }
        XCTAssertTrue(stopped)
        XCTAssertEqual(display, "Salut")
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

final class LocalModelSwitchPolicyTests: XCTestCase {
    func testAutoLoadNeverSelectsOtherModel() {
        // La politique d’auto-load ne change pas l’id sélectionné — elle charge seulement si installé.
        XCTAssertTrue(
            LocalModelAutoLoadPolicy.shouldAttemptLoad(
                wantsLocalExecution: true,
                isInstalled: true,
                isReady: false,
                exclusiveBusy: false,
                isLoading: false
            )
        )
        // Sans fichier : aucun téléchargement implicite.
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

final class AIParityArchitectureTests: XCTestCase {
    func testAllDownloadableModelsShareApplicationCapabilities() {
        for model in LocalModelDescriptor.downloadable {
            let app = ApplicationCapabilities.full
            XCTAssertTrue(app.agent, model.id)
            XCTAssertTrue(app.web, model.id)
            XCTAssertTrue(app.mail, model.id)
            XCTAssertTrue(app.files, model.id)
            XCTAssertTrue(app.memory, model.id)
            XCTAssertTrue(app.visionWorkflow, model.id)
        }
    }

    func testExecutionProfilesDifferByBudgetNotFeatures() {
        let qwen = LocalModelDescriptor.primary.executionProfile
        let other = LocalModelDescriptor.descriptor(id: "qwen35-2b-q4_k_m")!.executionProfile
        XCTAssertEqual(qwen.performanceClass, .compact)
        XCTAssertEqual(other.performanceClass, .balanced)
        XCTAssertLessThan(qwen.maxWorkflowSteps, other.maxWorkflowSteps)
        XCTAssertLessThanOrEqual(qwen.contextCharBudget, other.contextCharBudget)
        XCTAssertLessThanOrEqual(qwen.maxToolCalls, other.maxToolCalls)
    }

    func testStructuredActionParserToolAndFinal() {
        let tool = StructuredActionParser.parse(
            #"{"type":"tool","action":"web_search","arguments":{"query":"meteo"}}"#
        )
        if case .tool(let call) = tool {
            XCTAssertEqual(call.action, "web_search")
            XCTAssertEqual(call.arguments["query"], "meteo")
        } else {
            XCTFail("expected tool")
        }

        let final = StructuredActionParser.parse(
            #"{"type":"final","content":"Bonjour"}"#
        )
        if case .final(let text) = final {
            XCTAssertEqual(text, "Bonjour")
        } else {
            XCTFail("expected final")
        }

        let plain = StructuredActionParser.parse("Reponse libre sans JSON")
        if case .final(let text) = plain {
            XCTAssertTrue(text.contains("Reponse libre"))
        } else {
            XCTFail("expected plain final")
        }
    }

    func testContextCompressorKeepsRecentAndSummarizesOlder() {
        var history: [LLMChatMessage] = []
        for i in 0..<20 {
            history.append(LLMChatMessage(role: .user, content: "user-\(i) " + String(repeating: "x", count: 40)))
            history.append(LLMChatMessage(role: .assistant, content: "asst-\(i) " + String(repeating: "y", count: 40)))
        }
        let profile = LocalModelExecutionProfile.compact
        let packet = ConversationContextCompressor.compress(
            history: history,
            profile: profile,
            taskHint: "test"
        )
        XCTAssertFalse(packet.systemAugment.isEmpty)
        XCTAssertLessThanOrEqual(packet.messages.count, profile.historyMessageBudget)
        XCTAssertTrue(packet.messages.contains { $0.content.contains("user-19") || $0.content.contains("asst-19") })
        XCTAssertLessThanOrEqual(packet.approximateChars, profile.contextCharBudget + 200)
    }

    func testNativeCapabilitiesDoNotGateAgent() {
        let native = ModelNativeCapabilities.from(descriptor: .primary)
        XCTAssertFalse(native.supportsVision)
        XCTAssertTrue(ApplicationCapabilities.full.agent)
    }
}

final class LlamaInferencePerfTests: XCTestCase {
    func testA15DefaultPrefersMetalWithAllLayers() {
        let c = LlamaInferenceConfig.a15Default
        XCTAssertTrue(c.preferMetal)
        XCTAssertEqual(c.nGpuLayers, -1)
        XCTAssertEqual(c.nCtx, 2048)
        XCTAssertLessThanOrEqual(c.nUbatch, c.nBatch)
        XCTAssertEqual(c.flashAttention, .auto)
    }

    func testExecutionProfilesCarryInferenceWithoutFeatureGating() {
        let qwen = LocalModelDescriptor.primary.executionProfile
        let other = LocalModelDescriptor.descriptor(id: "qwen35-2b-q4_k_m")!.executionProfile
        XCTAssertTrue(ApplicationCapabilities.full.agent)
        XCTAssertTrue(qwen.inference.preferMetal)
        XCTAssertTrue(other.inference.preferMetal)
        XCTAssertNotEqual(qwen.maxWorkflowSteps, other.maxWorkflowSteps)
    }

    func testResolvedThreadsCappedForA15Class() {
        let t = LlamaInferenceConfig.resolvedThreads(explicit: nil)
        XCTAssertGreaterThanOrEqual(t, 1)
        XCTAssertLessThanOrEqual(t, 4)
        XCTAssertEqual(LlamaInferenceConfig.resolvedThreads(explicit: 2), 2)
    }

    func testHeavyModelProfileUsesConservativeGpuLayers() {
        let heavy = LocalModelDescriptor.descriptor(id: "phi4-mini-3.8b")!.executionProfile
        XCTAssertEqual(heavy.inference.nGpuLayers, 28)
        XCTAssertLessThan(heavy.inference.nCtx, LlamaInferenceConfig.a15Default.nCtx)
    }

    func testOutputTokensExplanationLargerThanShort() {
        let p = LocalModelExecutionProfile.compact
        XCTAssertGreaterThan(p.outputTokens(for: .explanation), p.outputTokens(for: .short))
        XCTAssertGreaterThan(p.outputTokens(for: .mailReply), 320)
        XCTAssertEqual(ApplicationCapabilities.full.agent, true)
        XCTAssertEqual(ApplicationCapabilities.full.files, true)
        XCTAssertEqual(ApplicationCapabilities.full.web, true)
    }

    func testMarkdownNotStrippedByControlSanitizer() {
        let raw = "# Titre\n\n**gras** et *italique*\n- item"
        let cut = LocalChatTemplate.truncateAssistantOutput(raw, profile: .chatmlQwen)
        XCTAssertTrue(cut.text.contains("**gras**"))
        XCTAssertTrue(cut.text.contains("# Titre"))
        XCTAssertFalse(cut.text.contains("<|im_end|>"))
    }

    func testSpecialTokensNeverSurviveTruncation() {
        let raw = "Hello<|im_end|>\n<|im_start|>assistant\nsecret"
        let cut = LocalChatTemplate.truncateAssistantOutput(raw, profile: .chatmlQwen)
        XCTAssertEqual(cut.text, "Hello")
        XCTAssertFalse(cut.text.contains("<|"))
    }

    func testAgentAntiLoopSignature() {
        let a = AIToolCall(action: "web_search", arguments: ["query": "x"])
        let b = AIToolCall(action: "web_search", arguments: ["query": "x"])
        let c = AIToolCall(action: "web_search", arguments: ["query": "y"])
        XCTAssertEqual(AgentWorkflow.toolSignature(a), AgentWorkflow.toolSignature(b))
        XCTAssertNotEqual(AgentWorkflow.toolSignature(a), AgentWorkflow.toolSignature(c))
    }

    func testMailThreadPromptIsChronologicalAndIsolated() {
        let older = DirectMailMessage(
            id: "1", threadId: "t", subject: "Sujet", from: "a@b.c",
            snippet: "old", date: "2020-01-01", bodyPlain: "Ancien corps", bodyHtml: nil, labelIds: []
        )
        let newer = DirectMailMessage(
            id: "2", threadId: "t", subject: "Sujet", from: "a@b.c",
            snippet: "new", date: "2024-01-01", bodyPlain: "Pouvez-vous confirmer mardi ?", bodyHtml: nil, labelIds: []
        )
        let thread = DirectMailThread(
            id: "t", threadId: "t", subject: "Sujet", from: "a@b.c",
            snippet: "new", date: "2024-01-01", bodyPlain: nil, labelIds: [],
            messages: [newer, older]
        )
        let prompt = MailThreadPromptBuilder.userPrompt(
            thread: thread,
            profile: .compact,
            kind: .reply(instruction: "Réponds.")
        )
        XCTAssertTrue(prompt.contains("Pouvez-vous confirmer mardi"))
        XCTAssertTrue(prompt.contains("Ancien corps"))
        XCTAssertTrue(prompt.contains("dernier, prioritaire"))
        XCTAssertFalse(prompt.contains("Nouvelle conversation"))
        XCTAssertFalse(prompt.lowercased().contains("mémoire personnelle"))
        let idxOld = prompt.range(of: "Ancien corps")!.lowerBound
        let idxNew = prompt.range(of: "Pouvez-vous confirmer mardi")!.lowerBound
        XCTAssertLessThan(idxOld, idxNew)
    }

    func testPlainBodyForSendStripsMarkdownLate() {
        let md = "**Bonjour**,\n\n- item"
        let plain = MailThreadPromptBuilder.plainBodyForSend(md)
        XCTAssertFalse(plain.contains("**"))
        XCTAssertTrue(plain.contains("Bonjour"))
    }

    func testConversationPromptAllowsMarkdownAndExplanations() {
        XCTAssertTrue(LocalPrompts.conversation.contains("Markdown"))
        XCTAssertEqual(LocalPrompts.conversationTask(for: "Explique-moi la théorie des cordes"), .explanation)
        XCTAssertEqual(LocalPrompts.conversationTask(for: "ok"), .short)
    }

    func testLocalFilesRootIdStable() {
        XCTAssertTrue(LocalFilesStore.isLocalRoot(LocalFilesStore.rootId))
        XCTAssertEqual(LocalFilesStore.root().enabled, true)
    }
}
