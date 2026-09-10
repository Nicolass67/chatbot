import Foundation

/// Couche réseau web — recherche et lecture de page.
///
/// Volontairement hors `@MainActor` (les outils `AITool` le sont) : décoder et
/// nettoyer 1 Mo de HTML sur le thread d'UI fige le défilement du chat pendant
/// la recherche. Ici tout le travail lourd se fait sur un thread de fond, et
/// les pages sont lues **en parallèle** au lieu d'une par une.
enum WebNetwork {
    struct Page: Sendable, Equatable {
        var text: String
        var title: String?
        var truncated: Bool
        var fromCache: Bool
    }

    enum FetchError: Error, Equatable {
        case badStatus(Int)
        case unsupportedContentType(String)
        case empty
    }

    /// Session dédiée : pas de cookies (les murs de consentement en posent à
    /// chaque appel), cache HTTP mémoire modeste, et pas d'attente réseau infinie.
    nonisolated(unsafe) static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .reloadRevalidatingCacheData
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 32 << 20)
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    // MARK: - Recherche

    /// Interroge plusieurs points d'entrée **en parallèle** et fusionne les
    /// classements (Reciprocal Rank Fusion).
    ///
    /// L'ancien code n'essayait le point d'entrée suivant que si le précédent
    /// renvoyait zéro résultat : un HTML DuckDuckGo qui rend deux liens de
    /// mauvaise qualité coupait l'accès aux autres. La fusion prend le meilleur
    /// des trois et fait remonter les URLs vues par plusieurs sources.
    static func search(
        queries: [String],
        limit: Int,
        snippetBudget: Int
    ) async -> [SearchSourceDTO] {
        let wanted = max(1, limit)
        let cleaned = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [] }

        var ranked: [[SearchSourceDTO]] = []
        for (index, query) in cleaned.enumerated() {
            if let cached = await WebRetrievalCache.shared.sources(for: query) {
                ranked.append(cached)
                continue
            }
            // La requête principale mérite les trois points d'entrée ; les
            // variantes ne servent qu'au rappel, un seul suffit.
            let providers: [Provider] = index == 0 ? [.html, .lite, .instant] : [.html]
            let lists = await withTaskGroup(of: [SearchSourceDTO].self) { group -> [[SearchSourceDTO]] in
                for provider in providers {
                    group.addTask {
                        await provider.run(query: query, limit: wanted * 2, snippetBudget: snippetBudget)
                    }
                }
                var out: [[SearchSourceDTO]] = []
                for await list in group where !list.isEmpty {
                    out.append(list)
                }
                return out
            }
            let fused = fuse(lists, limit: wanted * 2)
            if !fused.isEmpty {
                await WebRetrievalCache.shared.store(sources: fused, for: query)
                ranked.append(fused)
            }
        }
        return fuse(ranked, limit: wanted)
    }

    /// Reciprocal Rank Fusion — `1 / (k + rang)`, k = 60 (valeur de référence).
    /// Robuste sans calibration : une URL bien classée par deux listes passe
    /// devant une URL première d'une seule liste.
    static func fuse(_ lists: [[SearchSourceDTO]], limit: Int) -> [SearchSourceDTO] {
        guard !lists.isEmpty else { return [] }
        let k = 60.0
        var scores: [String: Double] = [:]
        var best: [String: SearchSourceDTO] = [:]
        var order: [String] = []

        for list in lists {
            for (rank, source) in list.enumerated() {
                let key = normalizedURLKey(source.url)
                guard !key.isEmpty else { continue }
                scores[key, default: 0] += 1.0 / (k + Double(rank + 1))
                if let existing = best[key] {
                    // Garder la variante la plus informative (snippet le plus long).
                    let existingLength = existing.snippet?.count ?? 0
                    let candidateLength = source.snippet?.count ?? 0
                    if candidateLength > existingLength { best[key] = source }
                } else {
                    best[key] = source
                    order.append(key)
                }
            }
        }

        // Ordre de première apparition, pour départager à score égal sans
        // rechercher dans le tableau à chaque comparaison.
        var firstSeen: [String: Int] = [:]
        for (index, key) in order.enumerated() { firstSeen[key] = index }
        let sorted = order.sorted { lhs, rhs in
            let a = scores[lhs] ?? 0
            let b = scores[rhs] ?? 0
            if a == b { return (firstSeen[lhs] ?? 0) < (firstSeen[rhs] ?? 0) }
            return a > b
        }
        return reindex(sorted.compactMap { best[$0] }, limit: limit)
    }

    static func normalizedURLKey(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]) }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func reindex(_ sources: [SearchSourceDTO], limit: Int) -> [SearchSourceDTO] {
        var seen = Set<String>()
        var out: [SearchSourceDTO] = []
        for source in sources {
            let key = normalizedURLKey(source.url)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append(
                SearchSourceDTO(
                    id: "web_\(out.count + 1)",
                    title: source.title,
                    url: source.url,
                    domain: source.domain ?? WebURLNormalizer.domain(from: source.url),
                    snippet: source.snippet
                )
            )
            if out.count >= max(1, limit) { break }
        }
        return out
    }

    // MARK: - Points d'entrée

    enum Provider: Sendable {
        case html
        case lite
        case instant

        func run(query: String, limit: Int, snippetBudget: Int) async -> [SearchSourceDTO] {
            switch self {
            case .html:
                return await WebNetwork.duckDuckGoHTML(query: query, limit: limit, snippetBudget: snippetBudget)
            case .lite:
                return await WebNetwork.duckDuckGoLite(query: query, limit: limit, snippetBudget: snippetBudget)
            case .instant:
                return await WebNetwork.duckDuckGoInstant(query: query, limit: limit, snippetBudget: snippetBudget)
            }
        }
    }

    private static func duckDuckGoHTML(query: String, limit: Int, snippetBudget: Int) async -> [SearchSourceDTO] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return [] }
        guard let html = await text(from: url, userAgent: browserUserAgent, timeout: 15) else { return [] }
        return WebSERPParser.duckDuckGoHTML(html, limit: limit, snippetBudget: snippetBudget)
    }

    private static func duckDuckGoLite(query: String, limit: Int, snippetBudget: Int) async -> [SearchSourceDTO] {
        var components = URLComponents(string: "https://lite.duckduckgo.com/lite/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return [] }
        guard let html = await text(from: url, userAgent: browserUserAgent, timeout: 12) else { return [] }
        return WebSERPParser.duckDuckGoLite(html, limit: limit, snippetBudget: snippetBudget)
    }

    private static func duckDuckGoInstant(query: String, limit: Int, snippetBudget: Int) async -> [SearchSourceDTO] {
        var components = URLComponents(string: "https://api.duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let url = components?.url else { return [] }
        guard let json = await text(from: url, userAgent: "ChatbotNative/3.0 (local-web)", timeout: 12),
              let data = json.data(using: .utf8) else { return [] }
        return WebSERPParser.duckDuckGoInstant(data, limit: limit, snippetBudget: snippetBudget)
    }

    // MARK: - Lecture de page

    static func fetchPage(
        url: URL,
        maxChars: Int,
        timeout: TimeInterval = 15
    ) async throws -> Page {
        if let cached = await WebRetrievalCache.shared.page(for: url.absoluteString) {
            let clipped = String(cached.text.prefix(max(200, maxChars)))
            return Page(
                text: clipped,
                title: cached.title,
                truncated: cached.text.count > clipped.count,
                fromCache: true
            )
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,text/plain;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("fr-FR,fr;q=0.9,en;q=0.6", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await requestWithRetry(request)
        if let http = response as? HTTPURLResponse {
            guard (200...299).contains(http.statusCode) else {
                throw FetchError.badStatus(http.statusCode)
            }
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            // Un PDF ou une image passés dans un extracteur HTML produisent du
            // charabia qui pollue les extraits sans jamais être détecté.
            if !contentType.isEmpty,
               !contentType.contains("html"),
               !contentType.contains("text/plain"),
               !contentType.contains("xml") {
                throw FetchError.unsupportedContentType(contentType)
            }
        }
        guard data.count <= 4_000_000 else { throw FetchError.unsupportedContentType("payload trop volumineux") }

        let html = HTMLReadability.decode(data, textEncodingName: response.textEncodingName)
        let title = HTMLReadability.title(from: html)
        let text = HTMLReadability.mainText(from: html)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FetchError.empty
        }
        await WebRetrievalCache.shared.store(page: text, title: title, for: url.absoluteString)

        let clipped = String(text.prefix(max(200, maxChars)))
        return Page(text: clipped, title: title, truncated: text.count > clipped.count, fromCache: false)
    }

    /// Une seule reprise, sur erreur transport uniquement : un 404 ne devient
    /// pas un 200 au second essai, mais un réseau mobile qui bascule 5G/Wi-Fi si.
    private static func requestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where Self.retryableCodes.contains(error.code) {
            try await Task.sleep(nanoseconds: 400_000_000)
            return try await session.data(for: request)
        }
    }

    private static let retryableCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost,
        .dnsLookupFailed, .notConnectedToInternet,
    ]

    private static func text(from url: URL, userAgent: String, timeout: TimeInterval) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("fr-FR,fr;q=0.9,en;q=0.6", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await requestWithRetry(request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil
        }
        return HTMLReadability.decode(data, textEncodingName: response.textEncodingName)
    }
}

