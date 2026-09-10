import Foundation

/// Requêtes envoyées au moteur de recherche, dérivées de la demande utilisateur.
///
/// La demande et la requête ne sont pas la même chose : le modèle doit répondre
/// à « tu peux me trouver la meilleure carte graphique pour du 1440p ? », mais
/// un SERP ne veut que « meilleure carte graphique 1440p 2026 ». Envoyer la
/// phrase brute fait remonter des forums de questions, pas des comparatifs.
struct WebQueryPlan: Equatable, Sendable {
    /// Demande utilisateur d'origine — c'est elle que le modèle doit satisfaire.
    var userRequest: String
    /// Question de retrieval (anaphores rattachées au contexte).
    var retrievalQuestion: String
    /// Requête principale : mots porteurs uniquement.
    var primary: String
    /// Requêtes de rappel, fusionnées avec la principale.
    var variants: [String]
    /// Termes discriminants — base du scoring lexical et du test de couverture.
    var strongTerms: [String]

    /// Requêtes uniques, principale d'abord.
    var allQueries: [String] {
        var out: [String] = []
        for query in [primary] + variants {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !out.contains(trimmed) else { continue }
            out.append(trimmed)
        }
        return out
    }
}

enum WebQueryPlanner {
    /// Nombre de mots porteurs conservés dans la requête principale.
    /// Au-delà, DuckDuckGo dégrade en recherche floue et perd les pages précises.
    static let maxKeywords = 12

    /// Mots vides FR/EN : ils ne discriminent rien et diluent le SERP.
    static let stopWords: Set<String> = [
        "le", "la", "les", "un", "une", "des", "du", "de", "d", "au", "aux",
        "ce", "cet", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes",
        "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs",
        "et", "ou", "mais", "donc", "or", "ni", "car", "que", "qui", "quoi",
        "dont", "ou\u{300}", "pour", "par", "avec", "sans", "sous", "sur", "dans",
        "chez", "vers", "entre", "depuis", "pendant", "avant", "apres", "après",
        "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "me",
        "te", "se", "moi", "toi", "lui", "eux", "y", "en",
        "est", "sont", "etre", "être", "avoir", "as", "ai", "ont", "avons",
        "peux", "peut", "pouvez", "pourrais", "veux", "veut", "voudrais",
        "dire", "dis", "donne", "donnes", "donner", "trouve", "trouver",
        "cherche", "chercher", "recherche", "rechercher", "explique", "expliquer",
        "montre", "montrer", "aide", "aider", "stp", "svp", "merci", "salut",
        "bonjour", "hello", "please", "thanks",
        "quel", "quelle", "quels", "quelles", "combien", "pourquoi", "comment",
        "quand", "est-ce", "estce", "ya", "there",
        "the", "a", "an", "of", "to", "for", "with", "and", "or", "is", "are",
        "what", "which", "how", "why", "when", "can", "could", "would", "you",
        "me", "my", "your", "please", "give", "find", "search", "show", "tell",
        "s", "n", "l", "c", "j", "t", "qu",
    ]

    /// Tournures d'ouverture sans contenu propre.
    private static let leadingNoise: [String] = [
        "recherche sur internet ", "recherche sur le web ", "cherche sur internet ",
        "cherche sur le web ", "fais une recherche sur ", "fais une recherche ",
        "peux-tu me trouver ", "peux tu me trouver ", "peux-tu chercher ",
        "peux tu chercher ", "tu peux chercher ", "tu peux me trouver ",
        "j'aimerais savoir ", "jaimerais savoir ", "je voudrais savoir ",
        "dis-moi ", "dis moi ", "donne-moi ", "donne moi ",
        "recherche ", "cherche ", "trouve ",
    ]

    /// Construit le plan de requêtes pour une demande.
    static func plan(
        userText: String,
        history: [LLMChatMessage] = [],
        now: Date = Date()
    ) -> WebQueryPlan {
        let request = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Une question de suivi (« et son prix ? ») ne contient pas son sujet :
        // sans réécriture, le SERP reçoit « prix » et renvoie n'importe quoi.
        let retrieval = QueryRewriter.retrievalQuery(userText: request, history: history)

        let terms = keywords(retrieval, limit: maxKeywords)
        let primaryBase = terms.isEmpty ? stripNoise(request) : terms.joined(separator: " ")
        let primary = RuntimeTemporalContext.groundWebQuery(primaryBase, now: now)

        var variants: [String] = []
        // La formulation naturelle reste utile : certains moteurs répondent mieux
        // à une question qu'à un sac de mots. On la garde en second, jamais seule.
        let natural = RuntimeTemporalContext.groundWebQuery(stripNoise(request), now: now)
        if natural.caseInsensitiveCompare(primary) != .orderedSame, natural.count <= 140 {
            variants.append(natural)
        }

        return WebQueryPlan(
            userRequest: request,
            retrievalQuestion: retrieval,
            primary: primary,
            variants: variants,
            strongTerms: terms
        )
    }

