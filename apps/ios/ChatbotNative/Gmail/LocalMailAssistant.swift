import Foundation
import Combine

/// Proposition d’envoi — l’envoi réel n’a lieu que via `confirmSend`.
struct MailSendConfirmation: Identifiable, Hashable, Sendable {
    let id: UUID
    let to: String
    let subject: String
    let proposedBody: String
    let threadId: String?
    /// Brouillon Gmail créé avant confirmation (optionnel).
    let draftId: String?

    init(
        id: UUID = UUID(),
        to: String,
        subject: String,
        proposedBody: String,
        threadId: String? = nil,
        draftId: String? = nil
    ) {
        self.id = id
        self.to = to
        self.subject = subject
        self.proposedBody = proposedBody
        self.threadId = threadId
        self.draftId = draftId
    }
}

enum LocalMailAssistantError: Error, LocalizedError, Sendable {
    case gmailNotConnected
    case modelNotReady
    case emptyQuery
    case noResults
    case noPendingConfirmation
    case confirmationMismatch
    case cancelled
    case emptyMailContent
    case inference(String)

    var errorDescription: String? {
        switch self {
        case .gmailNotConnected:
            return "Connecte Gmail sur cet iPhone pour continuer."
        case .modelNotReady:
            return "L’IA locale n’est pas prête. Installe et charge le modèle dans Réglages."
        case .emptyQuery:
            return "Indique une recherche ou une instruction."
        case .noResults:
            return "Aucun mail trouvé pour cette recherche."
        case .noPendingConfirmation:
            return "Aucune proposition d’envoi en attente."
        case .confirmationMismatch:
            return "La confirmation ne correspond plus à la proposition en cours."
        case .cancelled:
            return "Génération annulée."
        case .emptyMailContent:
            return "Ce mail n’a pas de contenu texte exploitable pour l’IA locale."
        case .inference(let detail):
            return detail
        }
    }
}

/// Assistant mail **100 % local** : Gmail API device + `LocalInferenceEngine` (pas de PC).
@MainActor
final class LocalMailAssistant: ObservableObject {
    @Published private(set) var pendingConfirmation: MailSendConfirmation?
    @Published var lastError: String?
    @Published var isBusy = false

    private let gmail: DirectGmailClient
    private let oauth: GmailOAuthSession
    private let inference: LocalInferenceEngine

    init(
        oauth: GmailOAuthSession = .shared,
        gmail: DirectGmailClient? = nil,
        inference: LocalInferenceEngine = .shared
    ) {
        self.oauth = oauth
        self.gmail = gmail ?? DirectGmailClient(oauth: oauth)
        self.inference = inference
    }

    private var runtimeProfile: LocalModelRuntimeProfile {
        LocalModelManager.shared.activeRuntimeProfile
    }

    private var executionProfile: LocalModelExecutionProfile {
        LocalModelManager.shared.activeDescriptor.executionProfile
    }

    private var maxMailChars: Int { executionProfile.maxMailBodyChars }
    private var maxAnswerTokens: Int { executionProfile.maxOutputTokens }
    private var maxDraftTokens: Int { min(320, executionProfile.maxOutputTokens) }
    private var maxMailMessages: Int { executionProfile.maxMailMessages }

    // MARK: - Search + answer

    func searchAndAnswer(_ userQuery: String) async throws -> String {
        let query = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw LocalMailAssistantError.emptyQuery }
        try ensureGmailConnected()
        try await ensureModelReady()

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let page = try await gmail.listMessages(query: query, pageToken: nil, maxResults: maxMailMessages)
        guard !page.messages.isEmpty else { throw LocalMailAssistantError.noResults }

        let context = page.messages.prefix(maxMailMessages).enumerated().map { idx, m in
            """
            [\(idx + 1)] id=\(m.id)
            De: \(m.from ?? "—")
            Objet: \(m.subject ?? "—")
            Date: \(m.date ?? "—")
            Extrait: \(m.snippet ?? "—")
            """
        }.joined(separator: "\n\n")

