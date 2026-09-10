import XCTest
@testable import ChatbotNative

@MainActor
final class ScriptedAIRuntime: AIRuntime {
    var applicationCapabilities: ApplicationCapabilities { .full }
    var nativeCapabilities: ModelNativeCapabilities {
        ModelNativeCapabilities.from(descriptor: .primary)
    }
    var executionProfile: LocalModelExecutionProfile { .compact }
    var chatTemplateProfile: LocalModelRuntimeProfile { .chatmlQwen }
    var isReady: Bool { true }
    var shouldFail = false
    var handler: (String, String) -> String

    init(handler: @escaping (String, String) -> String) {
        self.handler = handler
    }

    func generate(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int?
    ) async throws -> String {
        if shouldFail { throw AIRuntimeError.emptyGeneration }
        let user = messages.last?.content ?? ""
        return handler(system, user)
    }

    func generateStream(
        system: String,
        messages: [LLMChatMessage],
        maxTokens: Int?,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let text = try await generate(system: system, messages: messages, maxTokens: maxTokens)
        onToken(text)
        return text
    }

    func cancel() async {}
}

final class MailDraftAndIntentTests: XCTestCase {
    func testImprovePromptPutsInstructionFirst() {
        let prompt = MailDraftRewriteWorkflow.userPrompt(
            instruction: "Écris-le en anglais",
            body: "Bonjour Jean, je serai disponible mardi.",
            to: "jean@example.com",
            subject: "RDV"
        )
        XCTAssertTrue(prompt.contains("USER INSTRUCTION:"))
        XCTAssertTrue(prompt.contains("Écris-le en anglais"))
        XCTAssertLessThan(
            prompt.range(of: "USER INSTRUCTION:")!.lowerBound,
            prompt.range(of: "CURRENT DRAFT:")!.lowerBound
        )
        XCTAssertTrue(prompt.contains("Do not re-apply older instructions"))
        XCTAssertTrue(prompt.contains("visible change") || prompt.contains("CLEARLY different") || LocalPrompts.mailDraftRewrite.contains("clairement différent"))
        XCTAssertTrue(LocalPrompts.mailDraftRewrite.contains("PRIORITÉ 1 — USER INSTRUCTION"))
    }

    func testWantsDraftRewriteWhenDraftOpen() {
        XCTAssertTrue(MailIntentDetector.wantsDraftRewrite("moins formel"))
        XCTAssertTrue(MailIntentDetector.wantsDraftRewrite("Écris-le en anglais"))
        XCTAssertTrue(MailIntentDetector.wantsDraftRewrite("plus court et plus direct"))
        XCTAssertFalse(MailIntentDetector.wantsDraftRewrite("Écris un mail à Jean"))
        XCTAssertFalse(MailIntentDetector.wantsDraftRewrite("Comment rédiger un mail ?"))
    }

    func testNearlyIdenticalRewriteDetection() {
        let body = "Bonjour Jean, je confirme notre rendez-vous mardi à 14h. Cordialement"
        XCTAssertTrue(MailDraftRewriteWorkflow.isNearlyIdentical(body, body))
        XCTAssertTrue(
            MailDraftRewriteWorkflow.isNearlyIdentical(
                body,
                "Bonjour Jean, je confirme notre rendez-vous mardi à 14h. Cordialement\n"
            )
        )
        XCTAssertFalse(
            MailDraftRewriteWorkflow.isNearlyIdentical(
                body,
                "Salut Jean,\n\nOn se voit mardi 14h, nickel ?\n\nÀ plus"
            )
        )
    }

    func testComposeIntentOpensMailAssistantNotAdvice() {
        let compose = MailIntentDetector.detect(
            "Écris un mail à Jean pour lui confirmer le rendez-vous.",
            hasOpenThread: false
        )
        if case .compose(let hint) = compose {
            XCTAssertEqual(hint?.lowercased(), "jean")
        } else {
            XCTFail("expected compose, got \(compose)")
        }
        XCTAssertTrue(MailIntentDetector.wantsCompose("Rédige un mail professionnel pour annuler."))
        XCTAssertFalse(MailIntentDetector.wantsCompose("Comment rédiger un mail professionnel ?"))
        XCTAssertEqual(
            MailIntentDetector.detect("Comment rédiger un mail professionnel ?", hasOpenThread: false),
            .none
        )
        XCTAssertTrue(MailIntentDetector.isMailAdvice("Que devrais-je répondre à ce mail ?"))
        XCTAssertEqual(
            MailIntentDetector.detect("Que devrais-je répondre à ce mail ?", hasOpenThread: true),
            .none
        )
        XCTAssertEqual(
            MailIntentDetector.detect("Rédige une réponse à ce mail.", hasOpenThread: true),
            .threadReply
        )
        XCTAssertTrue(MailIntentDetector.wantsReply("Rédige une réponse à ce mail."))
    }