    /// Relance ciblée quand les extraits ne couvrent pas la demande.
    /// `nil` s'il ne reste rien de neuf à demander : mieux vaut répondre avec ce
    /// qu'on a que relancer la même requête et payer un aller-retour réseau.
    static func followUpQuery(
        plan: WebQueryPlan,
        uncovered: [String],
        now: Date = Date()
    ) -> String? {
        let missing = uncovered.filter { !$0.isEmpty }.prefix(3)
        guard !missing.isEmpty else { return nil }
        let base = missing.joined(separator: " ")
        // On réancre sur les deux termes les plus porteurs de la requête initiale
        // pour ne pas partir sur un sujet voisin.
        let anchor = plan.strongTerms.prefix(2).joined(separator: " ")
        let combined = [anchor, base]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else { return nil }
        let grounded = RuntimeTemporalContext.groundWebQuery(combined, now: now)
        guard grounded.caseInsensitiveCompare(plan.primary) != .orderedSame else { return nil }
        return grounded
    }

    /// Mots porteurs, dans l'ordre d'apparition, sans doublon.
    /// Les expressions entre guillemets sont conservées telles quelles : elles
    /// portent une intention explicite de recherche exacte.
    static func keywords(_ text: String, limit: Int = maxKeywords) -> [String] {
        var out: [String] = []
        var seen = Set<String>()

        for phrase in quotedPhrases(text) {
            let key = fold(phrase)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append("\"\(phrase)\"")
            if out.count >= limit { return out }
        }

        for raw in text.components(separatedBy: wordSeparators) {
            // Les points internes doivent survivre (« 24.04 », « node.js ») :
            // découper dessus transformait une version en deux nombres inutiles.
            let word = raw.trimmingCharacters(in: edgePunctuation)
            guard word.count >= 2, word.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            let folded = fold(word)
            guard !isStopWord(folded) else { continue }
            guard seen.insert(folded).inserted else { continue }
            out.append(word)
            if out.count >= limit { break }
        }
        return out
    }

    /// Un composé dont toutes les parties sont vides de sens l'est aussi
    /// (« peux-tu », « est-ce »).
    private static func isStopWord(_ folded: String) -> Bool {
        if stopWords.contains(folded) { return true }
        guard folded.contains("-") else { return false }
        let parts = folded.split(separator: "-").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return true }
        return parts.allSatisfy { stopWords.contains($0) }
    }

    private static let wordSeparators = CharacterSet(
        charactersIn: " \t\n\r\u{00A0},;:!?()[]{}«»\"'\u{2019}`|<>*=+&\u{2014}\u{2013}"
    )

    private static let edgePunctuation = CharacterSet(charactersIn: ".-_/\\\u{2019}'")

    /// Termes retenus pour mesurer la couverture des extraits.
    static func coverageTerms(_ plan: WebQueryPlan) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for term in plan.strongTerms {
            let folded = fold(term.replacingOccurrences(of: "\"", with: ""))
            guard folded.count >= 4, seen.insert(folded).inserted else { continue }
            out.append(folded)
        }
        return out
    }

    private static func quotedPhrases(_ text: String) -> [String] {
        guard text.contains("\"") else { return [] }
        var out: [String] = []
        var current: String?
        for char in text {
            if char == "\"" {
                if let value = current {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count >= 3 { out.append(trimmed) }
                    current = nil
                } else {
                    current = ""
                }
            } else if current != nil {
                current?.append(char)
            }
        }
        return out
    }

    private static func stripNoise(_ text: String) -> String {
        var query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        // Certaines demandes empilent les formules (« stp cherche sur internet … »).
        while changed {
            changed = false
            let lower = query.lowercased()
            for prefix in leadingNoise where lower.hasPrefix(prefix) {
                query = String(query.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                break
            }
        }
        while let last = query.last, last == "?" || last == "!" || last == "." {
            query.removeLast()
        }
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}
