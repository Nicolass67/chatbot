import Foundation

/// Extraction du contenu principal d'une page HTML.
///
/// Un `<[^>]+>` → " " naïf laisse passer les menus, les bandeaux cookies, les
/// pieds de page et le JSON-LD : sur une page d'actualité, le texte utile
/// représente souvent moins de 20 % du résultat. Le modèle local n'a que
/// quelques milliers de caractères de budget, les gaspiller en navigation
/// revient à ne pas lire la page.
///
/// Volontairement `nonisolated` : ce travail (regex sur ~1 Mo) ne doit jamais
/// s'exécuter sur le thread d'UI.
enum HTMLReadability {
    /// Blocs sans valeur informative, retirés avec leur contenu.
    private static let droppedElements = [
        "script", "style", "noscript", "template", "svg", "canvas", "iframe",
        "form", "nav", "aside", "footer", "header", "figure", "select", "button",
    ]

    /// Balises dont la fermeture marque une rupture de ligne.
    private static let blockBoundaries = [
        "</p>", "</div>", "</li>", "</ul>", "</ol>", "</tr>", "</table>",
        "</section>", "</article>", "</blockquote>", "</pre>",
        "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>",
        "<br>", "<br/>", "<br />", "</br>",
    ]

    /// Décode les octets selon le charset déclaré, avec repli tolérant.
    /// Sans ça, une page ISO-8859-1 revient vide (`String(data:encoding:.utf8)` = nil)
    /// et la source est silencieusement perdue.
    static func decode(_ data: Data, textEncodingName: String?) -> String {
        if let name = textEncodingName {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let decoded = String(data: data, encoding: encoding) { return decoded }
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // Le charset peut n'être déclaré que dans le HTML lui-même.
        let probe = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        if probe.contains("charset=iso-8859-1") || probe.contains("charset=windows-1252") {
            if let latin = String(data: data, encoding: .windowsCP1252) { return latin }
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Titre déclaré par la page (`<title>`), nettoyé.
    static func title(from html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let raw = String(html[range])
        guard let open = raw.firstIndex(of: ">"),
              let close = raw.range(of: "</", options: .backwards) else { return nil }
        let inner = String(raw[raw.index(after: open)..<close.lowerBound])
        let cleaned = decodeEntities(collapseWhitespace(inner))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Texte principal de la page, débarrassé de la navigation.
    static func mainText(from html: String) -> String {
        var working = removeComments(html)
        working = removeElements(working)
        working = mainContentCandidate(working)
        working = markBlockBoundaries(working)
        working = stripTags(working)
        working = decodeEntities(working)
        working = collapseWhitespace(working)
        return dropBoilerplateLines(working)
    }

    // MARK: - Étapes

    private static func removeComments(_ html: String) -> String {
        replaceRegex(html, pattern: "<!--[\\s\\S]*?-->", with: " ")
    }

    private static func removeElements(_ html: String) -> String {
        var out = html
        for tag in droppedElements {
            out = replaceRegex(out, pattern: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: "\n")
            // Balise auto-fermante ou non refermée : au moins retirer l'ouverture.
            out = replaceRegex(out, pattern: "<\(tag)\\b[^>]*/?>", with: "\n")
        }
        return out
    }

    /// Préfère `<article>` puis `<main>` puis `<body>`, si le candidat est assez
    /// dense. Un `<article>` de 200 caractères est un teaser, pas l'article.
    private static func mainContentCandidate(_ html: String) -> String {
        for tag in ["article", "main"] {
            guard let opening = html.range(of: "<\(tag)\\b[^>]*>", options: [.regularExpression, .caseInsensitive]),
                  let closing = html.range(of: "</\(tag)>", options: [.regularExpression, .caseInsensitive, .backwards]),
                  opening.upperBound < closing.lowerBound else { continue }
            let candidate = String(html[opening.upperBound..<closing.lowerBound])
            if approximateTextLength(candidate) >= 400 { return candidate }
        }
        if let opening = html.range(of: "<body\\b[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            let closing = html.range(of: "</body>", options: [.regularExpression, .caseInsensitive, .backwards])
            let end = closing.map(\.lowerBound) ?? html.endIndex
            if opening.upperBound < end {
                return String(html[opening.upperBound..<end])
            }
        }
        return html
    }

    private static func markBlockBoundaries(_ html: String) -> String {
        var out = html
        for boundary in blockBoundaries {
            out = out.replacingOccurrences(of: boundary, with: "\n", options: .caseInsensitive)
        }
        return out
    }

    private static func stripTags(_ html: String) -> String {
        replaceRegex(html, pattern: "<[^>]+>", with: " ")
    }

    /// Estimation du texte utile sans matérialiser la chaîne strippée.
    private static func approximateTextLength(_ html: String) -> Int {
        var count = 0
        var inTag = false
        for char in html {
            if char == "<" { inTag = true; continue }
            if char == ">" { inTag = false; continue }
            if !inTag, !char.isWhitespace { count += 1 }
        }
        return count
    }

    // MARK: - Normalisation

    private static let namedEntities: [String: String] = [
        "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&apos;": "'", "&#39;": "'", "&#x27;": "'", "&#x2F;": "/", "&#47;": "/",
        "&hellip;": "…", "&mdash;": "—", "&ndash;": "–", "&laquo;": "«",
        "&raquo;": "»", "&eacute;": "é", "&egrave;": "è", "&ecirc;": "ê",
        "&agrave;": "à", "&ccedil;": "ç", "&ugrave;": "ù", "&ocirc;": "ô",
        "&icirc;": "î", "&euro;": "€", "&deg;": "°", "&times;": "×",
        "&rsquo;": "'", "&lsquo;": "'", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
    ]

    private static let numericEntityRegex = try? NSRegularExpression(
        pattern: "&#(x?)([0-9a-fA-F]+);",
        options: []
    )

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, replacement) in namedEntities {
            out = out.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        guard let regex = numericEntityRegex, out.contains("&#") else { return out }
        let range = NSRange(out.startIndex..<out.endIndex, in: out)
        var result = ""
        var last = out.startIndex
        for match in regex.matches(in: out, options: [], range: range) {
            guard let full = Range(match.range, in: out),
                  let flagRange = Range(match.range(at: 1), in: out),
                  let digitsRange = Range(match.range(at: 2), in: out) else { continue }
            let radix = out[flagRange].isEmpty ? 10 : 16
            guard let code = UInt32(out[digitsRange], radix: radix),
                  let scalar = Unicode.Scalar(code) else { continue }
            result += out[last..<full.lowerBound]
            result.append(Character(scalar))
            last = full.upperBound
        }
        result += out[last...]
        return result
    }

    /// Réduit les blancs en un seul passage.
    ///
    /// L'implémentation précédente bouclait sur `replacingOccurrences(of: "  ")`
    /// jusqu'à stabilisation : quadratique, et une page de 1 Mo bloquait le
    /// thread appelant plusieurs secondes.
    static func collapseWhitespace(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        var pendingNewlines = 0
        var pendingSpace = false
        var started = false

        for char in text {
            if char == "\n" || char == "\r" {
                pendingNewlines = min(2, pendingNewlines + 1)
                pendingSpace = false
                continue
            }
            if char.isWhitespace {
                pendingSpace = true
                continue
            }
            if started {
                if pendingNewlines > 0 {
                    out.append(String(repeating: "\n", count: pendingNewlines))
                } else if pendingSpace {
                    out.append(" ")
                }
            }
            pendingNewlines = 0
            pendingSpace = false
            started = true
            out.append(char)
        }
        return out
    }

    /// Retire les lignes de navigation résiduelles et les répétitions.
    private static func dropBoilerplateLines(_ text: String) -> String {
        var out: [String] = []
        var previous: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if previous != nil, out.last?.isEmpty == false { out.append("") }
                continue
            }
            let folded = line.lowercased()
            if consentPhrases.contains(where: { folded.contains($0) }), line.count < 200 { continue }
            // Une ligne d'un seul mot court est presque toujours un item de menu.
            if line.count < 3 { continue }
            if line == previous { continue }
            previous = line
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let consentPhrases = [
        "accepter les cookies", "gérer mes choix", "gerer mes choix",
        "politique de confidentialité", "politique de confidentialite",
        "accept all cookies", "manage preferences", "nous utilisons des cookies",
        "activez javascript", "enable javascript", "abonnez-vous à notre newsletter",
    ]

    private static func replaceRegex(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: template
        )
    }
}
