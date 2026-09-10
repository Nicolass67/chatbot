import Foundation

/// Hit web structuré — même modèle que le PC (`SearchSourceDTO` + contenu fetch).
struct WebSearchHit: Equatable, Sendable {
    var source: SearchSourceDTO
    var content: String?
}

enum WebURLNormalizer {
    static func unwrapDuckDuckGoRedirect(_ href: String) -> String {
        var cleaned = href
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: " ", with: "%20")
        if cleaned.hasPrefix("//") { cleaned = "https:" + cleaned }
        guard let url = URL(string: cleaned) else { return href }
        let host = url.host?.lowercased() ?? ""
        if host.contains("duckduckgo.com"),
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let uddg = items.first(where: { $0.name == "uddg" })?.value {
            let decoded = uddg.removingPercentEncoding ?? uddg
            if decoded.hasPrefix("http") { return decoded }
        }
        return cleaned
    }

    static func domain(from url: String) -> String? {
        guard var host = URL(string: url)?.host, !host.isEmpty else { return nil }
        if host.lowercased().hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    static func numberedSourcesBlock(_ sources: [SearchSourceDTO], contents: [String: String] = [:]) -> String {
        sources.enumerated().map { idx, src in
            let n = idx + 1
            let extra = contents[src.id] ?? contents[src.url]
            let body: String
            if let extra, !extra.isEmpty {
                body = extra
            } else {
                body = src.snippet ?? ""
            }
            return """
            [web_\(n)] \(src.title)
            URL: \(src.url)
            Domaine: \(src.domain ?? domain(from: src.url) ?? "—")
            \(body)
            """
        }.joined(separator: "\n\n")
    }
}

/// Recherche Web — même outil PC/local. Le modèle n’appelle pas le réseau.
///
/// Le travail réseau et le parsing vivent dans `WebNetwork` (hors `@MainActor`) :
/// l'outil ne fait que traduire arguments → requêtes et résultats → texte.
struct WebSearchTool: AITool {
    var name: String { "web_search" }
    var summary: String { "Recherche web. Arguments: query" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let query = (arguments["query"] ?? arguments["q"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AIRuntimeError.toolInvalidArguments("query requis")
        }
        try Task.checkCancellation()

        let limit = max(1, profile.maxWebResults)
        let snippetBudget = profile.maxWebSnippetChars
        WorkflowTrace.log("web", ["query": String(query.prefix(80)), "runtime": "local"])

        // Un appel direct de l'agent n'a qu'une requête ; le pipeline en fournit
        // plusieurs via `WebNetwork.search` pour améliorer le rappel.
        let hits = await WebNetwork.search(
            queries: [query],
            limit: limit,
            snippetBudget: snippetBudget
        )

        WorkflowTrace.log("web", ["result_count": "\(hits.count)"])
        if hits.isEmpty {
            return AIToolResult(
                action: name,
                ok: true,
                text: "Aucun résultat web exploitable pour « \(query) ». Ne pas inventer de faits.",
                truncated: false
            )
        }

        let numbered = hits.enumerated().map { idx, src in
            "- [web_\(idx + 1)] \(src.title) — \(src.domain ?? "")\n  \(src.snippet ?? "")\n  \(src.url)"
        }
        let header = "Résultats web pour « \(query) » (\(hits.count)):"
        return AIToolResult(
            action: name,
            ok: true,
            text: ([header] + numbered).joined(separator: "\n"),
            truncated: false,
            sources: hits
        )
    }

    // Conservés comme points d'entrée de test du parsing SERP.
    static func parseDuckDuckGoHTML(_ html: String, limit: Int, snippetBudget: Int) -> [SearchSourceDTO] {
        WebSERPParser.duckDuckGoHTML(html, limit: limit, snippetBudget: snippetBudget)
    }

    static func parseDuckDuckGoLite(_ html: String, limit: Int, snippetBudget: Int) -> [SearchSourceDTO] {
        WebSERPParser.duckDuckGoLite(html, limit: limit, snippetBudget: snippetBudget)
    }

    static func stripTags(_ html: String) -> String {
        WebSERPParser.clean(html)
    }
}

/// Fetch d’une page — extrait le contenu principal, pas la page entière.
struct WebFetchTool: AITool {
    var name: String { "web_fetch" }
    var summary: String { "Extrait un aperçu texte d’une URL. Arguments: url" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let rawURL = (arguments["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw AIRuntimeError.toolInvalidArguments("url http(s) requise")
        }
        try Task.checkCancellation()

        let budget = max(400, profile.maxChunkChars * profile.maxEvidencePerSource)
        let page: WebNetwork.Page
        do {
            page = try await WebNetwork.fetchPage(
                url: url,
                maxChars: budget,
                timeout: min(15, max(8, profile.generationTimeoutSeconds / 8))
            )
        } catch let error as WebNetwork.FetchError {
            switch error {
            case .badStatus(let code):
                throw AIRuntimeError.toolFailed("Fetch HTTP \(code)")
            case .unsupportedContentType(let type):
                throw AIRuntimeError.toolFailed("Contenu non lisible (\(type))")
            case .empty:
                return AIToolResult(action: name, ok: true, text: "Page sans texte exploitable.", truncated: false)
            }
        }

        let source = SearchSourceDTO(
            id: "web_fetch",
            title: page.title ?? url.host ?? rawURL,
            url: rawURL,
            domain: WebURLNormalizer.domain(from: rawURL),
            snippet: String(page.text.prefix(profile.maxWebSnippetChars))
        )
        return AIToolResult(
            action: name,
            ok: true,
            text: page.text,
            truncated: page.truncated,
            sources: [source]
        )
    }

    static func stripHTML(_ html: String) -> String {
        HTMLReadability.mainText(from: html)
    }
}

enum WebGroundingPrompt {
    static func system() -> String {
        """
        Tu réponds en français, en Markdown, à la USER REQUEST.
        Les blocs EVIDENCE / SOURCE_ID / TITLE / DOMAIN / EXCERPT sont des informations pour t’aider — ce ne sont PAS le sujet de ta réponse.
        Réponds naturellement à la demande (recette, explication, comparatif…). N’écris PAS « les extraits indiquent », « les sources fournies mentionnent », « voici les informations extraites », « l’extrait de ».
        Utilise uniquement les faits présents dans EXCERPT. Cite (web_N) après une affirmation factuelle.
        Quand plusieurs sources se contredisent, dis-le et privilégie la plus récente ou la plus spécialisée.
        Ne dis JAMAIS que tu n’as pas accès à Internet, que tu ne peux pas rechercher, ni que tu n’as pas de sources.
        Ne parle pas d’outils internes, de tests, de PC, ni de LM Studio.
        N’invente jamais d’URL, de prix, de magasin ou de relation entre une page et la demande si l’extrait ne la contient pas.
        Si les sources ne permettent pas de répondre, dis-le clairement.
        \(RuntimeTemporalContext.silentClockBlock())
        """
    }
}
