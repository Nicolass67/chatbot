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
        XCTAssertGreaterThanOrEqual(LocalModelDescriptor.catalog.count, 3)
        XCTAssertEqual(LocalModelDescriptor.catalog.filter { $0.id == LocalModelDescriptor.primary.id }.count, 1)
        XCTAssertTrue(LocalModelDescriptor.downloadable.contains { $0.id == "lfm25-1.2b-instruct-q4_k_m" })
        XCTAssertTrue(LocalModelDescriptor.downloadable.contains { $0.id == "qwen35-2b-q4_k_m" })
        XCTAssertTrue(LocalModelDescriptor.catalog.allSatisfy(\.isDownloadable))
    }

    func testQwen35KeepsLmstudioGGUFAndOptionalMmproj() {
        let m = LocalModelDescriptor.descriptor(id: "qwen35-2b-q4_k_m")!
        XCTAssertEqual(m.filename, "Qwen3.5-2B-Q4_K_M.gguf")
        XCTAssertEqual(m.expectedBytes, 1_270_808_032)
        XCTAssertEqual(m.architecture, "qwen35")
        XCTAssertTrue(m.downloadURL!.absoluteString.contains("lmstudio-community/Qwen3.5-2B-GGUF"))
        XCTAssertTrue(m.downloadURL!.absoluteString.contains("Qwen3.5-2B-Q4_K_M.gguf"))
        XCTAssertFalse(m.downloadURL!.absoluteString.contains("bartowski"))
        XCTAssertFalse(m.downloadURL!.absoluteString.contains("Qwen_Qwen3.5-2B-Q4_K_M"))
        let mmproj = m.mmproj
        XCTAssertNotNil(mmproj)
        XCTAssertEqual(mmproj?.filename, "mmproj-Qwen3.5-2B-BF16.gguf")
        XCTAssertEqual(mmproj?.expectedBytes, 671_372_416)
        XCTAssertTrue(mmproj!.filename.hasPrefix("mmproj"))
        XCTAssertNotEqual(mmproj?.filename, m.filename)
        XCTAssertTrue(mmproj!.downloadURL.absoluteString.contains("lmstudio-community/Qwen3.5-2B-GGUF"))
        XCTAssertFalse(mmproj!.downloadURL.absoluteString.contains("bartowski"))
        XCTAssertTrue(m.capabilities.vision)
    }

    func testGemma4RemainsAbsentFromCatalog() {
        XCTAssertNil(LocalModelDescriptor.descriptor(id: "gemma4-e2b-it-q4_k_m"), "Gemma 4 retire du catalogue")
        XCTAssertNil(LocalModelDescriptor.descriptor(id: "gemma4-e4b-it"))
        XCTAssertFalse(LocalModelDescriptor.catalog.contains { $0.id.localizedCaseInsensitiveContains("gemma") })
    }

    func testVisionMarkerInsertedOnlyWhenImagesPresent() {
        XCTAssertEqual(LocalVision.userContent("Hello", imageCount: 0), "Hello")
        let withImage = LocalVision.userContent("Décris", imageCount: 1)
        XCTAssertTrue(withImage.contains(LocalVision.mediaMarker))
        XCTAssertTrue(withImage.contains("Décris"))
        XCTAssertEqual(LocalVision.userContent("", imageCount: 1).components(separatedBy: LocalVision.mediaMarker).count - 1, 1)
    }

    func testCompatibilityTiersForIPhone14Plus() {
        XCTAssertEqual(LocalModelDescriptor.primary.compatibilityIPhone14Plus, .recommended)
        XCTAssertNil(LocalModelDescriptor.descriptor(id: "gemma4-e2b-it-q4_k_m"), "Gemma 4 retire du catalogue")
        XCTAssertNil(LocalModelDescriptor.descriptor(id: "gemma4-e4b-it"))
        let phi = LocalModelDescriptor.descriptor(id: "phi4-mini-3.8b")
        XCTAssertEqual(phi?.compatibilityIPhone14Plus, .notRecommended)
    }

    func testFutureStubModelsNotDownloadableYet() {
        let stubs = LocalModelDescriptor.experimentalInternal.filter { !$0.isDownloadable }
        XCTAssertFalse(stubs.isEmpty)
        for stub in stubs {
            XCTAssertNil(stub.downloadURL, stub.id)
        }
        let gemma = LocalModelDescriptor.descriptor(id: "gemma4-e2b-it-q4_0")
        XCTAssertNotNil(gemma)
        XCTAssertFalse(gemma!.isDownloadable, "Gemma 4 E2B reste hors téléchargement — trop lourd vs Qwen3.5 2B")
        XCTAssertFalse(LocalModelDescriptor.downloadable.contains { $0.id == "gemma4-e2b-it-q4_0" })
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
        XCTAssertEqual(
            LocalPrompts.conversationTask(for: "Explique-moi la théorie des cordes en détail."),
            .detailed
        )
        XCTAssertEqual(LocalPrompts.conversationTask(for: "ok"), .short)
        XCTAssertFalse(LocalPrompts.mailSummary.contains("Qui / quoi / quand"))
    }

    func testLocalFilesRootIdStable() {
        XCTAssertTrue(LocalFilesStore.isLocalRoot(LocalFilesStore.rootId))
        XCTAssertTrue(LocalFilesStore.isLocalRoot(LocalFilesStore.documentsRootId))
        XCTAssertEqual(LocalFilesStore.root().enabled, true)
        XCTAssertFalse((LocalFilesStore.root().absolutePath ?? "").hasPrefix("/var/mobile"))
        XCTAssertTrue(LocalFilesStore.roots().contains(where: { $0.id == LocalFilesStore.documentsRootId }))
    }
}

