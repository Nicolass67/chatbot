import Foundation

/// Extrait compact envoyé au modèle — les `SearchSourceDTO` restent la provenance UI.
struct WebEvidence: Equatable, Sendable {
    var sourceId: String
    var title: String
    var domain: String
    var url: String
    var excerpt: String
}

struct WebEvidencePacket: Equatable, Sendable {
    var query: String
    var sources: [SearchSourceDTO]
    var evidence: [WebEvidence]
    var promptBlock: String
}

/// SEARCH → RANK → SELECT → CHUNK → COMPRESS (déterministe, un seul modèle).
enum WebEvidenceBuilder {
    static func rank(_ sources: [SearchSourceDTO], query: String) -> [SearchSourceDTO] {
        let terms = tokens(query)
        return sources.sorted { a, b in
            score(a, terms: terms) > score(b, terms: terms)
        }
    }

    static func build(
        query: String,
        sources: [SearchSourceDTO],
        pageTexts: [String: String],
        profile: LocalModelExecutionProfile
    ) -> WebEvidencePacket {
        let ranked = rank(sources, query: query)
        let selected = Array(ranked.prefix(max(1, profile.maxWebResults)))
        let perSource = max(1, profile.maxEvidencePerSource)
        let excerptCap = max(120, profile.maxWebSnippetChars)
        let terms = tokens(query)
        var evidence: [WebEvidence] = []
        for src in selected {
            let raw = pageTexts[src.id] ?? pageTexts[src.url] ?? src.snippet ?? ""
            let chunks = chunk(raw, maxChars: max(160, profile.maxChunkChars))
            let picked = chunks
                .map { (text: $0, score: lexicalScore($0, terms: terms)) }
                .sorted { $0.score > $1.score }
                .prefix(perSource)
                .map(\.text)
            let excerpt: String
            if picked.isEmpty {
                excerpt = String((src.snippet ?? "").prefix(excerptCap))
            } else {
                excerpt = String(picked.joined(separator: "\n").prefix(excerptCap * perSource))
            }
            evidence.append(
                WebEvidence(
                    sourceId: src.id,
                    title: src.title,
                    domain: src.domain ?? WebURLNormalizer.domain(from: src.url) ?? "",
                    url: src.url,
                    excerpt: excerpt
                )
            )
        }

        var block = """
        WebSearchTool a été exécuté avec succès.
        Extraite uniquement les passages ci-dessous. Cite (web_N). N’invente rien.
        Question: \(query)
        """
        for (idx, item) in evidence.enumerated() {
            let n = idx + 1
            block += """


            [web_\(n)] \(item.title)
            Domaine: \(item.domain)
            \(item.excerpt)
            """
        }
        if evidence.isEmpty {
            block += "\n\nAucun extrait exploitable. Ne pas inventer de faits."
        }
        block = GenerationContextBudget.clip(block, maxChars: max(400, profile.toolResultCharBudget))
        return WebEvidencePacket(
            query: query,
            sources: reindex(selected),
            evidence: evidence,
            promptBlock: block
        )
    }

    static func reindex(_ sources: [SearchSourceDTO]) -> [SearchSourceDTO] {
        sources.enumerated().map { idx, src in
            SearchSourceDTO(
                id: "web_\(idx + 1)",
                title: src.title,
                url: src.url,
                domain: src.domain ?? WebURLNormalizer.domain(from: src.url),
                snippet: src.snippet
            )
        }
    }

    static func chunk(_ text: String, maxChars: Int) -> [String] {
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        if cleaned.count <= maxChars { return [cleaned] }
        var out: [String] = []
        var start = cleaned.startIndex
        while start < cleaned.endIndex {
            let end = cleaned.index(start, offsetBy: maxChars, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            out.append(String(cleaned[start..<end]))
            if end == cleaned.endIndex { break }
            start = cleaned.index(end, offsetBy: -min(40, maxChars / 8), limitedBy: cleaned.startIndex) ?? end
        }
        return out
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    private static func score(_ source: SearchSourceDTO, terms: [String]) -> Int {
        lexicalScore(
            [source.title, source.domain ?? "", source.snippet ?? ""].joined(separator: " "),
            terms: terms
        )
    }

    private static func lexicalScore(_ text: String, terms: [String]) -> Int {
        guard !terms.isEmpty else { return 0 }
        let lower = text.lowercased()
        return terms.reduce(0) { acc, term in acc + (lower.contains(term) ? 1 : 0) }
    }
}

/// Orchestration search + fetch borné — commune Chat / Agent.
enum WebEvidencePipeline {
    @MainActor
    static func gather(
        query: String,
        tools: AIToolRegistry,
        profile: LocalModelExecutionProfile,
        onEvent: ((AgentOrchestrationEvent) -> Void)?
    ) async throws -> WebEvidencePacket {
        let q = AgentWorkflow.compactWebQuery(query)
        WorkflowTrace.log("web", ["query": String(q.prefix(80)), "phase": "search"])
        onEvent?(.webSearch(query: q))
        onEvent?(.toolStarted(tool: "web_search", query: q))

        let search = try await tools.execute(
            AIToolCall(action: "web_search", arguments: ["query": q]),
            profile: profile
        )
        let ranked = WebEvidenceBuilder.rank(search.sources, query: q)
        if !ranked.isEmpty {
            onEvent?(.sources(ranked))
        }
        onEvent?(.toolCompleted(tool: "web_search", sourceCount: ranked.count))

        var pageTexts: [String: String] = [:]
        let fetchCount = min(profile.maxFetchedPages, ranked.count)
        for (idx, source) in ranked.prefix(fetchCount).enumerated() {
            try Task.checkCancellation()
            onEvent?(.sourceOpened(source: source, index: idx + 1, total: fetchCount))
            do {
                let fetched = try await tools.execute(
                    AIToolCall(action: "web_fetch", arguments: ["url": source.url]),
                    profile: profile
                )
                let clipped = String(fetched.text.prefix(profile.maxChunkChars * profile.maxEvidencePerSource))
                pageTexts[source.id] = clipped
                WorkflowTrace.log("web", [
                    "source": source.domain ?? source.url,
                    "chars": "\(clipped.count)",
                ])
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        let packet = WebEvidenceBuilder.build(
            query: q,
            sources: ranked,
            pageTexts: pageTexts,
            profile: profile
        )
        WorkflowTrace.log("web", [
            "results": "\(search.sources.count)",
            "selected": "\(packet.sources.count)",
            "prompt_chars": "\(packet.promptBlock.count)",
        ])
        return packet
    }
}
