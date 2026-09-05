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
        onEvent: @escaping @Sendable (ChatSSEParser.Event) async -> Void
    ) async throws {
        cancel()
        let myGeneration = generation

        // Deterministic SSE for Simulator XCUITest — never hits the network.
        if UITestMode.isActive {
            try await streamUITestFixture(
                mode: options.mode,
                myGeneration: myGeneration,
                onEvent: onEvent
            )
            return
        }

        var lastTransient: Error?
        // 502/503 = tunnel Cloudflare / PC momentanément injoignable après une grosse requête.
        for attempt in 0..<3 {
            guard myGeneration == generation else { throw CancellationError() }
            do {
                try await streamOnce(
                    baseURL: baseURL,
                    token: token,
                    conversationId: conversationId,
                    message: message,
                    options: options,
                    myGeneration: myGeneration,
                    onEvent: onEvent
                )
                return
            } catch let APIClientError.http(code, detail) where code == 502 || code == 503 {
                let message = Self.friendlyTransientMessage(code: code, detail: detail)
                lastTransient = APIClientError.http(code, message)
                if attempt < 2 {
                    try await Task.sleep(nanoseconds: UInt64(450_000_000) * UInt64(attempt + 1))
                    continue
                }
                throw lastTransient!
            }
        }
        throw lastTransient ?? APIClientError.http(503, Self.friendlyTransientMessage(code: 503, detail: nil))
    }

    private static func friendlyTransientMessage(code: Int, detail: String?) -> String {
        let d = (detail ?? "").lowercased()
        if d.contains("backend_offline") || d.contains("indisponible") {
            return "Le PC est momentanément injoignable. Réessaie dans quelques secondes."
        }
        return "Connexion interrompue (HTTP \(code)). Réessaie."
    }

    private func streamOnce(
        baseURL: URL,
        token: String?,
        conversationId: String,
        message: String,
        options: ChatSendOptions,
        myGeneration: UInt64,
        onEvent: @escaping @Sendable (ChatSSEParser.Event) async -> Void
    ) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ios", forHTTPHeaderField: "X-Client")
        req.setValue("3.0.0", forHTTPHeaderField: "X-App-Version")
        req.timeoutInterval = 120
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
            var detail = "SSE failed"
            var collected = Data()
            for try await chunk in bytes {
                collected.append(chunk)
                if collected.count > 2048 { break }
            }
            if let obj = try? JSONSerialization.jsonObject(with: collected) as? [String: Any] {
                if let err = obj["error"] as? String, !err.isEmpty {
                    detail = err
                } else if let message = obj["message"] as? String, !message.isEmpty {
                    detail = message
                }
            }
            throw APIClientError.http(http.statusCode, detail)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard myGeneration == generation else { throw CancellationError() }
            if let event = ChatSSEParser.parseLine(line) {
                await onEvent(event)
            }
        }
    }

    /// Fixtures SSE : thinking visible assez longtemps pour screenshot ; agent timeline ; Stop via cancel().
    private func streamUITestFixture(
        mode: String,
        myGeneration: UInt64,
        onEvent: @escaping @Sendable (ChatSSEParser.Event) async -> Void
    ) async throws {
        let scenario = UITestMode.sseScenario
        let useAgent = mode == "agent" || scenario == "agent" || scenario == "agent-error"

        if useAgent {
            await onEvent(ChatSSEParser.Event(type: "agent_start", payload: ["type": "agent_start"]))
            try await Task.sleep(nanoseconds: 120_000_000)
            guard myGeneration == generation else { throw CancellationError() }

            await onEvent(ChatSSEParser.Event(type: "agent_plan", payload: [
                "type": "agent_plan",
                "plan": [
                    "steps": [
                        ["id": "1", "title": "Analyser la demande"],
                        ["id": "2", "title": "Préparer la réponse"],
                    ],
                ],
            ] as [String: Any]))
            try await Task.sleep(nanoseconds: 200_000_000)
            guard myGeneration == generation else { throw CancellationError() }

            await onEvent(ChatSSEParser.Event(type: "agent_step", payload: [
                "type": "agent_step",
                "stepId": "1",
                "stepIndex": 0,
                "totalSteps": 2,
                "status": "running",
                "message": "Analyser la demande",
            ]))
            // Hold agent strip visible for XCUITest screenshot / Stop tap.
            try await Task.sleep(nanoseconds: 2_000_000_000)
            guard myGeneration == generation else { throw CancellationError() }

            if scenario == "agent-error" {
                await onEvent(ChatSSEParser.Event(type: "agent_step", payload: [
                    "type": "agent_step",
                    "stepId": "1",
                    "status": "error",
                    "message": "Permission denied accessing file",
                ]))
                try await Task.sleep(nanoseconds: 400_000_000)
                guard myGeneration == generation else { throw CancellationError() }
                await onEvent(ChatSSEParser.Event(type: "done", payload: ["type": "done"]))
                return
            }

            await onEvent(ChatSSEParser.Event(type: "agent_step", payload: [
                "type": "agent_step",
                "stepId": "1",
                "status": "done",
            ]))
            await onEvent(ChatSSEParser.Event(type: "agent_step", payload: [
                "type": "agent_step",
                "stepId": "2",
                "stepIndex": 1,
                "totalSteps": 2,
                "status": "running",
                "message": "Préparer la réponse",
            ]))
            try await Task.sleep(nanoseconds: 200_000_000)
            guard myGeneration == generation else { throw CancellationError() }

            await onEvent(ChatSSEParser.Event(type: "token", payload: [
                "type": "token",
                "content": "Réponse Agent UITest. ",
            ]))
            await onEvent(ChatSSEParser.Event(type: "agent_done", payload: ["type": "agent_done"]))
            await onEvent(ChatSSEParser.Event(type: "done", payload: ["type": "done"]))
            return
        }

        // Chat / thinking : status visible avant le premier token.
        await onEvent(ChatSSEParser.Event(type: "thinking", payload: [
            "type": "thinking",
            "message": "Réflexion…",
        ]))
        let holdNs: UInt64 = (scenario == "thinking") ? 2_400_000_000
            : (scenario == "chat") ? 1_600_000_000
            : 400_000_000
        try await Task.sleep(nanoseconds: holdNs)
        guard myGeneration == generation else { throw CancellationError() }

        await onEvent(ChatSSEParser.Event(type: "token", payload: [
            "type": "token",
            "content": "Réponse UITest déterministe. ",
        ]))
        if scenario == "handoff" {
            await onEvent(ChatSSEParser.Event(type: "mail_handoff", payload: [
                "type": "mail_handoff",
                "threadId": "uitest-thread-free",
                "query": "facture Free",
                "label": "Votre facture Free du mois",
                "reason": "Ouvrir le fil Free",
            ] as [String: Any]))
            try await Task.sleep(nanoseconds: 400_000_000)
            guard myGeneration == generation else { throw CancellationError() }
            await onEvent(ChatSSEParser.Event(type: "files_handoff", payload: [
                "type": "files_handoff",
                "rootId": "uitest-root-documents",
                "query": "notes.txt",
                "reason": "Ouvrir Documents",
            ] as [String: Any]))
            try await Task.sleep(nanoseconds: 600_000_000)
            guard myGeneration == generation else { throw CancellationError() }
        }
        await onEvent(ChatSSEParser.Event(type: "done", payload: ["type": "done"]))
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