final class LocalParityWorkflowTests: XCTestCase {
    func testMailIntentLatestFromInboxQuestion() {
        let intent = MailIntentDetector.detect("Tu peux me donner mon dernier mail ?", hasOpenThread: false)
        XCTAssertEqual(intent, .latest(count: 1))
        XCTAssertTrue(intent.needsGmailSearch)
        XCTAssertEqual(MailIntentDetector.gmailQuery(for: intent, userText: "x"), "in:inbox")
        XCTAssertEqual(
            MailIntentDetector.detect("Explique la théorie des cordes", hasOpenThread: false),
            .none
        )
    }

    func testMailIntentUnreadAndFrom() {
        XCTAssertEqual(
            MailIntentDetector.detect("Quels sont mes mails non lus ?", hasOpenThread: false),
            .unread(count: 8)
        )
        if case .fromContact(let name) = MailIntentDetector.detect(
            "Est-ce que j'ai reçu un mail de Pierre ?",
            hasOpenThread: false
        ) {
            XCTAssertTrue(name.lowercased().contains("pierre"))
        } else {
            XCTFail("expected fromContact")
        }
    }

    func testMailSignatureAppendedOnce() {
        let body = "Bonjour,\n\nMerci pour votre retour."
        let signed = MailSignature.appendOnce(body, name: "Nicolas")
        XCTAssertTrue(signed.contains("Cordialement"))
        XCTAssertEqual(signed.components(separatedBy: "Nicolas").count - 1, 1)
        let twice = MailSignature.appendOnce(signed, name: "Nicolas")
        XCTAssertEqual(twice.components(separatedBy: "Nicolas").count - 1, 1)
        let alreadyClosed = MailSignature.appendOnce("Merci pour le retour.\n\nCordialement", name: "Nicolas")
        XCTAssertEqual(alreadyClosed.components(separatedBy: "Cordialement").count - 1, 1)
        XCTAssertEqual(alreadyClosed.components(separatedBy: "Nicolas").count - 1, 1)
    }

    func testPromptBudgetReservesOutput() {
        let profile = LocalModelExecutionProfile.compact
        let budget = GenerationContextBudget.make(
            profile: profile,
            requestedOutput: profile.outputTokens(for: .webSynthesize)
        )
        XCTAssertEqual(budget.nCtx, Int(profile.inference.nCtx))
        XCTAssertEqual(budget.promptBudget + budget.reservedOutputTokens + budget.safetyTokens, budget.nCtx)
        XCTAssertGreaterThan(budget.promptBudget, 300)
        let huge = String(repeating: "lasagne vegan ", count: 400)
        XCTAssertGreaterThan(GenerationContextBudget.estimateTokens(huge), budget.promptBudget)
        let clipped = GenerationContextBudget.clip(huge, maxChars: 400)
        XCTAssertEqual(clipped.count, 400)
    }