/// Parsing des pages de résultats — séparé du réseau pour rester testable.
enum WebSERPParser {
    static func duckDuckGoHTML(_ html: String, limit: Int, snippetBudget: Int) -> [SearchSourceDTO] {
        var hits: [SearchSourceDTO] = []
        let pattern = #"class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        let snippetRegex = try? NSRegularExpression(
            pattern: #"class="result__snippet"[^>]*>(.*?)</(?:a|td|span|div)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let snippetMatches = snippetRegex?.matches(in: html, options: [], range: range) ?? []
        for (idx, match) in matches.prefix(max(1, limit)).enumerated() {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let href = WebURLNormalizer.unwrapDuckDuckGoRedirect(String(html[urlRange]))
            guard href.hasPrefix("http") else { continue }
            let title = clean(String(html[titleRange]))
            if title.isEmpty { continue }
            var snippet: String?
            if idx < snippetMatches.count, let sr = Range(snippetMatches[idx].range(at: 1), in: html) {
                snippet = String(clean(String(html[sr])).prefix(snippetBudget))
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
        return WebNetwork.reindex(hits, limit: limit)
    }

    static func duckDuckGoLite(_ html: String, limit: Int, snippetBudget: Int) -> [SearchSourceDTO] {
        var hits: [SearchSourceDTO] = []
        let pattern = #"rel="nofollow"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, options: [], range: range) {
            if hits.count >= max(1, limit) { break }
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let href = WebURLNormalizer.unwrapDuckDuckGoRedirect(String(html[urlRange]))
            guard href.hasPrefix("http"), !href.contains("duckduckgo.com") else { continue }
            let title = clean(String(html[titleRange]))
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
        return WebNetwork.reindex(hits, limit: limit)
    }

    static func duckDuckGoInstant(_ data: Data, limit: Int, snippetBudget: Int) -> [SearchSourceDTO] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
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
        return WebNetwork.reindex(hits, limit: limit)
    }

    private static func appendRelated(
        _ related: [Any],
        into hits: inout [SearchSourceDTO],
        limit: Int,
        snippetBudget: Int
    ) {
        for item in related {
            if hits.count >= max(1, limit) { return }
            guard let dict = item as? [String: Any] else { continue }
            if let text = dict["Text"] as? String, let firstURL = dict["FirstURL"] as? String {
                hits.append(
                    SearchSourceDTO(
                        id: "web_\(hits.count + 1)",
                        title: String(text.prefix(80)),
                        url: firstURL,
                        domain: WebURLNormalizer.domain(from: firstURL),
                        snippet: String(text.prefix(snippetBudget))
                    )
                )
            } else if let topics = dict["Topics"] as? [Any] {
                appendRelated(topics, into: &hits, limit: limit, snippetBudget: snippetBudget)
            }
        }
    }

    static func clean(_ html: String) -> String {
        HTMLReadability.collapseWhitespace(
            HTMLReadability.decodeEntities(
                html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            )
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
