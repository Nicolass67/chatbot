import Foundation

/// Construction RFC822 + base64url pour `users.messages.send`.
/// Pas de brouillon Gmail : le MIME est le message final.
enum GmailRfc822 {
    struct Attachment: Equatable, Sendable {
        var filename: String
        var mimeType: String
        var data: Data
    }

    enum EncodeError: Error, Equatable, LocalizedError {
        case emptyBody
        case missingRecipient

        var errorDescription: String? {
            switch self {
            case .emptyBody:
                return "Impossible d’envoyer un message vide."
            case .missingRecipient:
                return "Destinataire manquant."
            }
        }
    }

    /// Encode un message prêt pour Gmail API (`raw` base64url, sans padding).
    static func encodeRaw(
        to: String,
        cc: String? = nil,
        bcc: String? = nil,
        subject: String,
        body: String,
        inReplyTo: String? = nil,
        references: String? = nil,
        attachments: [Attachment] = []
    ) throws -> String {
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTo.isEmpty else { throw EncodeError.missingRecipient }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { throw EncodeError.emptyBody }

        let rfc = buildRFC822(
            to: trimmedTo,
            cc: Self.optionalHeader(cc),
            bcc: Self.optionalHeader(bcc),
            subject: subject,
            body: trimmedBody,
            inReplyTo: Self.angleAddr(inReplyTo),
            references: Self.optionalHeader(references),
            attachments: attachments
        )
        return Data(rfc.utf8).base64URLEncodedString()
    }

    /// RFC822 décodable (tests) — toujours `\r\n`, corps réellement présent.
    static func buildRFC822(
        to: String,
        cc: String?,
        bcc: String?,
        subject: String,
        body: String,
        inReplyTo: String?,
        references: String?,
        attachments: [Attachment]
    ) -> String {
        let safeSubject = subject
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        var headers = [
            "To: \(to)",
            "Subject: \(safeSubject)",
            "MIME-Version: 1.0",
        ]
        if let cc, !cc.isEmpty { headers.append("Cc: \(cc)") }
        if let bcc, !bcc.isEmpty { headers.append("Bcc: \(bcc)") }
        if let inReplyTo, !inReplyTo.isEmpty { headers.append("In-Reply-To: \(inReplyTo)") }
        if let references, !references.isEmpty { headers.append("References: \(references)") }

        if attachments.isEmpty {
            headers.append("Content-Type: text/plain; charset=UTF-8")
            headers.append("Content-Transfer-Encoding: 8bit")
            return headers.joined(separator: "\r\n") + "\r\n\r\n" + body + "\r\n"
        }

        let boundary = "ChatbotBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        headers.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
        var raw = headers.joined(separator: "\r\n") + "\r\n\r\n"
        raw += "--\(boundary)\r\n"
        raw += "Content-Type: text/plain; charset=UTF-8\r\n"
        raw += "Content-Transfer-Encoding: 8bit\r\n\r\n"
        raw += "\(body)\r\n"
        for att in attachments {
            let filename = att.filename
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            let mime = att.mimeType.isEmpty ? "application/octet-stream" : att.mimeType
            raw += "--\(boundary)\r\n"
            raw += "Content-Type: \(mime); name=\"\(filename)\"\r\n"
            raw += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n"
            raw += "Content-Transfer-Encoding: base64\r\n\r\n"
            raw += Self.wrapBase64(att.data.base64EncodedString())
        }
        raw += "--\(boundary)--\r\n"
        return raw
    }

    static func angleAddr(_ value: String?) -> String? {
        guard let raw = optionalHeader(value) else { return nil }
        if raw.hasPrefix("<"), raw.hasSuffix(">") { return raw }
        return "<\(raw)>"
    }

    static func decodeRaw(_ raw: String) -> String? {
        var s = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - s.count % 4
        if pad < 4 { s += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func optionalHeader(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func wrapBase64(_ b64: String) -> String {
        var wrapped = ""
        var i = b64.startIndex
        while i < b64.endIndex {
            let end = b64.index(i, offsetBy: 76, limitedBy: b64.endIndex) ?? b64.endIndex
            wrapped += String(b64[i..<end]) + "\r\n"
            i = end
        }
        return wrapped
    }
}

/// Id Gmail distant (hex / `r-…`) vs UUID de brouillon serveur/local.
enum GmailRemoteIds {
    static func isPersistedGmailDraftId(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("local-") { return false }
        if UUID(uuidString: trimmed) != nil { return false }
        return true
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Un seul envoi Gmail à la fois (anti double tap / double Task), thread-safe.
enum GmailSendLock: Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var owner: UUID?
    }

    private static let state = State()

    static var isSending: Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.owner != nil
    }

    @discardableResult
    static func acquire() throws -> UUID {
        state.lock.lock()
        defer { state.lock.unlock() }
        if state.owner != nil {
            throw DirectGmailError.sendInProgress
        }
        let id = UUID()
        state.owner = id
        return id
    }

    static func release(_ id: UUID) {
        state.lock.lock()
        defer { state.lock.unlock() }
        if state.owner == id { state.owner = nil }
    }

    /// Tests uniquement.
    static func resetForTests() {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.owner = nil
    }
}
