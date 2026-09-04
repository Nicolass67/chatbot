import Foundation

/// Service SSE chat avec session URLSession dédiée — `cancel()` invalide la requête HTTP
/// pour propager `request.signal` côté Next (`/api/chat`).
actor ChatStreamingService {
    private var urlSession: URLSession?
    private var generation: UInt64 = 0

    func cancel() {
        generation &+= 1
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    func stream(
        baseURL: URL,
        token: String?,
        conversationId: String,
        message: String,
        options: ChatSendOptions,
        onEvent: @escaping @Sendable (ChatSSEParser.Event) -> Void
    ) async throws {
        cancel()
        let myGeneration = generation

        // Deterministic SSE for Simulator XCUITest — never hits the network.
        if UITestMode.isActive {
            onEvent(ChatSSEParser.Event(type: "status", payload: ["type": "status", "phase": "thinking"]))
            try await Task.sleep(nanoseconds: 80_000_000)
            guard myGeneration == generation else { return }
            onEvent(ChatSSEParser.Event(type: "token", payload: [
                "type": "token",
                "delta": "Réponse UITest déterministe. ",
            ]))
            onEvent(ChatSSEParser.Event(type: "done", payload: ["type": "done"]))
            return
        }

        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ios", forHTTPHeaderField: "X-Client")
        req.setValue("3.0.0", forHTTPHeaderField: "X-App-Version")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = [
            "conversationId": conversationId,
            "message": message,
            "attachmentIds": options.attachmentIds,
            "mode": options.mode,
        ]
        if options.regenerate { body["regenerate"] = true }
        if let editId = options.editMessageId { body["editMessageId"] = editId }
        if let ctx = options.activeContext, !ctx.isEmpty {
            body["activeContext"] = ctx.asDictionary()
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default)
        urlSession = session
        defer {
            if urlSession === session {
                session.finishTasksAndInvalidate()
                urlSession = nil
            }
        }

        let (bytes, resp) = try await session.bytes(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
            throw APIClientError.unauthorized
        }
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIClientError.http(http.statusCode, "SSE failed")
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard myGeneration == generation else { return }
            if let event = ChatSSEParser.parseLine(line) {
                onEvent(event)
            }
        }
    }
}

public enum ChatSSEParser {
    public struct Event: @unchecked Sendable {
        public let type: String
        public let payload: [String: Any]
    }

    public static func parseLine(_ line: String) -> Event? {
        if line.hasPrefix(":") { return nil }
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }
        return Event(type: type, payload: obj)
    }
}
