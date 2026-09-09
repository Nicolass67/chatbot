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
        case .inference(let detail):
            return detail
        }
    }
}

/// Assistant mail **100 % local** : Gmail API device + `LocalInferenceEngine` (pas de PC).
///
/// Règle d’or : `draftReply` propose un texte ; seul `confirmSend` appelle
/// `sendDraft` / `sendMessage` après action utilisateur explicite.
@MainActor
final class LocalMailAssistant: ObservableObject {
    @Published private(set) var pendingConfirmation: MailSendConfirmation?
    @Published var lastError: String?
    @Published var isBusy = false

    private let gmail: DirectGmailClient
    private let oauth: GmailOAuthSession
    private let inference: LocalInferenceEngine

    /// Budget contexte Qwen3 1.7B — tronquer le corps mail.
    private let maxMailChars = 6_000
    private let maxAnswerTokens = 512
    private let maxDraftTokens = 400

    init(
        oauth: GmailOAuthSession = .shared,
        gmail: DirectGmailClient? = nil,
        inference: LocalInferenceEngine = .shared
    ) {
        self.oauth = oauth
        self.gmail = gmail ?? DirectGmailClient(oauth: oauth)
        self.inference = inference
    }

    // MARK: - Search + answer

    /// Recherche Gmail puis réponse locale (faits issus des résultats uniquement).
    func searchAndAnswer(_ userQuery: String) async throws -> String {
        let query = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw LocalMailAssistantError.emptyQuery }
        try ensureGmailConnected()
        try await ensureModelReady()

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let page = try await gmail.listMessages(query: query, pageToken: nil, maxResults: 8)
        guard !page.messages.isEmpty else { throw LocalMailAssistantError.noResults }

        let context = page.messages.prefix(8).enumerated().map { idx, m in
            """
            [\(idx + 1)] id=\(m.id)
            De: \(m.from ?? "—")
            Objet: \(m.subject ?? "—")
            Date: \(m.date ?? "—")
            Extrait: \(m.snippet ?? "—")
            """
        }.joined(separator: "\n\n")

        let prompt = Self.buildPrompt(
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

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let thread = try await gmail.getThread(id: id)
        let body = truncatedMailBody(thread.bodyPlain ?? thread.messages.compactMap(\.bodyPlain).joined(separator: "\n\n"))
        let prompt = Self.buildPrompt(
            system: LocalPrompts.mailSummary,
            user: """
            Fil Gmail à résumer.
            Objet: \(thread.subject ?? "—")
            De: \(thread.from ?? "—")
            Date: \(thread.date ?? "—")

            Contenu :
            \(body)
            """
        )
        return try await generateText(prompt: prompt, maxTokens: maxAnswerTokens)
    }

    // MARK: - Draft reply (NO send)

    /// Propose un texte de réponse. **N’envoie pas** le mail.
    @discardableResult
    func draftReply(threadId: String, instruction: String) async throws -> MailSendConfirmation {
        let id = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionTrimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw LocalMailAssistantError.emptyQuery }
        try ensureGmailConnected()
        try await ensureModelReady()

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let thread = try await gmail.getThread(id: id)
        let body = truncatedMailBody(thread.bodyPlain ?? "")
        let to = Self.extractReplyAddress(from: thread.from) ?? ""
        let subject: String = {
            let s = thread.subject ?? ""
            if s.lowercased().hasPrefix("re:") { return s }
            return s.isEmpty ? "Re:" : "Re: \(s)"
        }()

        let prompt = Self.buildPrompt(
            system: LocalPrompts.mailReplyDraft,
            user: """
            Instruction utilisateur (rédaction uniquement, pas d’envoi) :
            \(instructionTrimmed.isEmpty ? "Propose une réponse polie et concise." : instructionTrimmed)

            Fil :
            Objet: \(thread.subject ?? "—")
            De: \(thread.from ?? "—")

            Contenu :
            \(body)

            Réponds uniquement avec le corps du mail proposé (texte brut).
            """
        )
        let proposed = try await generateText(prompt: prompt, maxTokens: maxDraftTokens)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Brouillon Gmail optionnel (compose) — toujours avant confirmation d’envoi.
        var draftId: String?
        if !to.isEmpty {
            let draft = try await gmail.createDraft(
                to: to,
                subject: subject,
                body: proposed,
                threadId: thread.threadId ?? thread.id
            )
            draftId = draft.id
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

    /// Seul point d’entrée autorisé pour un envoi Gmail depuis l’assistant local.
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
        var buffer = ""
        do {
            try await inference.generate(prompt: prompt, maxTokens: maxTokens) { piece in
                buffer += piece
            }
        } catch let error as LocalInferenceError {
            let message = error.localizedDescription
            lastError = message
            throw LocalMailAssistantError.inference(message)
        } catch {
            let message = error.localizedDescription
            lastError = message
            throw LocalMailAssistantError.inference(message)
        }
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LocalMailAssistantError.inference("Réponse vide du modèle local.")
        }
        return trimmed
    }

    private func truncatedMailBody(_ text: String) -> String {
        if text.count <= maxMailChars { return text }
        let idx = text.index(text.startIndex, offsetBy: maxMailChars)
        return String(text[..<idx]) + "\n…[tronqué]"
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

    private static func buildPrompt(system: String, user: String) -> String {
        // Format simple compatible Qwen chat — pas de dépendance au backend PC.
        """
        <|im_start|>system
        \(system)
        <|im_end|>
        <|im_start|>user
        \(user)
        <|im_end|>
        <|im_start|>assistant
        """
    }

}