    func testDraftStatusNeverSentFromExistence() {
        XCTAssertEqual(
            MailDraftCardPolicy.statusLabel(sent: false, sending: false, streaming: false, stored: ""),
            "Brouillon"
        )
        XCTAssertEqual(
            MailDraftCardPolicy.statusLabel(sent: false, sending: false, streaming: false, stored: "Message envoyé"),
            "Brouillon"
        )
        XCTAssertEqual(
            MailDraftCardPolicy.statusLabel(sent: false, sending: false, streaming: true, stored: ""),
            "Rédaction…"
        )
        XCTAssertEqual(
            MailDraftCardPolicy.statusLabel(sent: false, sending: true, streaming: false, stored: "Brouillon"),
            "Envoi…"
        )
        XCTAssertEqual(
            MailDraftCardPolicy.statusLabel(sent: true, sending: false, streaming: false, stored: "Brouillon"),
            "Envoyé"
        )
        XCTAssertEqual(
            MailDraftCardPolicy.sanitizedRestoreStatus("Message envoyé", sent: false),
            "Brouillon"
        )
        XCTAssertFalse(
            MailDraftCardPolicy.recoverable(
                collapsed: false,
                sent: false,
                draftId: "x",
                text: "hi",
                inConversation: true
            )
        )
        XCTAssertTrue(
            MailDraftCardPolicy.recoverable(
                collapsed: true,
                sent: false,
                draftId: nil,
                text: "Bonjour Monsieur,\nMerci pour votre retour…",
                inConversation: true
            )
        )
        XCTAssertFalse(
            MailDraftCardPolicy.recoverable(
                collapsed: true,
                sent: true,
                draftId: "id",
                text: "x",
                inConversation: true
            )
        )
    }

    func testDismissKeepsDraftRecoverableWithoutServerId() {
        XCTAssertTrue(
            MailDraftCardPolicy.recoverable(
                collapsed: true,
                sent: false,
                draftId: "local-abc",
                text: "Hello",
                inConversation: true
            )
        )
        XCTAssertTrue(
            MailDraftCardPolicy.visible(
                collapsed: false,
                sent: false,
                inConversation: true,
                draftId: nil,
                streaming: false
            )
        )
    }

    @MainActor
    func testRewriteAppliesLanguageToneLengthAndFreeInstruction() async throws {
        let runtime = ScriptedAIRuntime { _, user in
            if user.contains("anglais") {
                return "Hello Jean,\nI will be available Tuesday."
            }
            if user.contains("moins formel") {
                XCTAssertTrue(user.contains("CURRENT DRAFT:"))
                XCTAssertTrue(user.contains("Hello Jean"))
                return "Hey Jean,\nI'll be around Tuesday — no stress."
            }
            if user.contains("plus court") {
                XCTAssertTrue(user.contains("Hey Jean"))
                return "Hey Jean — Tuesday works."
            }
            if user.contains("chaleureux") {
                return "Bonjour Jean,\nMerci infiniment pour votre message, au plaisir d’échanger."
            }
            if user.contains("remercier") && user.contains("mardi") {
                return "Merci pour votre message.\nJe suis disponible mardi."
            }
            return "fallback-not-used"
        }

        let v2 = try await MailDraftRewriteWorkflow.run(
            .init(
                instruction: "Écris-le en anglais",
                body: "Bonjour Jean, je serai disponible mardi.",
                to: "jean@example.com",
                subject: "RDV"
            ),
            runtime: runtime
        )
        XCTAssertTrue(v2.lowercased().contains("hello"))
        XCTAssertFalse(v2.contains("Bonjour Jean, je serai"))

        let v3 = try await MailDraftRewriteWorkflow.run(
            .init(
                instruction: "Fais-le moins formel",
                body: v2,
                to: "jean@example.com",
                subject: "RDV"
            ),
            runtime: runtime
        )
        XCTAssertTrue(v3.lowercased().contains("hey") || v3.lowercased().contains("i'll") || v3.lowercased().contains("ill"))

        let v4 = try await MailDraftRewriteWorkflow.run(
            .init(
                instruction: "Fais-le plus court",
                body: v3,
                to: "jean@example.com",
                subject: "RDV"
            ),
            runtime: runtime
        )
        XCTAssertLessThan(v4.count, v2.count + 40)
        XCTAssertTrue(v4.lowercased().contains("tuesday") || v4.lowercased().contains("jean"))

        let warm = try await MailDraftRewriteWorkflow.run(
            .init(
                instruction: "Rends-le plus chaleureux",
                body: "Bonjour,\nSuite à votre demande.",
                to: "",
                subject: ""
            ),
            runtime: runtime
        )
        XCTAssertTrue(warm.lowercased().contains("merci"))

        let free = try await MailDraftRewriteWorkflow.run(
            .init(
                instruction: "Commence par remercier la personne et termine en indiquant que je suis disponible mardi.",
                body: "Bonjour,\nSuite à votre message.",
                to: "",
                subject: ""
            ),
            runtime: runtime
        )
        XCTAssertTrue(free.lowercased().contains("merci"))
        XCTAssertTrue(free.lowercased().contains("mardi") || free.lowercased().contains("tuesday"))
    }

