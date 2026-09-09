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

    private var executionProfile: LocalModelExecutionProfile {
        LocalModelManager.shared.activeDescriptor.executionProfile
    }

    private var maxMailMessages: Int { executionProfile.maxMailMessages }

    // MARK: - Search + answer

    func searchAndAnswer(_ userQuery: String) async throws -> String {
        let query = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw LocalMailAssistantError.emptyQuery }
        try ensureGmailConnected()
        try await ensureModelReady()
        try Task.checkCancellation()

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let intent = MailIntentDetector.detect(query, hasOpenThread: false)
        let gmailQ = MailIntentDetector.gmailQuery(
            for: intent == .none ? .genericMailbox : intent,
            userText: query
        )
        let limit = MailIntentDetector.resultLimit(
            for: intent == .none ? .genericMailbox : intent,
            profile: executionProfile
        )

        let page = try await gmail.listMessages(query: gmailQ, pageToken: nil, maxResults: limit)
        guard !page.messages.isEmpty else { throw LocalMailAssistantError.noResults }

        var contextBlocks: [String] = []
        for (idx, m) in page.messages.prefix(limit).enumerated() {
            try Task.checkCancellation()
            var body = m.snippet ?? ""
            if let full = try? await gmail.getMessage(id: m.id) {
                body = MailThreadPromptBuilder.clipBody(
                    MailThreadPromptBuilder.sanitize(MailThreadPromptBuilder.preferredBody(full)),
                    maxChars: executionProfile.maxMailBodyChars / max(limit, 1)
                )
            }
            contextBlocks.append(
                """
                [\(idx + 1)] threadId=\(m.threadId ?? m.id)
                De: \(m.from ?? "—")
                Objet: \(m.subject ?? "—")
                Date: \(m.date ?? "—")
                \(body)
                """
            )
        }

        return try await generateMessages(
            system: LocalPrompts.mailMailbox,
            user: """
            Question de l’utilisateur :
            \(query)

            Mails Gmail (ne rien inventer hors de cette liste ; tu as accès à ces mails via l’application) :
            \(contextBlocks.joined(separator: "\n\n"))
            """,
            maxTokens: executionProfile.outputTokens(for: .mailSummary)
        )
    }

    // MARK: - Summarize

    func summarizeThread(
        threadId: String,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
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
        let user = MailThreadPromptBuilder.userPrompt(
            thread: thread,
            profile: executionProfile,
            kind: .summary
        )
        return try await generateMessages(
            system: LocalPrompts.mailSummary,
            user: user,
            maxTokens: executionProfile.outputTokens(for: .mailSummary),
            onToken: onToken
        )
    }

    // MARK: - Draft reply (NO send)

    @discardableResult
    func draftReply(
        threadId: String,
        instruction: String,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> MailSendConfirmation {
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
        let to = Self.extractReplyAddress(from: thread.from) ?? ""
        let subject: String = {
            let s = thread.subject ?? ""
            if s.lowercased().hasPrefix("re:") { return s }
            return s.isEmpty ? "Re:" : "Re: \(s)"
        }()
        let user = MailThreadPromptBuilder.userPrompt(
            thread: thread,
            profile: executionProfile,
            kind: .reply(instruction: instructionTrimmed)
        )
        let proposed = MailSignature.appendOnce(
            try await generateMessages(
                system: LocalPrompts.mailReplyDraft,
                user: user,
                maxTokens: executionProfile.outputTokens(for: .mailReply),
                onToken: onToken
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        )

        var draftId: String?
        if !to.isEmpty {
            do {
                let draft = try await gmail.createDraft(
                    to: to,
                    subject: subject,
                    body: MailThreadPromptBuilder.plainBodyForSend(proposed),
                    threadId: thread.threadId ?? thread.id
                )
                draftId = draft.id
            } catch {
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
                body: MailThreadPromptBuilder.plainBodyForSend(pending.proposedBody),
                threadId: pending.threadId
            )
        }
        pendingConfirmation = nil
    }

    func cancelPendingSend() {
        pendingConfirmation = nil
    }

    func cancelGeneration() async {
        await LocalAIRuntime.shared.cancel()
        await inference.cancel()
    }

    // MARK: - Helpers

    private func ensureGmailConnected() throws {
        guard oauth.isConnected else {
            throw LocalMailAssistantError.gmailNotConnected
        }
    }

    private func ensureModelReady() async throws {
        if !LocalModelManager.shared.isReady {
            await LocalModelManager.shared.loadIntoEngine()
        }
        guard LocalModelManager.shared.isReady else {
            throw LocalMailAssistantError.modelNotReady
        }
        guard LocalInferenceEngine.isLlamaRuntimeAvailable else {
            throw LocalMailAssistantError.modelNotReady
        }
    }

    private func generateMessages(
        system: String,
        user: String,
        maxTokens: Int,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        do {
            return try await LocalAIRuntime.shared.generateStream(
                system: system,
                messages: [LLMChatMessage(role: .user, content: user)],
                maxTokens: maxTokens,
                onToken: { token in
                    onToken?(token)
                }
            )
        } catch AIRuntimeError.cancelled {
            throw LocalMailAssistantError.cancelled
        } catch AIRuntimeError.emptyGeneration {
            throw LocalMailAssistantError.inference(
                "Le modèle n’a produit aucune réponse exploitable. Réessaie ou vérifie que le modèle est chargé."
            )
        } catch let error as AIRuntimeError {
            lastError = error.localizedDescription
            throw LocalMailAssistantError.inference(error.localizedDescription)
        } catch is CancellationError {
            throw LocalMailAssistantError.cancelled
        } catch {
            lastError = error.localizedDescription
            throw LocalMailAssistantError.inference(error.localizedDescription)
        }
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

/// Construit le prompt user mail (fil chronologique, sans historique Chat).
enum MailThreadPromptBuilder {
    enum Kind {
        case summary
        case reply(instruction: String)
    }

    static func userPrompt(
        thread: DirectMailThread,
        profile: LocalModelExecutionProfile,
        kind: Kind
    ) -> String {
        let ordered = chronological(thread.messages)
        let keep = max(1, min(profile.maxMailMessages, ordered.count))
        let slice = Array(ordered.suffix(keep))
        let perMessage = max(400, profile.maxMailBodyChars / max(keep, 1))
        var blocks: [String] = []
        blocks.append("Objet: \(thread.subject ?? "—")")
        blocks.append("Messages: \(slice.count)/\(ordered.count) (ordre chronologique)")
        for (idx, msg) in slice.enumerated() {
            let last = idx == slice.count - 1
            let header = last ? "--- Message \(idx + 1) (dernier, prioritaire) ---" : "--- Message \(idx + 1) ---"
            let body = clipBody(sanitize(preferredBody(msg)), maxChars: last ? perMessage * 2 : perMessage)
            blocks.append(
                """
                \(header)
                De: \(msg.from ?? "—")
                Date: \(msg.date ?? "—")
                \(body.isEmpty ? "(corps vide — extraits: \(msg.snippet ?? "—"))" : body)
                """
            )
        }
        let fil = blocks.joined(separator: "\n\n")
        switch kind {
        case .summary:
            return "Fil Gmail à résumer (uniquement ce contenu) :\n\n\(fil)"
        case .reply(let instruction):
            let inst = instruction.isEmpty
                ? "Rédige une réponse qui traite la demande du dernier message."
                : instruction
            return """
            Instruction (rédaction uniquement, pas d’envoi) :
            \(inst)

            \(fil)
            """
        }
    }

    /// Conversion tardive Markdown → texte pour Gmail send.
    static func plainBodyForSend(_ markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "*", with: "")
        text = text.replacingOccurrences(of: "^#+\\s+", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func chronological(_ messages: [DirectMailMessage]) -> [DirectMailMessage] {
        messages.sorted { a, b in
            (a.date ?? "") < (b.date ?? "")
        }
    }

    static func preferredBody(_ msg: DirectMailMessage) -> String {
        if let plain = msg.bodyPlain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plain
        }
        if let html = msg.bodyHtml, !html.isEmpty {
            return stripHTML(html)
        }
        return msg.snippet ?? ""
    }

    static func sanitize(_ text: String) -> String {
        let filtered = text.unicodeScalars.filter { scalar in
            scalar.value == 9 || scalar.value == 10 || scalar.value == 13
                || (scalar.value >= 32 && scalar.value != 127)
        }
        var out = String(String.UnicodeScalarView(filtered))
        if let sig = out.range(of: "\n-- \n") {
            out = String(out[..<sig.lowerBound])
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clipBody(_ text: String, maxChars: Int) -> String {
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars)) + "\n…[tronqué]"
    }

    static func stripHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
