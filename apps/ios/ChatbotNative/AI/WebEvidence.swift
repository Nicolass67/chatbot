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
    /// Part des termes porteurs de la demande réellement présents dans les extraits.
    var coverage: Double = 1.0
    /// Termes de la demande qu'aucun extrait ne couvre — base d'une relance.
    var uncoveredTerms: [String] = []
}

/// SEARCH → RANK → SELECT → CHUNK → COMPRESS (déterministe, un seul modèle).
///
/// Le classement est **hybride** : un score lexical (fréquence des termes,
/// normalisé par la longueur) fusionné avec une similarité d'embedding quand
/// `NLEmbedding` est disponible. Le lexical seul rate les reformulations
/// (« carte graphique » vs « GPU ») ; l'embedding seul remonte des pages
/// vaguement du même thème sans les faits demandés.
enum WebEvidenceBuilder {
    /// Poids de la partie sémantique dans le score final d'une source.
    private static let semanticWeightSource = 0.35
    /// Poids de la partie sémantique dans le choix des extraits.
    private static let semanticWeightChunk = 0.40
    /// Au-delà, deux extraits disent la même chose : le second gaspille du contexte.
    private static let duplicateJaccardThreshold = 0.8

    // MARK: - Classement des sources

    static func rank(_ sources: [SearchSourceDTO], query: String) -> [SearchSourceDTO] {
        let terms = tokens(query)
        return sources
            .enumerated()
            .sorted { lhs, rhs in
                let a = score(lhs.element, terms: terms)
                let b = score(rhs.element, terms: terms)
                if a == b { return lhs.offset < rhs.offset }
                return a > b
            }
            .map(\.element)
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

    /// Reclassement hybride : lexical pondéré + similarité d'embedding.
    /// Sans embedding disponible, se réduit exactement au classement lexical.
    static func semanticRank(
        _ sources: [SearchSourceDTO],
        question: String,
        query: String
    ) -> [SearchSourceDTO] {
        guard sources.count > 1 else { return sources }
        let terms = tokens(query)
        let lexical = sources.map { weightedLexicalScore($0, terms: terms) }
        let maxLexical = max(lexical.max() ?? 0, 0.0001)

        guard let questionVector = TextEmbedder.shared.vector(for: question) else {
            return zip(sources, lexical)
                .enumerated()
                .sorted { lhs, rhs in
                    if lhs.element.1 == rhs.element.1 { return lhs.offset < rhs.offset }
                    return lhs.element.1 > rhs.element.1
                }
                .map(\.element.0)
        }

        let scored: [(source: SearchSourceDTO, score: Double, order: Int)] = sources.enumerated().map { idx, source in
            let text = [source.title, source.snippet ?? "", source.domain ?? ""]
                .joined(separator: " ")
            let semantic = TextEmbedder.shared.vector(for: text)
                .flatMap { TextEmbedder.similarity(questionVector, $0) } ?? 0
            let blended = (1 - semanticWeightSource) * (lexical[idx] / maxLexical)
                + semanticWeightSource * max(0, semantic)
            return (source, blended, idx)
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.order < rhs.order }
                return lhs.score > rhs.score
            }
            .map(\.source)
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

    /// Sélection complète : pertinence → reclassement hybride → diversité de domaines.
    static func selectSources(
        _ sources: [SearchSourceDTO],
        question: String,
        query: String,
        limit: Int
    ) -> [SearchSourceDTO] {
        let relevant = filterRelevant(sources, query: query)
        let reranked = semanticRank(relevant, question: question, query: query)
        return diversify(reranked, limit: limit)
    }

    // MARK: - Construction du paquet

    static func build(
        query: String,
        sources: [SearchSourceDTO],
        pageTexts: [String: String],
        profile: LocalModelExecutionProfile,
        userRequest: String? = nil,
        coverageTerms: [String] = []
    ) -> WebEvidencePacket {
        let request = (userRequest ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = selectSources(
            sources,
            question: request,
            query: query,
            limit: max(1, profile.maxWebResults)
        )
        let perSource = max(1, profile.maxEvidencePerSource)
        let charBudget = max(400, profile.resolvedWebEvidenceCharBudget)
        // Répartir le budget entre les sources retenues plutôt que de laisser le
        // clip final amputer les dernières : une source citée sans extrait est
        // une invitation à halluciner son contenu.
        let overhead = 300 + 220 * max(1, selected.count)
        let excerptCap = max(
            240,
            min(profile.maxChunkChars, (charBudget - overhead) / max(1, selected.count * perSource))
        )
        let terms = tokens(query)
        let questionVector = TextEmbedder.shared.vector(for: request)

        var evidence: [WebEvidence] = []
        // Signatures des extraits déjà retenus : trois pages qui reprennent la
        // même dépêche ne doivent pas occuper trois fois le contexte.
        var acceptedSignatures: [Set<String>] = []

        for src in selected {
            let raw = stripFetchPrefix(pageTexts[src.id] ?? pageTexts[src.url] ?? src.snippet ?? "")
            let chunks = chunk(raw, maxChars: excerptCap)
            let picked = selectChunks(
                chunks,
                terms: terms,
                questionVector: questionVector,
                limit: perSource,
                acceptedSignatures: &acceptedSignatures
            )
            let excerpt: String
            if picked.isEmpty {
                excerpt = String((src.snippet ?? "").prefix(profile.maxWebSnippetChars))
            } else {
                excerpt = picked.joined(separator: "\n")
            }
            guard !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
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
            charBudget: charBudget
        )
        let uncovered = uncoveredTerms(coverageTerms, in: evidence)
        let coverage = coverageTerms.isEmpty
            ? 1.0
            : 1.0 - Double(uncovered.count) / Double(coverageTerms.count)

        return WebEvidencePacket(
            userRequest: request,
            query: query,
            sources: reindexAligned(selected, evidence: evidence),
            evidence: evidence,
            promptBlock: block,
            coverage: coverage,
            uncoveredTerms: uncovered
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

    /// Numérote les sources **dans l'ordre des extraits** : une citation
    /// `(web_2)` doit désigner la deuxième source affichée, pas la deuxième
    /// source trouvée. Sans alignement, les liens de l'UI ne correspondent pas
    /// aux numéros cités par le modèle.
    static func reindexAligned(
        _ sources: [SearchSourceDTO],
        evidence: [WebEvidence]
    ) -> [SearchSourceDTO] {
        guard !evidence.isEmpty else { return reindex(sources) }
        let byId = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [SearchSourceDTO] = []
        for item in evidence {
            guard let source = byId[item.sourceId] else { continue }
            ordered.append(source)
        }
        for source in sources where !ordered.contains(where: { $0.url == source.url }) {
            ordered.append(source)
        }
        return reindex(ordered)
    }

    // MARK: - Découpage et sélection des extraits

    /// Découpe sur les frontières de phrases.
    ///
    /// Une coupe tous les N caractères tronque au milieu d'un mot et sépare un
    /// chiffre de son unité (« 12,4 » / « Go ») : le modèle recopie alors des
    /// valeurs fausses. On agrège des phrases entières jusqu'à `maxChars`.
    static func chunk(_ text: String, maxChars: Int) -> [String] {
        let cleaned = stripFetchPrefix(text)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let cap = max(160, maxChars)

        var out: [String] = []
        var current = ""
        for sentence in sentences(cleaned) {
            if sentence.count > cap {
                if !current.isEmpty { out.append(current); current = "" }
                out.append(contentsOf: hardSplit(sentence, maxChars: cap))
                continue
            }
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= cap {
                current += " " + sentence
            } else {
                out.append(current)
                current = sentence
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Phrases (ponctuation forte ou saut de paragraphe), blancs normalisés.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = paragraph.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var current = ""
            for char in line {
                current.append(char)
                guard char == "." || char == "!" || char == "?" || char == "…" else { continue }
                // Une abréviation (« M. », « env. ») ne termine pas une phrase :
                // on n'accepte la coupe qu'au-delà d'une longueur plausible.
                if current.count < 24 { continue }
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            let tail = current.trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { out.append(tail) }
        }
        return out.filter { !$0.isEmpty }
    }

    private static func hardSplit(_ text: String, maxChars: Int) -> [String] {
        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex
            out.append(String(text[start..<end]).trimmingCharacters(in: .whitespaces))
            start = end
        }
        return out.filter { !$0.isEmpty }
    }

    /// Choisit les extraits les plus informatifs, sans redite entre sources.
    static func selectChunks(
        _ chunks: [String],
        terms: [String],
        questionVector: [Double]?,
        limit: Int,
        acceptedSignatures: inout [Set<String>]
    ) -> [String] {
        guard !chunks.isEmpty else { return [] }
        let lexical = chunks.map { Double(lexicalScore($0, terms: terms)) }
        let maxLexical = max(lexical.max() ?? 0, 0.0001)

        var scored: [(text: String, score: Double, order: Int)] = []
        for (idx, text) in chunks.enumerated() {
            var value = lexical[idx] / maxLexical
            if let questionVector,
               let vector = TextEmbedder.shared.vector(for: String(text.prefix(400))),
               let similarity = TextEmbedder.similarity(questionVector, vector) {
                value = (1 - semanticWeightChunk) * value + semanticWeightChunk * max(0, similarity)
            }
            scored.append((text, value, idx))
        }
        scored.sort { lhs, rhs in
            if lhs.score == rhs.score { return lhs.order < rhs.order }
            return lhs.score > rhs.score
        }

        var picked: [(text: String, order: Int)] = []
        for candidate in scored {
            guard picked.count < max(1, limit) else { break }
            let signature = signatureTokens(candidate.text)
            guard !signature.isEmpty else { continue }
            if acceptedSignatures.contains(where: { jaccard($0, signature) >= duplicateJaccardThreshold }) {
                continue
            }
            acceptedSignatures.append(signature)
            picked.append((candidate.text, candidate.order))
        }
        // Restituer l'ordre de lecture de la page : un extrait « étape 3 » avant
        // « étape 1 » fait produire une réponse incohérente.
        return picked.sorted { $0.order < $1.order }.map(\.text)
    }

    static func signatureTokens(_ text: String) -> Set<String> {
        Set(tokens(text).filter { $0.count >= 4 }.prefix(60))
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        guard intersection > 0 else { return 0 }
        return Double(intersection) / Double(a.union(b).count)
    }

    // MARK: - Couverture

    /// Termes de la demande qu'aucun extrait ne mentionne.
    static func uncoveredTerms(_ terms: [String], in evidence: [WebEvidence]) -> [String] {
        guard !terms.isEmpty, !evidence.isEmpty else { return terms }
        let haystack = fold(evidence.map(\.excerpt).joined(separator: " "))
        return terms.filter { !haystack.contains($0) }
    }

    // MARK: - Normalisation

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

    /// Score lexical continu : compte les occurrences (plafonnées) et normalise
    /// par la longueur. Le `contains` binaire donnait le même score à une page
    /// qui cite le terme une fois en pied de page et à un article qui le traite.
    static func weightedLexicalScore(_ source: SearchSourceDTO, terms: [String]) -> Double {
        guard !terms.isEmpty else { return 0 }
        let title = fold(source.title)
        let snippet = fold(source.snippet ?? "")
        let domain = fold(source.domain ?? "")
        var total = 0.0
        for term in terms {
            total += 3.0 * min(2.0, Double(occurrences(of: term, in: title)))
            total += 1.0 * min(3.0, Double(occurrences(of: term, in: snippet)))
            total += 2.0 * (domain.contains(term) ? 1.0 : 0.0)
        }
        // Un titre à rallonge qui contient tout n'est pas plus pertinent.
        let lengthPenalty = 1.0 + Double(title.count) / 400.0
        return total / lengthPenalty
    }

    static func occurrences(of term: String, in text: String) -> Int {
        guard !term.isEmpty, !text.isEmpty else { return 0 }
        var count = 0
        var index = text.startIndex
        while let range = text.range(of: term, range: index..<text.endIndex) {
            count += 1
            index = range.upperBound
            if count >= 8 { break }
        }
        return count
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
    /// En dessous, les extraits ne parlent pas vraiment de la demande : une
    /// relance ciblée coûte un aller-retour, mais évite une réponse à côté.
    private static let coverageRelaunchThreshold = 0.5

    @MainActor
    static func gather(
        query: String,
        history: [LLMChatMessage] = [],
        profile: LocalModelExecutionProfile,
        onEvent: ((AgentOrchestrationEvent) -> Void)?
    ) async throws -> WebEvidencePacket {
        let plan = WebQueryPlanner.plan(userText: query, history: history)
        WorkflowTrace.log("run:web-search", [
            "query": String(plan.primary.prefix(80)),
            "variants": "\(plan.variants.count)",
        ])
        onEvent?(.webSearch(query: plan.primary))
        onEvent?(.toolStarted(tool: "web_search", query: plan.primary))

        let coverage = WebQueryPlanner.coverageTerms(plan)
        var harvest = try await collect(
            plan: plan,
            queries: plan.allQueries,
            profile: profile,
            coverageTerms: coverage,
            previousPages: [:],
            previousSources: [],
            onEvent: onEvent
        )

        // Relance unique : au-delà, on empile du bruit et on fait attendre.
        if harvest.packet.coverage < coverageRelaunchThreshold,
           let followUp = WebQueryPlanner.followUpQuery(plan: plan, uncovered: harvest.packet.uncoveredTerms) {
            WorkflowTrace.log("web", [
                "follow_up": String(followUp.prefix(80)),
                "coverage": String(format: "%.2f", harvest.packet.coverage),
            ])
            onEvent?(.webSearch(query: followUp))
            let second = try await collect(
                plan: plan,
                queries: [followUp],
                profile: profile,
                coverageTerms: coverage,
                previousPages: harvest.pages,
                previousSources: harvest.packet.sources,
                onEvent: onEvent
            )
            if second.packet.coverage > harvest.packet.coverage { harvest = second }
        }
        let packet = harvest.packet

        WorkflowTrace.log("web", [
            "selected": "\(packet.sources.count)",
            "coverage": String(format: "%.2f", packet.coverage),
            "prompt_chars": "\(packet.promptBlock.count)",
        ])
        return packet
    }

    /// Un tour de récolte : recherche, lecture parallèle, construction du paquet.
    /// Les textes lus sont rendus séparément pour qu'une relance ne refetche pas
    /// des pages déjà téléchargées.
    private struct Harvest {
        var packet: WebEvidencePacket
        var pages: [String: String]
    }

    @MainActor
    private static func collect(
        plan: WebQueryPlan,
        queries: [String],
        profile: LocalModelExecutionProfile,
        coverageTerms: [String],
        previousPages: [String: String],
        previousSources: [SearchSourceDTO],
        onEvent: ((AgentOrchestrationEvent) -> Void)?
    ) async throws -> Harvest {
        try Task.checkCancellation()
        // Sur-échantillonner le SERP : le reclassement hybride a besoin de
        // candidats pour trancher, la diversité de domaines en consomme.
        let found = await WebNetwork.search(
            queries: queries,
            limit: max(profile.maxWebResults * 2, 8),
            snippetBudget: profile.maxWebSnippetChars
        )
        let pool = WebNetwork.fuse([previousSources, found], limit: max(profile.maxWebResults * 2, 8))
        // Le reclassement calcule un embedding par source : hors du thread d'UI,
        // sinon le chat se fige pendant la recherche.
        let question = plan.retrievalQuestion
        let primary = plan.primary
        let resultLimit = max(1, profile.maxWebResults)
        let ranked = await Task.detached(priority: .userInitiated) {
            WebEvidenceBuilder.selectSources(
                pool,
                question: question,
                query: primary,
                limit: resultLimit
            )
        }.value
        if !ranked.isEmpty {
            onEvent?(.sources(ranked))
        }
        onEvent?(.toolCompleted(tool: "web_search", sourceCount: ranked.count))

        let fetchCount = min(profile.maxFetchedPages, ranked.count)
        let targets = Array(ranked.prefix(fetchCount))
        for (idx, source) in targets.enumerated() {
            onEvent?(.sourceOpened(source: source, index: idx + 1, total: fetchCount))
        }

        var pageTexts = previousPages
        let budget = max(400, profile.maxChunkChars * profile.maxEvidencePerSource * 2)
        let timeout = min(15.0, max(8.0, profile.generationTimeoutSeconds / 8))
        // Lecture **parallèle** : en série, trois pages lentes s'additionnent et
        // le tour dépasse le budget avant même la première ligne générée.
        let fetched = await withTaskGroup(of: (String, String)?.self) { group -> [(String, String)] in
            for source in targets {
                guard let url = URL(string: source.url) else { continue }
                // Clé = URL, jamais l'id : une relance renumérote les sources et
                // un cache indexé par `web_2` servirait le texte d'une autre page.
                let key = source.url
                group.addTask {
                    guard let page = try? await WebNetwork.fetchPage(
                        url: url,
                        maxChars: budget,
                        timeout: timeout
                    ) else { return nil }
                    return (key, page.text)
                }
            }
            var out: [(String, String)] = []
            for await item in group {
                if let item { out.append(item) }
            }
            return out
        }
        try Task.checkCancellation()
        for (url, text) in fetched {
            pageTexts[url] = text
            WorkflowTrace.log("web", [
                "source": WebURLNormalizer.domain(from: url) ?? url,
                "chars": "\(text.count)",
            ])
        }

        // Découpage, scoring et déduplication des extraits : même raison, ce
        // travail est proportionnel à la taille des pages lues.
        let userRequest = plan.userRequest
        let snapshot = pageTexts
        let packet = await Task.detached(priority: .userInitiated) {
            WebEvidenceBuilder.build(
                query: primary,
                sources: ranked,
                pageTexts: snapshot,
                profile: profile,
                userRequest: userRequest,
                coverageTerms: coverageTerms
            )
        }.value
        return Harvest(packet: packet, pages: pageTexts)
    }
}