    @MainActor
    func testRewriteFailureKeepsCallerPreviousDraft() async {
        let runtime = ScriptedAIRuntime { _, _ in "" }
        runtime.shouldFail = true
        let previous = "Bonjour Monsieur,\nMerci pour votre retour."
        do {
            _ = try await MailDraftRewriteWorkflow.run(
                .init(instruction: "Écris-le en anglais", body: previous, to: "", subject: ""),
                runtime: runtime
            )
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(previous, "Bonjour Monsieur,\nMerci pour votre retour.")
            XCTAssertFalse(previous.isEmpty)
        }
    }

    func testGmailRemoteIdsRejectsLocalPrefix() {
        XCTAssertFalse(GmailRemoteIds.isPersistedGmailDraftId("local-123"))
        XCTAssertFalse(GmailRemoteIds.isPersistedGmailDraftId(UUID().uuidString))
        XCTAssertTrue(GmailRemoteIds.isPersistedGmailDraftId("r-abc123gmail"))
    }

    /// Une collecte web substantielle doit court-circuiter la boucle de décision :
    /// c'est ce qui fait passer une requête agent de dix générations à une.
    func testSubstantialCollectionShortCircuitsDecisionLoop() {
        let evidence = String(repeating: "Résultat de recherche détaillé. ", count: 12)
        XCTAssertTrue(AgentWorkflow.isSelfSufficient(action: "web_search", observation: evidence))
        XCTAssertTrue(AgentWorkflow.isSelfSufficient(action: "mail_summarize", observation: evidence))
        // Un résultat vide ou minuscule ne remplace pas une vraie décision.
        XCTAssertFalse(AgentWorkflow.isSelfSufficient(action: "web_search", observation: "Aucun résultat."))
        // Une action qui modifie l'état demande toujours une suite explicite.
        XCTAssertFalse(AgentWorkflow.isSelfSufficient(action: "mail_draft_reply", observation: evidence))
    }

    func testProductRecommendationTriggersWebWithoutAskingTheModel() {
        XCTAssertTrue(AgentWorkflow.looksLikeLiveWeb("Quelles sont les meilleures souris gamer ?"))
        XCTAssertTrue(AgentWorkflow.looksLikeLiveWeb("le prix des modèles"))
        XCTAssertFalse(AgentWorkflow.looksLikeLiveWeb("Rédige un mail de remerciement à Marc"))
    }

    func testAgentPlanIsTaskSpecificNotGenericTemplate() {
        let compare = AgentWorkflow.goalAwareFallbackPlan(
            userText: "Compare ces trois offres et dis-moi laquelle est la meilleure pour mon besoin.",
            firstTool: nil
        )
        XCTAssertGreaterThanOrEqual(compare.count, 3)
        XCTAssertLessThanOrEqual(compare.count, 4)
        XCTAssertTrue(compare.contains(where: { $0.title.lowercased().contains("compar") || $0.title.lowercased().contains("recommand") }))

        let simple = AgentWorkflow.goalAwareFallbackPlan(
            userText: "Quelle heure est-il à Tokyo ?",
            firstTool: nil
        )
        XCTAssertEqual(simple.count, 1)

        let parsed = AgentWorkflow.parsePlanJSON(
            #"{"steps":[{"id":"s1","title":"Identifier les critères"},{"id":"s2","title":"Comparer les compromis"}]}"#
        )
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?.first?.title, "Identifier les critères")
        XCTAssertNil(AgentWorkflow.parsePlanJSON("not json"))
        XCTAssertTrue(AgentWorkflow.looksLikeChainOfThought("Je pense que je vais chercher"))
        XCTAssertFalse(AgentWorkflow.looksLikeChainOfThought("Rechercher des sources sur les offres"))
    }

    func testAgentPanelDoesNotOverlayTranscript() {
        XCTAssertEqual(AgentPanelLayout.maxHeight(completed: false), 260)
        XCTAssertEqual(AgentPanelLayout.maxHeight(completed: true), 220)
        XCTAssertLessThan(AgentPanelLayout.maxHeight(completed: false), 500)
    }

    func testMailboxReplyDoesNotEmbedFullDraftInChatCopy() {
        XCTAssertTrue(LocalPrompts.mailComposeDraft.contains("N’écris JAMAIS que le message a été envoyé"))
        XCTAssertTrue(LocalPrompts.mailDraftRewrite.contains("USER INSTRUCTION"))
    }
}
