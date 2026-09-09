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

        var hits: [SearchSourceDTO] = []
        if let htmlHits = try? await htmlSearch(query: query, limit: limit, snippetBudget: snippetBudget) {
            hits = htmlHits
        }
        if hits.isEmpty, let instant = try? await instantAnswer(query: query, limit: limit, snippetBudget: snippetBudget) {
            hits = instant
        }
        if hits.isEmpty, let lite = try? await liteSearch(query: query, limit: limit, snippetBudget: snippetBudget) {
            hits = lite
        }

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

    private func instantAnswer(
        query: String,
        limit: Int,
        snippetBudget: Int
    ) async throws -> [SearchSourceDTO] {
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("ChatbotNative/3.0 (local-web)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var hits: [SearchSourceDTO] = []
        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty,
           let abstractURL = json["AbstractURL"] as? String, !abstractURL.isEmpty {
            hits.append(
                SearchSourceDTO(
                    id: "web_1",
                    title: (json["Heading"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? abstractURL,
                    url: abstractURL,
                    domain: WebURLNormalizer.domain(from: abstractURL),
                    snippet: String(abstract.prefix(snippetBudget))
                )
            )
        }
        if let related = json["RelatedTopics"] as? [Any] {
            appendRelated(related, into: &hits, limit: limit, snippetBudget: snippetBudget)
        }
        return Self.reindex(hits, limit: limit)
    }

    private func appendRelated(
        _ related: [Any],
        into hits: inout [SearchSourceDTO],
        limit: Int,
        snippetBudget: Int
    ) {
        for item in related {
            if hits.count >= limit { return }
            if let dict = item as? [String: Any],
               let text = dict["Text"] as? String,
               let firstURL = dict["FirstURL"] as? String {
                hits.append(
                    SearchSourceDTO(
                        id: "web_\(hits.count + 1)",
                        title: String(text.prefix(80)),
                        url: firstURL,
                        domain: WebURLNormalizer.domain(from: firstURL),
                        snippet: String(text.prefix(snippetBudget))
                    )
                )
            } else if let dict = item as? [String: Any], let topics = dict["Topics"] as? [Any] {
                appendRelated(topics, into: &hits, limit: limit, snippetBudget: snippetBudget)
            }
        }
    }

    private func htmlSearch(
        query: String,
        limit: Int,
        snippetBudget: Int
    ) async throws -> [SearchSourceDTO] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return []
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        return Self.parseDuckDuckGoHTML(html, limit: limit, snippetBudget: snippetBudget)
    }

    private func liteSearch(
        query: String,
        limit: Int,
        snippetBudget: Int
    ) async throws -> [SearchSourceDTO] {
        var components = URLComponents(string: "https://lite.duckduckgo.com/lite/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return []
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        return Self.parseDuckDuckGoLite(html, limit: limit, snippetBudget: snippetBudget)
    }

    static func parseDuckDuckGoHTML(_ html: String, limit: Int, snippetBudget: Int) -> [SearchSourceDTO] {
        var hits: [SearchSourceDTO] = []
        let pattern = #"class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        let snippetRegex = try? NSRegularExpression(
            pattern: #"class="result__snippet"[^>]*>(.*?)</(?:a|td|span)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let snippetMatches = snippetRegex?.matches(in: html, options: [], range: range) ?? []
        for (idx, match) in matches.prefix(limit).enumerated() {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let href = WebURLNormalizer.unwrapDuckDuckGoRedirect(String(html[urlRange]))
            guard href.hasPrefix("http") else { continue }
            let title = stripTags(String(html[titleRange]))
            if title.isEmpty { continue }
            var snippet: String?
            if idx < snippetMatches.count, let sr = Range(snippetMatches[idx].range(at: 1), in: html) {
                snippet = String(stripTags(String(html[sr])).prefix(snippetBudget))
            }
            hits.append(
                SearchSourceDTO(
                    id: "web_\(hits.count + 1)",
                    title: title,
                    url: href,
                    domain: WebURLNormalizer.domain(from: href),
                    snippet: snippet
                )
            )
        }
        return reindex(hits, limit: limit)
    }

    static func parseDuckDuckGoLite(_ html: String, limit: Int, snippetBudget: Int) -> [SearchSourceDTO] {
        var hits: [SearchSourceDTO] = []
        let pattern = #"rel="nofollow"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, options: [], range: range) {
            if hits.count >= limit { break }
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let href = WebURLNormalizer.unwrapDuckDuckGoRedirect(String(html[urlRange]))
            guard href.hasPrefix("http"), !href.contains("duckduckgo.com") else { continue }
            let title = stripTags(String(html[titleRange]))
            if title.count < 3 { continue }
            hits.append(
                SearchSourceDTO(
                    id: "web_\(hits.count + 1)",
                    title: String(title.prefix(120)),
                    url: href,
                    domain: WebURLNormalizer.domain(from: href),
                    snippet: String(title.prefix(snippetBudget))
                )
            )
        }
        return reindex(hits, limit: limit)
    }

    private static func reindex(_ hits: [SearchSourceDTO], limit: Int) -> [SearchSourceDTO] {
        var seen = Set<String>()
        var out: [SearchSourceDTO] = []
        for hit in hits {
            let key = hit.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(
                SearchSourceDTO(
                    id: "web_\(out.count + 1)",
                    title: hit.title,
                    url: hit.url,
                    domain: hit.domain ?? WebURLNormalizer.domain(from: hit.url),
                    snippet: hit.snippet
                )
            )
            if out.count >= limit { break }
        }
        return out
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Fetch d’une page — extrait texte court (pas la page entière).
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

        var request = URLRequest(url: url)
        request.timeoutInterval = min(12, profile.generationTimeoutSeconds / 5)
        request.setValue("ChatbotNative/3.0 (local-web-fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIRuntimeError.toolFailed("Fetch HTTP \(http.statusCode)")
        }
        if data.count > 1_500_000 {
            throw AIRuntimeError.toolFailed("Page trop volumineuse")
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let text = Self.stripHTML(html)
        let clip = String(text.prefix(profile.maxWebSnippetChars * 4))
        guard !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIToolResult(action: name, ok: true, text: "Page sans texte exploitable.", truncated: false)
        }
        let source = SearchSourceDTO(
            id: "web_fetch",
            title: url.host ?? rawURL,
            url: rawURL,
            domain: WebURLNormalizer.domain(from: rawURL),
            snippet: String(clip.prefix(profile.maxWebSnippetChars))
        )
        return AIToolResult(
            action: name,
            ok: true,
            text: "Extrait de \(rawURL):\n\(clip)",
            truncated: text.count > clip.count,
            sources: [source]
        )
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        if let regex = try? NSRegularExpression(
            pattern: "<script[\\s\\S]*?</script>|<style[\\s\\S]*?</style>|<nav[\\s\\S]*?</nav>",
            options: .caseInsensitive
        ) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text),
                withTemplate: " "
            )
        }
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text),
                withTemplate: " "
            )
        }
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "\r", with: "\n")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WebGroundingPrompt {
    static func system() -> String {
        """
        Tu rédiges une réponse en français, en Markdown.
        Tu n’as PAS d’accès Internet : utilise UNIQUEMENT les sources numérotées [web_N].
        Après chaque affirmation factuelle (prix, perf, date, disponibilité), cite (web_N).
        Si une info n’est pas dans les sources, dis clairement que les résultats ne permettent pas de la déterminer.
        N’invente jamais d’URL, de prix, de benchmark ni de nom de magasin absent des sources.
        Si les sources se contredisent, signale-le.
        """
    }
}
