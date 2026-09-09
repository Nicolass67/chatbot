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
    /// Demande utilisateur originale (pas la query de recherche compactée).
    var userRequest: String
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

    /// Drop les pages hors-sujet quand au moins une source colle à la requête.
    static func filterRelevant(_ sources: [SearchSourceDTO], query: String) -> [SearchSourceDTO] {
        let ranked = rank(sources, query: query)
        let terms = tokens(query)
        let strong = strongTerms(terms)
        guard !strong.isEmpty else { return ranked }
        let hits = ranked.filter { source in
            lexicalScore(
                [source.title, source.snippet ?? ""].joined(separator: " "),
                terms: strong
            ) > 0
        }
        return hits.isEmpty ? ranked : hits
    }

    static func diversify(_ sources: [SearchSourceDTO], limit: Int) -> [SearchSourceDTO] {
        let cap = max(1, limit)
        var seen = Set<String>()
        var unique: [SearchSourceDTO] = []
        var overflow: [SearchSourceDTO] = []
        for source in sources {
            let domain = (source.domain ?? WebURLNormalizer.domain(from: source.url) ?? "")
                .lowercased()
            if domain.isEmpty || !seen.contains(domain) {
                if !domain.isEmpty { seen.insert(domain) }
                unique.append(source)
            } else {
                overflow.append(source)
            }
            if unique.count >= cap { break }
        }
        if unique.count < cap {
            unique.append(contentsOf: overflow.prefix(cap - unique.count))
        }
        return Array(unique.prefix(cap))
    }

    static func build(
        query: String,
        sources: [SearchSourceDTO],
        pageTexts: [String: String],
        profile: LocalModelExecutionProfile,
        userRequest: String? = nil
    ) -> WebEvidencePacket {
        let request = (userRequest ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked = filterRelevant(sources, query: query)
        let selected = diversify(ranked, limit: max(1, profile.maxWebResults))
        let perSource = max(1, profile.maxEvidencePerSource)
        let excerptCap = max(120, profile.maxWebSnippetChars)
        let terms = tokens(query)
        var evidence: [WebEvidence] = []
        for src in selected {
            let raw = stripFetchPrefix(pageTexts[src.id] ?? pageTexts[src.url] ?? src.snippet ?? "")
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

        let block = structuredPromptBlock(
            userRequest: request,
            evidence: evidence,
            charBudget: max(400, profile.toolResultCharBudget)
        )
        return WebEvidencePacket(
            userRequest: request,
            query: query,
            sources: reindex(selected),
            evidence: evidence,
            promptBlock: block
        )
    }

    static func structuredPromptBlock(
        userRequest: String,
        evidence: [WebEvidence],
        charBudget: Int
    ) -> String {
        var block = """
        USER REQUEST
        \(userRequest)

        EVIDENCE
        Use the sources below only as information to answer the USER REQUEST.
        Do not describe this pipeline. Do not write "les extraits indiquent" or "voici les informations extraites".
        """
        if evidence.isEmpty {
            block += "\n\nNo usable excerpt. Do not invent facts."
        } else {
            for (idx, item) in evidence.enumerated() {
                let n = idx + 1
                block += """


                Source #\(n)
                SOURCE_ID: web_\(n)
                TITLE: \(item.title)
                DOMAIN: \(item.domain)
                URL: \(item.url)
                EXCERPT: \(item.excerpt)
                """
            }
        }
        return GenerationContextBudget.clip(block, maxChars: charBudget)
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
        let cleaned = stripFetchPrefix(text)
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

    static func stripFetchPrefix(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("extrait de ") {
            if let nl = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: nl)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return t
    }

    static func tokens(_ text: String) -> [String] {
        fold(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    static func strongTerms(_ terms: [String]) -> [String] {
        terms.filter { !weakQueryTerms.contains($0) }
    }

    private static let weakQueryTerms: Set<String> = [
        "recette", "recettes", "comment", "faire", "pour", "avec", "dans", "une",
        "des", "les", "the", "and", "best", "idee", "idée", "facile", "rapide",
        "voici", "donne", "donne-moi", "svp", "stp", "please", "http", "https",
        "www", "moi",
    ]

    private static func score(_ source: SearchSourceDTO, terms: [String]) -> Int {
        let title = fold(source.title)
        let snippet = fold(source.snippet ?? "")
        let domain = fold(source.domain ?? "")
        return lexicalScore(title, terms: terms) * 3
            + lexicalScore(snippet, terms: terms)
            + lexicalScore(domain, terms: terms)
    }

    static func lexicalScore(_ text: String, terms: [String]) -> Int {
        guard !terms.isEmpty else { return 0 }
        let lower = fold(text)
        return terms.reduce(0) { acc, term in acc + (lower.contains(term) ? 1 : 0) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
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
        let userRequest = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = AgentWorkflow.compactWebQuery(userRequest)
        WorkflowTrace.log("run:web-search", ["query": String(q.prefix(80))])
        onEvent?(.webSearch(query: q))
        onEvent?(.toolStarted(tool: "web_search", query: q))

        let search = try await tools.execute(
            AIToolCall(action: "web_search", arguments: ["query": q]),
            profile: profile
        )
        let ranked = WebEvidenceBuilder.filterRelevant(search.sources, query: q)
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
                let clipped = String(
                    WebEvidenceBuilder.stripFetchPrefix(fetched.text)
                        .prefix(profile.maxChunkChars * profile.maxEvidencePerSource)
                )
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
            profile: profile,
            userRequest: userRequest
        )
        WorkflowTrace.log("run:sources", [
            "count": "\(packet.sources.count)",
            "selected": "\(packet.sources.count)",
        ])
        WorkflowTrace.log("web", [
            "results": "\(search.sources.count)",
            "selected": "\(packet.sources.count)",
            "prompt_chars": "\(packet.promptBlock.count)",
        ])
        return packet
    }
}