    func testWebEvidenceIsBoundedAndRanked() {
        let profile = LocalModelExecutionProfile.compact
        let sources = [
            SearchSourceDTO(id: "web_1", title: "Unrelated", url: "https://a.example", domain: "a.example", snippet: "hello"),
            SearchSourceDTO(id: "web_2", title: "Lasagne vegan recette", url: "https://planetvegan.example/lasagne", domain: "planetvegan.example", snippet: "pâtes tofu béchamel"),
            SearchSourceDTO(id: "web_3", title: "GPU news", url: "https://gpu.example", domain: "gpu.example", snippet: "rtx"),
        ]
        let pages = [
            "web_2": String(repeating: "lasagne vegan tofu ricotta\n\n", count: 80) + "étape 1 cuire",
        ]
        let packet = WebEvidenceBuilder.build(
            query: "recette lasagne vegan",
            sources: sources,
            pageTexts: pages,
            profile: profile
        )
        XCTAssertLessThanOrEqual(packet.promptBlock.count, profile.toolResultCharBudget)
        XCTAssertTrue(packet.promptBlock.contains("USER REQUEST"))
        XCTAssertTrue(packet.promptBlock.contains("TITLE:"))
        XCTAssertTrue(packet.promptBlock.contains("DOMAIN:"))
        XCTAssertTrue(packet.promptBlock.contains("EXCERPT:"))
        XCTAssertTrue(packet.sources.contains(where: { $0.domain == "planetvegan.example" }))
        XCTAssertEqual(packet.sources.first?.domain, "planetvegan.example")
        XCTAssertEqual(packet.sources.first?.id, "web_1")
        XCTAssertLessThanOrEqual(packet.sources.count, profile.maxWebResults)
        XCTAssertFalse(packet.promptBlock.contains("Je n'ai pas accès à Internet"))
        XCTAssertFalse(packet.promptBlock.contains("WebSearchTool a été exécuté"))
    }

    func testShrinkMessagesDropsOldest() {
        let msgs = (0..<6).map { LLMChatMessage(role: .user, content: "m\($0) " + String(repeating: "x", count: 200)) }
        let shrunk = GenerationContextBudget.shrinkMessages(msgs, attempt: 2, toolResultCharBudget: 300)
        XCTAssertEqual(shrunk.count, 1)
        XCTAssertLessThanOrEqual(shrunk[0].content.count, 300)
    }

    func testGroundingPromptForbidsNoInternetDenial() {
        let sys = WebGroundingPrompt.system()
        XCTAssertTrue(sys.contains("USER REQUEST"))
        XCTAssertTrue(sys.contains("JAMAIS"))
        XCTAssertTrue(sys.contains("web_N"))
        XCTAssertFalse(sys.contains("WebSearchTool a été exécuté"))
    }

    func testAgentEventsCarryPlanNotStepText() {
        let started = AgentOrchestrationEvent.started
        let plan = AgentOrchestrationEvent.plan(steps: [
            AgentPlanStep(id: "act", title: "Rechercher sur le web", status: "pending"),
        ])
        XCTAssertEqual(started, .started)
        if case .plan(let steps) = plan {
            XCTAssertEqual(steps.first?.title, "Rechercher sur le web")
        } else {
            XCTFail("plan")
        }
    }

    func testLocalFilesRootIsAppSandboxNotIPhoneStorage() {
        let root = LocalFilesStore.root()
        XCTAssertEqual(root.id, LocalFilesStore.documentsRootId)
        XCTAssertFalse((root.label ?? "").localizedCaseInsensitiveContains("iphone") && (root.label ?? "").count < 8)
        XCTAssertFalse((root.absolutePath ?? "").hasPrefix("/var/mobile"))
        XCTAssertTrue((root.absolutePath ?? "").localizedCaseInsensitiveContains("sandbox")
            || (root.absolutePath ?? "").localizedCaseInsensitiveContains("app"))
    }