        let prompt = buildPrompt(
            system: LocalPrompts.mailExtract,
            user: """
            Question de l’utilisateur :
            \(query)

            Résultats Gmail (ne rien inventer hors de cette liste) :
            \(context)
            """
        )
        return try await generateText(prompt: prompt, maxTokens: maxAnswerTokens)
    }

    // MARK: - Summarize

    func summarizeThread(threadId: String) async throws -> String {
        let id = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw LocalMailAssistantError.emptyQuery }
        try ensureGmailConnected()
        try await ensureModelReady()
        try Task.checkCancellation()

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let thread = try await gmail.getThread(id: id)
        try Task.checkCancellation()

        let joinedBodies = thread.messages
            .compactMap(\.bodyPlain)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        let rawBody: String = {
            if let plain = thread.bodyPlain,
               !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return plain
            }
            return joinedBodies
        }()
        let body = truncatedMailBody(sanitizeMailText(rawBody))
        let snippetFallback = thread.messages.compactMap(\.snippet).joined(separator: " · ")
        let content: String = {
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return body
            }
            if !snippetFallback.isEmpty { return snippetFallback }
            return "(Contenu texte indisponible — résume à partir des métadonnées uniquement.)"
        }()

        let prompt = buildPrompt(
            system: LocalPrompts.mailSummary,
            user: """
            Fil Gmail à résumer.
            Objet: \(thread.subject ?? "—")
            De: \(thread.from ?? "—")
            Date: \(thread.date ?? "—")

            Contenu :
            \(content)
            """
        )
        return try await generateText(prompt: prompt, maxTokens: maxAnswerTokens)
    }

    // MARK: - Draft reply (NO send)

    @discardableResult
    func draftReply(threadId: String, instruction: String) async throws -> MailSendConfirmation {
        let id = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionTrimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw LocalMailAssistantError.emptyQuery }
        try ensureGmailConnected()
        try await ensureModelReady()
        try Task.checkCancellation()

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let thread = try await gmail.getThread(id: id)
        try Task.checkCancellation()

        let joinedBodies = thread.messages
            .compactMap(\.bodyPlain)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        let rawBody: String = {
            if let plain = thread.bodyPlain,
               !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return plain
            }
            return joinedBodies
        }()
        let body = truncatedMailBody(sanitizeMailText(rawBody))
        let to = Self.extractReplyAddress(from: thread.from) ?? ""
        let subject: String = {
            let s = thread.subject ?? ""
            if s.lowercased().hasPrefix("re:") { return s }
            return s.isEmpty ? "Re:" : "Re: \(s)"
        }()

        let prompt = buildPrompt(
            system: LocalPrompts.mailReplyDraft,
            user: """
            Instruction utilisateur (rédaction uniquement, pas d’envoi) :
            \(instructionTrimmed.isEmpty ? "Propose une réponse polie et concise." : instructionTrimmed)

            Fil :
            Objet: \(thread.subject ?? "—")
            De: \(thread.from ?? "—")

            Contenu :
            \(body.isEmpty ? "(corps vide)" : body)

            Réponds uniquement avec le corps du mail proposé (texte brut).
            """
        )
        let proposed = try await generateText(prompt: prompt, maxTokens: maxDraftTokens)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Brouillon Gmail optionnel — échec réseau ≠ crash ; on garde quand même la proposition.
        var draftId: String?
        if !to.isEmpty {
            do {
                let draft = try await gmail.createDraft(
                    to: to,
                    subject: subject,
                    body: proposed,
                    threadId: thread.threadId ?? thread.id
                )
                draftId = draft.id
            } catch {
                // Non fatal : l’utilisateur peut copier / confirmer plus tard.
                lastError = "Proposition prête (brouillon Gmail non créé : \(error.localizedDescription))"
            }
        }

        let confirmation = MailSendConfirmation(
            to: to,
            subject: subject,
            proposedBody: proposed,
            threadId: thread.threadId ?? thread.id,
            draftId: draftId
        )
        pendingConfirmation = confirmation
        return confirmation
    }

    // MARK: - Confirmation gate

    func confirmSend(_ confirmation: MailSendConfirmation? = nil) async throws {
        guard let pending = confirmation ?? pendingConfirmation else {
            throw LocalMailAssistantError.noPendingConfirmation
        }
        if let current = pendingConfirmation, current.id != pending.id {
            throw LocalMailAssistantError.confirmationMismatch
        }
        try ensureGmailConnected()

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        if let draftId = pending.draftId, !draftId.isEmpty {
            try await gmail.sendDraft(id: draftId)
        } else {
            guard !pending.to.isEmpty else {
                throw DirectGmailError.invalidArgument("Destinataire manquant pour l’envoi.")
            }
            try await gmail.sendMessage(
                to: pending.to,
                subject: pending.subject,
                body: pending.proposedBody,
                threadId: pending.threadId
            )
        }
        pendingConfirmation = nil
    }

    func cancelPendingSend() {
        pendingConfirmation = nil
    }

    func cancelGeneration() async {
        await inference.cancel()
    }

    // MARK: - Helpers

    private func ensureGmailConnected() throws {
        guard oauth.isConnected else {
            throw LocalMailAssistantError.gmailNotConnected
        }
    }

    private func ensureModelReady() async throws {
        let loaded = await inference.isModelLoaded
        guard loaded else {
            throw LocalMailAssistantError.modelNotReady
        }
        guard LocalInferenceEngine.isLlamaRuntimeAvailable else {
            throw LocalMailAssistantError.modelNotReady
        }
    }

    private func generateText(prompt: String, maxTokens: Int) async throws -> String {
        let profile = runtimeProfile
        let accumulator = StringAccumulator()
        do {
            try await inference.generate(prompt: prompt, maxTokens: maxTokens) { [inference] piece in
                accumulator.append(piece)
                let cut = LocalChatTemplate.truncateAssistantOutput(accumulator.value, profile: profile)
                if cut.hitStop {
                    accumulator.replace(with: cut.text)
                    await inference.cancel()
                }
            }
        } catch let error as LocalInferenceError {
            // Cancel après stop volontaire → cancelled ; on accepte le texte déjà tronqué.
            if case .cancelled = error {
                let truncated = LocalChatTemplate.truncateAssistantOutput(accumulator.value, profile: profile).text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !truncated.isEmpty { return truncated }
                throw LocalMailAssistantError.cancelled
            }
            let message = error.localizedDescription
            lastError = message
            throw LocalMailAssistantError.inference(message)
        } catch is CancellationError {
            let truncated = LocalChatTemplate.truncateAssistantOutput(accumulator.value, profile: profile).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !truncated.isEmpty { return truncated }
            throw LocalMailAssistantError.cancelled
        } catch {
            let message = error.localizedDescription
            lastError = message
            throw LocalMailAssistantError.inference(message)
        }

        let truncated = LocalChatTemplate.truncateAssistantOutput(accumulator.value, profile: profile).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !truncated.isEmpty else {
            throw LocalMailAssistantError.inference(
                "Le modèle n’a produit aucune réponse exploitable. Réessaie ou vérifie que le modèle est chargé."
            )
        }
        return truncated
    }

    private func buildPrompt(system: String, user: String) -> String {
        LocalChatTemplate.buildPrompt(system: system, user: user, profile: runtimeProfile)
    }

    private func truncatedMailBody(_ text: String) -> String {
        if text.count <= maxMailChars { return text }
        let idx = text.index(text.startIndex, offsetBy: maxMailChars)
        return String(text[..<idx]) + "\n…[tronqué]"
    }

    /// Retire null bytes / contrôles qui peuvent faire planter le tokenizer.
    private func sanitizeMailText(_ text: String) -> String {
        let filtered = text.unicodeScalars.filter { scalar in
            scalar.value == 9 || scalar.value == 10 || scalar.value == 13
                || (scalar.value >= 32 && scalar.value != 127)
        }
        return String(String.UnicodeScalarView(filtered))
    }

    private static func extractReplyAddress(from fromHeader: String?) -> String? {
        guard let fromHeader, !fromHeader.isEmpty else { return nil }
        if let start = fromHeader.firstIndex(of: "<"),
           let end = fromHeader.firstIndex(of: ">"),
           start < end {
            return String(fromHeader[fromHeader.index(after: start)..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = fromHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") ? trimmed : nil
    }
}

/// Accumulateur thread-safe pour callbacks `@Sendable` de génération.
private final class StringAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func append(_ piece: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer += piece
    }

    func replace(with text: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer = text
    }
}
