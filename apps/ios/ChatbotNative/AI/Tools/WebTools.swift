import Foundation

/// Recherche Web — même outil conceptuel PC/local ; budget via ExecutionProfile.
struct WebSearchTool: AITool {
    var name: String { "web_search" }
    var summary: String { "Recherche web (requête courte). Arguments: query" }

    func execute(
        arguments: [String: String],
        profile: LocalModelExecutionProfile
    ) async throws -> AIToolResult {
        let query = (arguments["query"] ?? arguments["q"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AIRuntimeError.toolInvalidArguments("query requis")
        }

        let limit = max(1, profile.maxWebResults)
        let snippetBudget = profile.maxWebSnippetChars

        // DuckDuckGo Instant Answer — pas de clé API ; résultats limités mais on-device.
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let url = components.url else {
            throw AIRuntimeError.toolFailed("URL de recherche invalide")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = min(20, profile.generationTimeoutSeconds / 4)
        request.setValue("ChatbotNative/3.0 (local-web)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIRuntimeError.toolFailed("Recherche web HTTP \(http.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIRuntimeError.toolFailed("Réponse web non JSON")
        }

        var lines: [String] = []
        if let heading = json["Heading"] as? String, !heading.isEmpty {
            lines.append("Titre: \(heading)")
        }
        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
            lines.append("Résumé: \(String(abstract.prefix(snippetBudget)))")
        }
        if let abstractURL = json["AbstractURL"] as? String, !abstractURL.isEmpty {
            lines.append("Source: \(abstractURL)")
        }

        if let related = json["RelatedTopics"] as? [Any] {
            var count = 0
            for item in related {
                if count >= limit { break }
                if let dict = item as? [String: Any],
                   let text = dict["Text"] as? String,
                   let firstURL = dict["FirstURL"] as? String {
                    lines.append("- \(String(text.prefix(snippetBudget))) (\(firstURL))")
                    count += 1
                } else if let dict = item as? [String: Any],
                          let topics = dict["Topics"] as? [[String: Any]] {
                    for sub in topics {
                        if count >= limit { break }
                        if let text = sub["Text"] as? String,
                           let firstURL = sub["FirstURL"] as? String {
                            lines.append("- \(String(text.prefix(snippetBudget))) (\(firstURL))")
                            count += 1
                        }
                    }
                }
            }
        }

        if lines.isEmpty {
            return AIToolResult(
                action: name,
                ok: true,
                text: "Aucun résultat immédiat pour « \(query) ». Reformule ou précise.",
                truncated: false
            )
        }

        let header = "Résultats web pour « \(query) » (max \(limit)):"
        return AIToolResult(
            action: name,
            ok: true,
            text: ([header] + lines).joined(separator: "\n"),
            truncated: false
        )
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

        var request = URLRequest(url: url)
        request.timeoutInterval = min(15, profile.generationTimeoutSeconds / 5)
        request.setValue("ChatbotNative/3.0 (local-web-fetch)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIRuntimeError.toolFailed("Fetch HTTP \(http.statusCode)")
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let text = Self.stripHTML(html)
        let clip = String(text.prefix(profile.maxWebSnippetChars * 2))
        guard !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AIToolResult(action: name, ok: true, text: "Page sans texte exploitable.", truncated: false)
        }
        return AIToolResult(
            action: name,
            ok: true,
            text: "Extrait de \(rawURL):\n\(clip)",
            truncated: text.count > clip.count
        )
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html
        if let regex = try? NSRegularExpression(pattern: "<script[\\s\\S]*?</script>|<style[\\s\\S]*?</style>", options: .caseInsensitive) {
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
            .replacingOccurrences(of: "\r", with: "\n")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