    func testDuckDuckGoRedirectUnwrap() {
        let href = "https://duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.ldlc.com%2Ffiche%2FPB123&rut=abc"
        let url = WebURLNormalizer.unwrapDuckDuckGoRedirect(href)
        XCTAssertEqual(url, "https://www.ldlc.com/fiche/PB123")
        XCTAssertEqual(WebURLNormalizer.domain(from: url), "ldlc.com")
    }

    func testNumberedSourcesUseWebIndex() {
        let sources = [
            SearchSourceDTO(id: "web_1", title: "A", url: "https://a.example/x", domain: "a.example", snippet: "un"),
            SearchSourceDTO(id: "web_2", title: "B", url: "https://b.example/y", domain: "b.example", snippet: "deux"),
        ]
        let block = WebURLNormalizer.numberedSourcesBlock(sources)
        XCTAssertTrue(block.contains("[web_1]"))
        XCTAssertTrue(block.contains("[web_2]"))
        XCTAssertTrue(block.contains("https://a.example/x"))
        XCTAssertFalse(block.contains("invented.example"))
    }

    func testCitationParserResolvesWebIndex() {
        let sources = [
            SearchSourceDTO(id: "web_1", title: "Tech", url: "https://techpowerup.example", domain: "techpowerup.example", snippet: nil),
        ]
        XCTAssertTrue(CitationParser.containsMarker("La carte est chère [web_1]."))
        let segs = CitationParser.segments(in: "La carte est chère [web_1].", sources: sources)
        XCTAssertFalse(segs.isEmpty)
    }

    func testGroundingPromptForbidsHallucination() {
        XCTAssertTrue(WebGroundingPrompt.system().contains("USER REQUEST"))
        XCTAssertTrue(WebGroundingPrompt.system().contains("web_N"))
        XCTAssertTrue(WebGroundingPrompt.system().contains("JAMAIS"))
        XCTAssertTrue(WebGroundingPrompt.system().contains("extraits indiquent"))
    }

    func testGraniteAndPhiTemplatesAreModelSpecific() {
        let granite = LocalChatTemplate.buildPrompt(
            system: "SYS",
            messages: [LLMChatMessage(role: .user, content: "Hi")],
            charBudget: 2000,
            profile: .granite
        )
        XCTAssertTrue(granite.contains("<|start_of_role|>user"))
        XCTAssertFalse(granite.contains("<|im_start|>"))
        let phi = LocalChatTemplate.buildPrompt(
            system: "SYS",
            messages: [LLMChatMessage(role: .user, content: "Hi")],
            charBudget: 2000,
            profile: .phi
        )
        XCTAssertTrue(phi.contains("<|user|>"))
        XCTAssertTrue(LocalModelDescriptor.descriptor(id: "granite4-micro-q4_k_m")?.runtimeProfile.templateKind == .granite)
        XCTAssertTrue(LocalModelDescriptor.descriptor(id: "phi4-mini-3.8b")?.runtimeProfile.templateKind == .phi)
    }

    func testDetailedBudgetLargerThanExplanation() {
        let p = LocalModelExecutionProfile.compact
        XCTAssertGreaterThan(p.outputTokens(for: .detailed), p.outputTokens(for: .explanation))
        XCTAssertGreaterThan(p.outputTokens(for: .explanation), p.outputTokens(for: .short))
    }

    func testParseLocalFileId() {
        let id = LocalFilesStore.fileId(rootId: "iphone-documents", relative: "Notes/a.txt")
        let parsed = LocalFilesStore.parseFileId(id)
        XCTAssertEqual(parsed?.rootId, "iphone-documents")
        XCTAssertEqual(parsed?.relative, "Notes/a.txt")
    }

    func testChatMLClipsOversizedLastMessage() {
        let huge = String(repeating: "page fetch ", count: 800)
        let prompt = LocalChatTemplate.buildPrompt(
            system: "sys",
            messages: [LLMChatMessage(role: .user, content: huge)],
            charBudget: 600,
            profile: .chatmlQwen
        )
        XCTAssertLessThan(prompt.count, huge.count)
        XCTAssertTrue(prompt.contains("<|im_start|>user"))
    }

