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
            try await streamUITestFixture(
                mode: options.mode,
                myGeneration: myGeneration,
                onEvent: onEvent
            )
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

    /// Fixtures SSE : thinking visible assez longtemps pour screenshot ; agent timeline ; Stop via cancel().
    private func streamUITestFixture(
        mode: String,
        myGeneration: UInt64,
        onEvent: @escaping @Sendable (ChatSSEParser.Event) -> Void
    ) async throws {
        let scenario = UITestMode.sseScenario
        let useAgent = mode == "agent" || scenario == "agent" || scenario == "agent-error"

        if useAgent {
            onEvent(ChatSSEParser.Event(type: "agent_start", payload: ["type": "agent_start"]))
            try await Task.sleep(nanoseconds: 120_000_000)
            guard myGeneration == generation else { return }

            onEvent(ChatSSEParser.Event(type: "agent_plan", payload: [
                "type": "agent_plan",
                "plan": [
                    "steps": [
                        ["id": "1", "title": "Analyser la demande"],
                        ["id": "2", "title": "Préparer la réponse"],
                    ],
                ],
            ] as [String: Any]))
            try await Task.sleep(nanoseconds: 200_000_000)
            guard myGeneration == generation else { return }

            onEvent(ChatSSEParser.Event(type: "agent_step", payload: [
                "type": "agent_step",
                "stepId": "1",
                "stepIndex": 0,
                "totalSteps": 2,
                "status": "running",
                "message": "Analyser la demande",
            ]))
            // Hold agent strip visible for XCUITest screenshot / Stop tap.
            try await Task.sleep(nanoseconds: 1_200_000_000)
            guard myGeneration == generation else { return }

            if scenario == "agent-error" {
                onEvent(ChatSSEParser.Event(type: "agent_step", payload: [
                    "type": "agent_step",
                    "stepId": "1",
                    "status": "error",
                    "message": "Permission denied accessing file",
                ]))
                try await Task.sleep(nanoseconds: 400_000_000)
                guard myGeneration == generation else { return }
                onEvent(ChatSSEParser.Event(type: "done", payload: ["type": "done"]))
                return
            }

            onEvent(ChatSSEParser.Event(type: "agent_step", payload: [
                "type": "agent_step",
                "stepId": "1",
                "status": "done",
            ]))
            onEvent(ChatSSEParser.Event(type: "agent_step", payload: [
                "type": "agent_step",
                "stepId": "2",
                "stepIndex": 1,
                "totalSteps": 2,
                "status": "running",
                "message": "Préparer la réponse",
            ]))
            try await Task.sleep(nanoseconds: 200_000_000)
            guard myGeneration == generation else { return }

            onEvent(ChatSSEParser.Event(type: "token", payload: [
                "type": "token",
                "content": "Réponse Agent UITest. ",
            ]))
            onEvent(ChatSSEParser.Event(type: "agent_done", payload: ["type": "agent_done"]))
            onEvent(ChatSSEParser.Event(type: "done", payload: ["type": "done"]))
            return
        }

        // Chat / thinking : status visible avant le premier token.
        onEvent(ChatSSEParser.Event(type: "thinking", payload: [
            "type": "thinking",
            "message": "Réflexion…",
        ]))
        let holdNs: UInt64 = (scenario == "thinking" || scenario == "chat") ? 1_600_000_000 : 400_000_000
        try await Task.sleep(nanoseconds: holdNs)
        guard myGeneration == generation else { return }

        onEvent(ChatSSEParser.Event(type: "token", payload: [
            "type": "token",
            "content": "Réponse UITest déterministe. ",
        ]))
        onEvent(ChatSSEParser.Event(type: "done", payload: ["type": "done"]))
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