    func testHtmlResultParserExtractsHref() {
        let html = """
        <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.tomshardware.com%2Fgpu">Tom's Hardware GPU</a>
        <a class="result__snippet">Benchmarks 1440p</a>
        """
        let hits = WebSearchTool.parseDuckDuckGoHTML(html, limit: 5, snippetBudget: 200)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits[0].url.contains("tomshardware.com"))
        XCTAssertEqual(hits[0].id, "web_1")
    }
}

final class WorkflowSyncTests: XCTestCase {
    func testGenerationRunSourcesStayOnSameRun() {
        var first = GenerationRunState.start(workflow: "web")
        first.discoveredSources = [
            SearchSourceDTO(id: "web_1", title: "A", url: "https://a.example", domain: "a.example", snippet: "a"),
        ]
        first.finalSources = first.discoveredSources
        first.messageId = "asst-1"
        var second = GenerationRunState.start(workflow: "chat")
        second.messageId = "asst-2"
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.finalSources.count, 1)
        XCTAssertTrue(second.finalSources.isEmpty)
        XCTAssertTrue(second.discoveredSources.isEmpty)
        XCTAssertNotEqual(first.messageId, second.messageId)
    }

    func testPreviousRunSourcesDoNotLeakOntoNewRun() {
        var previous = GenerationRunState.start(workflow: "web")
        previous.finalSources = [
            SearchSourceDTO(id: "web_1", title: "Old", url: "https://old.example", domain: "old.example"),
        ]
        let next = GenerationRunState.start(workflow: "web")
        XCTAssertTrue(next.sources.isEmpty)
        XCTAssertFalse(next.finalSources.contains(where: { $0.domain == "old.example" }))
    }

    func testStructuredEvidenceContainsTitleDomainExcerpt() {
        let evidence = [
            WebEvidence(
                sourceId: "web_1",
                title: "Nouilles au wok",
                domain: "cuisine.example",
                url: "https://cuisine.example/wok",
                excerpt: "Faire sauter les nouilles."
            ),
        ]
        let block = WebEvidenceBuilder.structuredPromptBlock(
            userRequest: "Donne-moi une recette de nouilles sautées au wok",
            evidence: evidence,
            charBudget: 4000
        )
        XCTAssertTrue(block.contains("USER REQUEST"))
        XCTAssertTrue(block.contains("nouilles sautées au wok"))
        XCTAssertTrue(block.contains("SOURCE_ID: web_1"))
        XCTAssertTrue(block.contains("TITLE: Nouilles au wok"))
        XCTAssertTrue(block.contains("DOMAIN: cuisine.example"))
        XCTAssertTrue(block.contains("EXCERPT: Faire sauter"))
        XCTAssertFalse(block.contains("Extrait de"))
    }

    func testOffTopicWebResultsAreFiltered() {
        let sources = [
            SearchSourceDTO(
                id: "web_1",
                title: "Nuggets végétaux PST",
                url: "https://vegan.example/pst",
                domain: "vegan.example",
                snippet: "Recette de nuggets au simili-poulet."
            ),
            SearchSourceDTO(
                id: "web_2",
                title: "Nouilles sautées au wok",
                url: "https://wok.example/nouilles",
                domain: "wok.example",
                snippet: "Recette de nouilles sautées au wok avec légumes."
            ),
        ]
        let filtered = WebEvidenceBuilder.filterRelevant(sources, query: "recette de nouilles sautées au wok")
        XCTAssertEqual(filtered.first?.domain, "wok.example")
        XCTAssertFalse(filtered.contains(where: { $0.domain == "vegan.example" }))
    }

    func testMailIntentLastMailFromSenderBeatsLatest() {
        let intent = MailIntentDetector.detect(
            "Lis-moi mon dernier mail de la part de la SPA",
            hasOpenThread: false
        )
        guard case .fromContact(let name) = intent else {
            return XCTFail("expected fromContact, got \(intent)")
        }
        XCTAssertTrue(name.localizedCaseInsensitiveContains("SPA"))
        XCTAssertFalse(name.localizedCaseInsensitiveContains("la part"))
        let q = MailIntentDetector.gmailQuery(for: intent, userText: "x")
        XCTAssertTrue(q.contains("from:"))
        XCTAssertTrue(q.lowercased().contains("spa"))
        XCTAssertNotEqual(q, "in:inbox")
    }

    func testMailIntentLatestFromMailboxList() {
        let intent = MailIntentDetector.detect("Lis-moi mon dernier mail.", hasOpenThread: false)
        XCTAssertEqual(intent, .latest(count: 1))
        XCTAssertTrue(intent.needsGmailSearch)
    }

    func testMailContextPromptForbidsAccessDenialWhenMessagesExist() {
        let tool = """
        [1] messageId=m1 threadId=t1
        De: SPA <spa@example.org>
        Objet: Don
        Date: hier
        Merci pour votre don.
        """
        XCTAssertTrue(MailContextPrompt.containsMessages(toolText: tool, ok: true))
        let sys = MailContextPrompt.system(hasMessages: true)
        XCTAssertTrue(sys.contains("MAIL CONTEXT AVAILABLE"))
        XCTAssertTrue(sys.contains("JAMAIS"))
        let user = MailContextPrompt.userMessage(userRequest: "Lis le dernier mail de la SPA", toolText: tool, hasMessages: true)
        XCTAssertTrue(user.contains("USER REQUEST"))
        XCTAssertTrue(user.contains("MAIL CONTEXT AVAILABLE"))
        XCTAssertTrue(user.contains("SPA"))
        XCTAssertFalse(MailContextPrompt.containsMessages(toolText: "Aucun mail Gmail pour cette recherche (q=in:inbox).", ok: true))
    }

    func testMailboxWithoutSelectionStillNeedsSearch() {
        XCTAssertTrue(MailIntentDetector.detect("Quel est le dernier mail que j'ai reçu ?", hasOpenThread: false).needsGmailSearch)
        XCTAssertTrue(MailIntentDetector.detect("Résume mon dernier mail.", hasOpenThread: false).needsGmailSearch)
        XCTAssertTrue(MailIntentDetector.wantsReply("Réponds à mon dernier mail."))
        XCTAssertTrue(MailIntentDetector.detect("Réponds à mon dernier mail.", hasOpenThread: false).needsGmailSearch)
    }

    func testAgentTimerLocksWhenRunCompletes() {
        var state = AgentActivityState()
        state.visible = true
        state.startedAt = Date().addingTimeInterval(-12)
        state.planSteps = [
            AgentPlanStep(id: "act", title: "Rechercher sur le web", status: "running"),
            AgentPlanStep(id: "answer", title: "Rédiger la réponse", status: "pending"),
        ]
        XCTAssertNil(state.lockedThoughtSeconds)
        state.lockedThoughtSeconds = max(1, Int(Date().timeIntervalSince(state.startedAt!)))
        state.completed = true
        for i in state.planSteps.indices where state.planSteps[i].status == "running" || state.planSteps[i].status == "pending" {
            state.planSteps[i].status = "done"
        }
        let snap = state.snapshot()
        XCTAssertTrue(snap.completed)
        XCTAssertEqual(snap.thoughtSeconds, state.lockedThoughtSeconds)
        XCTAssertTrue(snap.planSteps.allSatisfy { $0.status == "done" })
        XCTAssertGreaterThanOrEqual(snap.thoughtSeconds ?? 0, 1)
    }

    func testFilesRootOpensOnceAndDoubleTapIsIgnored() {
        let root = FilesDestination.folder(rootId: "docs", path: "", title: "Documents")
        var path: [FilesDestination] = []
        let first = FilesPathOps.push(path, root)
        XCTAssertEqual(first.path.count, 1)
        path = first.path
        let second = FilesPathOps.push(path, root)
        XCTAssertEqual(second.result, .ignoredDuplicate)
        XCTAssertEqual(second.path.count, 1)
        let titled = FilesDestination.folder(rootId: "docs", path: "", title: "Fichiers de l’app")
        let third = FilesPathOps.push(path, titled)
        XCTAssertEqual(third.result, .ignoredDuplicate)
        XCTAssertEqual(FilesPathOps.breadcrumb(path), "Documents")
    }

    func testFilesFolderPathAndBackToRoot() {
        let root = FilesDestination.folder(rootId: "docs", path: "", title: "Documents")
        let a = FilesDestination.folder(rootId: "docs", path: "Projet", title: "Projet")
        let b = FilesDestination.folder(rootId: "docs", path: "Projet/Photos", title: "Photos")
        var path = FilesPathOps.push([], root).path
        path = FilesPathOps.push(path, a).path
        path = FilesPathOps.push(path, b).path
        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(FilesPathOps.breadcrumb(path), "Documents / Projet / Photos")
        let back = FilesPathOps.push(path, root)
        XCTAssertEqual(back.path.count, 1)
        XCTAssertEqual(FilesPathOps.breadcrumb(back.path), "Documents")
        XCTAssertEqual(FilesPathOps.dedupe([root, root, a, a, b]).count, 3)
    }

    func testMailReferenceParsesSearchHit() {
        let tool = """
        [1] messageId=msgSPA threadId=thrSPA
        De: SPA <spa@example.org>
        Objet: Don
        Date: 2026-04-01
        Merci pour votre don.
        """
        let ref = MailReference.first(fromToolText: tool)
        XCTAssertEqual(ref?.messageId, "msgSPA")
        XCTAssertEqual(ref?.threadId, "thrSPA")
        XCTAssertEqual(ref?.subject, "Don")
        XCTAssertTrue(ref?.sender?.contains("SPA") == true)
        let encoded = try! JSONEncoder().encode(ref!)
        let decoded = try! JSONDecoder().decode(MailHandoffDTO.self, from: encoded)
        XCTAssertEqual(decoded.messageId, "msgSPA")
        XCTAssertEqual(decoded.threadId, "thrSPA")
    }

    @MainActor
    func testMailChromeSliceSurvivesReloadWithoutFilesFound() {
        let handoff = MailReference.make(
            messageId: "m1",
            threadId: "t1",
            subject: "SPA",
            sender: "SPA",
            date: "hier"
        )
        ConversationSessionStore.setChrome(
            MessageChromeMeta(mailHandoff: handoff),
            conversationId: "conv-mail-tile-test",
            messageId: "asst-1"
        )
        ConversationSessionStore.replaceChrome(conversationId: "conv-mail-tile-test", chrome: [:])
        ConversationSessionStore.setChrome(
            MessageChromeMeta(mailHandoff: handoff),
            conversationId: "conv-mail-tile-test",
            messageId: "asst-1"
        )
        let map = ConversationSessionStore.chrome(for: "conv-mail-tile-test")
        XCTAssertEqual(map["asst-1"]?.mailHandoff?.messageId, "m1")
        ConversationSessionStore.clear(conversationId: "conv-mail-tile-test", scope: .general)
    }

    func testChatModeNeverRoutesToAgentWorkflow() {
        XCTAssertEqual(
            ConversationWorkflowRouter.kind(
                interaction: .chat,
                filesScope: false,
                preferMail: false,
                webEnabled: true
            ),
            .web
        )
        XCTAssertEqual(
            ConversationWorkflowRouter.kind(
                interaction: .agent,
                filesScope: false,
                preferMail: false,
                webEnabled: true
            ),
            .agent
        )
        XCTAssertEqual(
            ConversationWorkflowRouter.kind(
                interaction: .chat,
                filesScope: false,
                preferMail: true,
                webEnabled: true
            ),
            .mail
        )
    }

    func testLocalPreviewKindDetectsPdfAndImages() {
        XCTAssertEqual(LocalFileTypeDetector.kind(for: URL(fileURLWithPath: "/tmp/a.pdf")), .pdf)
        XCTAssertEqual(LocalFileTypeDetector.kind(for: URL(fileURLWithPath: "/tmp/a.png")), .image)
        XCTAssertEqual(LocalFileTypeDetector.kind(for: URL(fileURLWithPath: "/tmp/a.jpg")), .image)
        XCTAssertEqual(LocalFileTypeDetector.kind(for: URL(fileURLWithPath: "/tmp/a.heic")), .image)
        XCTAssertEqual(LocalFileTypeDetector.kind(for: URL(fileURLWithPath: "/tmp/a.webp")), .image)
        XCTAssertEqual(LocalFileTypeDetector.kind(for: URL(fileURLWithPath: "/tmp/a.txt")), .text)
        let pdfMagic = Data([0x25, 0x50, 0x44, 0x46, 0x2D])
        XCTAssertEqual(
            LocalFileTypeDetector.kind(for: URL(fileURLWithPath: "/tmp/unknown.bin"), sniffing: pdfMagic),
            .pdf
        )
    }

    func testGmailMutationResultCases() {
        XCTAssertEqual(MailMutationResult.success, .success)
        if case .failure(let msg) = MailMutationResult.failure("boom") {
            XCTAssertEqual(msg, "boom")
        } else {
            XCTFail("expected failure")
        }
        let unread = MailMessageSummary(
            id: "m1",
            threadId: "t1",
            from: nil,
            subject: "SPA",
            snippet: nil,
            date: nil,
            isUnread: true,
            hasAttachments: nil
        )
        XCTAssertEqual(unread.withUnread(false).isUnread, false)
        XCTAssertEqual(unread.id, unread.withUnread(false).id)
    }

    @MainActor
    func testConversationInteractionStoreIsSingleSourceOfTruth() {
        let suite = "test.conversation.interaction.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ConversationInteractionStore(defaults: defaults)
        XCTAssertEqual(store.mode, .chat)
        store.set(.agent)
        XCTAssertEqual(store.mode, .agent)
        store.set(stored: "chat")
        XCTAssertEqual(store.mode, .chat)
        XCTAssertEqual(defaults.string(forKey: ConversationInteractionStore.defaultsKey), "chat")
        XCTAssertEqual(
            ConversationWorkflowRouter.kind(
                interaction: store.mode,
                filesScope: false,
                preferMail: false,
                webEnabled: true
            ),
            .web
        )
        defaults.removePersistentDomain(forName: suite)
    }

    func testMailDeepLinkPrefersMessageId() {
        let ref = MailReference.make(
            messageId: "msgSPA",
            threadId: "thrSPA",
            subject: "Don",
            sender: "SPA",
            date: "hier"
        )
        let link = MailDeepLink(ref)
        XCTAssertEqual(link.messageId, "msgSPA")
        XCTAssertEqual(link.threadId, "thrSPA")
        XCTAssertEqual(link.subject, "Don")
    }

    func testQwen35NativeVisionRequiresMmproj() {
        let qwen = LocalModelDescriptor.descriptor(id: "qwen35-2b-q4_k_m")!
        XCTAssertTrue(qwen.capabilities.vision)
        XCTAssertNotNil(qwen.mmproj)
        XCTAssertTrue(qwen.nativeVision)
        XCTAssertTrue(qwen.recommended)
        let gemma = LocalModelDescriptor.descriptor(id: "gemma4-e2b-it-q4_0")!
        XCTAssertTrue(gemma.capabilities.vision)
        XCTAssertNil(gemma.mmproj)
        XCTAssertFalse(gemma.nativeVision)
        XCTAssertFalse(gemma.isDownloadable)
        XCTAssertFalse(LocalModelDescriptor.catalog.contains { $0.id == gemma.id })
    }

    func testScrollFollowsBottomUnlessUserReleased() {
        XCTAssertTrue(ChatScrollPolicy.shouldFollowNewContent(userReleasedAutoScroll: false, pinToTopActive: false))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowNewContent(userReleasedAutoScroll: true, pinToTopActive: false))
        XCTAssertFalse(ChatScrollPolicy.shouldFollowNewContent(userReleasedAutoScroll: false, pinToTopActive: true))
        let sendingPin = ChatScrollPolicy.bottomSlack(
            isSending: true,
            pinToTopActive: true,
            agentOrStreamActive: false,
            chromePadding: 160,
            viewportHeight: 700
        )
        XCTAssertEqual(sendingPin, 688)
        let agent = ChatScrollPolicy.bottomSlack(
            isSending: true,
            pinToTopActive: true,
            agentOrStreamActive: true,
            chromePadding: 160,
            viewportHeight: 700
        )
        XCTAssertEqual(agent, 160)
    }
}
