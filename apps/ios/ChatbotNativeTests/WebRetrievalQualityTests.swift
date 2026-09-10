import XCTest
@testable import ChatbotNative

// MARK: - Construction des requêtes

final class WebQueryPlannerTests: XCTestCase {
    /// Une phrase française complète envoyée telle quelle au SERP remonte des
    /// forums de questions, pas des pages de contenu.
    func testPlanStripsPolitenessAndStopWords() {
        let plan = WebQueryPlanner.plan(
            userText: "Peux-tu me trouver la meilleure carte graphique pour jouer en 1440p ?",
            history: [],
            now: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let lower = plan.primary.lowercased()
        XCTAssertFalse(lower.contains("peux-tu"))
        XCTAssertFalse(lower.contains("pour"))
        XCTAssertTrue(lower.contains("carte"))
        XCTAssertTrue(lower.contains("graphique"))
        XCTAssertTrue(lower.contains("1440p"))
    }

    /// « meilleure » est un marqueur de présent : la requête doit être ancrée
    /// sur l'année en cours, sinon le SERP sert des comparatifs de 2023.
    func testCurrentIntentIsGroundedOnCurrentYear() {
        let now = Date()
        let year = String(Calendar.current.component(.year, from: now))
        let plan = WebQueryPlanner.plan(userText: "meilleure carte graphique 1440p", now: now)
        XCTAssertTrue(plan.primary.contains(year))
    }

    /// Une question de suivi ne contient pas son sujet : sans réécriture, le
    /// moteur reçoit « prix » et répond n'importe quoi.
    func testFollowUpQuestionInheritsSubjectFromHistory() {
        let history = [
            LLMChatMessage(role: .user, content: "Parle-moi de la RTX 5070 Ti Super"),
            LLMChatMessage(role: .assistant, content: "La RTX 5070 Ti Super est une carte milieu de gamme."),
        ]
        let plan = WebQueryPlanner.plan(userText: "et son prix ?", history: history)
        let lower = plan.primary.lowercased()
        XCTAssertTrue(lower.contains("prix"))
        XCTAssertTrue(lower.contains("5070"))
    }

    /// Les guillemets expriment une recherche exacte : elle doit survivre au
    /// filtrage des mots vides.
    func testQuotedPhraseIsPreserved() {
        let plan = WebQueryPlanner.plan(userText: "cherche \"loi de finances 2026\" pour les PME")
        XCTAssertTrue(plan.primary.contains("\"loi de finances 2026\""))
    }

    /// Une seule requête SERP : une variante du suivi elliptique (« prix des
    /// modèles 2026 ») ramenait des Tesla et doublait le temps réseau.
    func testPlanUsesSingleQuery() {
        let plan = WebQueryPlanner.plan(userText: "comment installer Docker sur Ubuntu 24.04")
        XCTAssertEqual(plan.allQueries, [plan.primary])
        XCTAssertTrue(plan.variants.isEmpty)
    }

    /// Régression : « le prix des modèles » après des souris gamer ne doit
    /// surtout pas devenir une requête de voitures Tesla.
    func testFollowUpAboutModelsKeepsTheProductSubject() {
        let history = [
            LLMChatMessage(role: .user, content: "Quelles sont les meilleures souris gamer ?"),
            LLMChatMessage(
                role: .assistant,
                content: "Les plus citées sont la Logitech G Pro X Superlight 2 et la Razer DeathAdder V3."
            ),
        ]
        let plan = WebQueryPlanner.plan(userText: "le prix des modèles", history: history)
        let lower = plan.primary.lowercased()
        XCTAssertTrue(lower.contains("souris") || lower.contains("gamer") || lower.contains("logitech"))
        XCTAssertFalse(lower.contains("modele") || lower.contains("modèle"))
        XCTAssertFalse(plan.variants.contains(where: { $0.lowercased().contains("modèle") || $0.lowercased().contains("modele") }))
    }

    /// Relancer avec la même requête ne rapporte rien : autant répondre.
    func testFollowUpQueryIsNilWhenNothingIsMissing() {
        let plan = WebQueryPlanner.plan(userText: "prix RTX 5070")
        XCTAssertNil(WebQueryPlanner.followUpQuery(plan: plan, uncovered: []))
    }

    func testFollowUpQueryTargetsUncoveredTerms() {
        let plan = WebQueryPlanner.plan(userText: "autonomie batterie iPhone 17 Pro")
        let query = WebQueryPlanner.followUpQuery(plan: plan, uncovered: ["autonomie"])
        XCTAssertNotNil(query)
        XCTAssertTrue(query?.lowercased().contains("autonomie") ?? false)
    }
}

// MARK: - Extraction HTML

final class HTMLReadabilityTests: XCTestCase {
    /// Le stripper naïf conservait les menus et les scripts : sur une page
    /// réelle, le texte utile se retrouvait noyé dans la navigation.
    func testMainTextDropsNavigationAndScripts() {
        let html = """
        <html><head><title>Recette de lasagnes</title></head>
        <body>
        <nav><a href="/">Accueil</a><a href="/recettes">Recettes</a></nav>
        <script>var tracker = 1;</script>
        <style>.a{color:red}</style>
        <article><p>Faire revenir les oignons pendant dix minutes environ.</p>
        <p>Ajouter la b&eacute;chamel puis enfourner trente minutes.</p></article>
        <footer>Mentions légales</footer>
        </body></html>
        """
        let text = HTMLReadability.mainText(from: html)
        XCTAssertTrue(text.contains("oignons"))
        XCTAssertTrue(text.contains("béchamel"))
        XCTAssertFalse(text.contains("tracker"))
        XCTAssertFalse(text.contains("color:red"))
        XCTAssertFalse(text.contains("Accueil"))
        XCTAssertFalse(text.contains("Mentions légales"))
    }

    func testTitleIsDecoded() {
        let html = "<html><head><title>Caf&eacute; &amp; th&eacute;</title></head><body>x</body></html>"
        XCTAssertEqual(HTMLReadability.title(from: html), "Café & thé")
    }

    /// La collapse précédente bouclait sur `replacingOccurrences` : quadratique,
    /// et exécutée sur le thread d'UI.
    func testCollapseWhitespaceIsSinglePassAndKeepsParagraphs() {
        let input = "a    b\n\n\n\nc   \n d"
        XCTAssertEqual(HTMLReadability.collapseWhitespace(input), "a b\n\nc\nd")
    }

    func testNumericEntitiesAreDecoded() {
        XCTAssertEqual(HTMLReadability.decodeEntities("prix&#160;: 30&#8364;"), "prix\u{00A0}: 30€")
        XCTAssertEqual(HTMLReadability.decodeEntities("30&#x20AC;"), "30€")
    }

    /// Une page ISO-8859-1 renvoyait une chaîne vide et la source était perdue.
    func testLatin1PageIsDecoded() {
        let data = "Café crème".data(using: .isoLatin1)!
        let decoded = HTMLReadability.decode(data, textEncodingName: "iso-8859-1")
        XCTAssertEqual(decoded, "Café crème")
    }
}

// MARK: - Fusion des classements

final class WebNetworkFusionTests: XCTestCase {
    private func source(_ n: Int, url: String) -> SearchSourceDTO {
        SearchSourceDTO(id: "web_\(n)", title: "T\(n)", url: url, domain: WebURLNormalizer.domain(from: url), snippet: "s\(n)")
    }

    /// Une URL vue par deux points d'entrée passe devant une URL première d'un
    /// seul : c'est tout l'intérêt de la fusion par rang réciproque.
    func testConsensusURLWinsOverSingleListLeader() {
        let a = [source(1, url: "https://only.example/x"), source(2, url: "https://both.example/y")]
        let b = [source(3, url: "https://other.example/z"), source(4, url: "https://both.example/y")]
        let fused = WebNetwork.fuse([a, b], limit: 3)
        XCTAssertEqual(fused.first?.domain, "both.example")
        XCTAssertEqual(fused.first?.id, "web_1")
    }

    func testFusionDeduplicatesTrailingSlashAndFragment() {
        let a = [source(1, url: "https://x.example/page")]
        let b = [source(2, url: "https://x.example/page/#top")]
        XCTAssertEqual(WebNetwork.fuse([a, b], limit: 5).count, 1)
    }

    func testEmptyListsProduceNoResult() {
        XCTAssertTrue(WebNetwork.fuse([[], []], limit: 5).isEmpty)
    }
}

// MARK: - Preuves web

final class WebEvidenceQualityTests: XCTestCase {
    private let profile = LocalModelExecutionProfile.qwen35Dense2B

    /// Une coupe tous les N caractères sépare un nombre de son unité et fait
    /// recopier des valeurs fausses.
    func testChunksRespectSentenceBoundaries() {
        let text = """
        La carte graphique testée consomme 220 W en charge soutenue sur ce banc d'essai.
        Elle embarque 12 Go de mémoire vidéo cadencée à 21 Gbit/s par puce mémoire.
        Le prix public conseillé annoncé par le constructeur est de 649 euros en France.
        Les performances relevées en 1440p atteignent 118 images par seconde en moyenne.
        """
        let chunks = WebEvidenceBuilder.chunk(text, maxChars: 180)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertTrue(
                chunk.hasSuffix(".") || chunk.hasSuffix("!") || chunk.hasSuffix("?"),
                "coupe hors frontière de phrase : \(chunk)"
            )
            XCTAssertLessThanOrEqual(chunk.count, 200)
        }
        XCTAssertTrue(chunks.contains { $0.contains("649 euros") })
    }

    /// Trois pages qui reprennent la même dépêche ne doivent pas occuper trois
    /// fois le contexte.
    func testDuplicateExcerptsAcrossSourcesAreDropped() {
        let shared = "Le constructeur annonce une disponibilité mondiale au mois de mars prochain partout."
        var signatures: [Set<String>] = []
        let first = WebEvidenceBuilder.selectChunks(
            [shared],
            terms: WebEvidenceBuilder.tokens("disponibilité mars"),
            questionVector: nil,
            limit: 2,
            acceptedSignatures: &signatures
        )
        let second = WebEvidenceBuilder.selectChunks(
            [shared],
            terms: WebEvidenceBuilder.tokens("disponibilité mars"),
            questionVector: nil,
            limit: 2,
            acceptedSignatures: &signatures
        )
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
    }

    /// Le budget doit être réparti : une source citée sans extrait invite le
    /// modèle à inventer son contenu.
    func testEverySelectedSourceCarriesAnExcerpt() {
        var sources: [SearchSourceDTO] = []
        var pages: [String: String] = [:]
        for i in 1...5 {
            let url = "https://site\(i).example/gpu"
            sources.append(
                SearchSourceDTO(
                    id: "web_\(i)",
                    title: "Comparatif carte graphique \(i)",
                    url: url,
                    domain: "site\(i).example",
                    snippet: "carte graphique 1440p test \(i)"
                )
            )
            pages[url] = "La carte graphique testée atteint \(i * 20) images par seconde en 1440p sur ce protocole. "
                + "Le comparatif numéro \(i) mesure la consommation à \(200 + i) watts en charge soutenue."
        }
        let packet = WebEvidenceBuilder.build(
            query: "meilleure carte graphique 1440p",
            sources: sources,
            pageTexts: pages,
            profile: profile,
            userRequest: "Quelle est la meilleure carte graphique pour le 1440p ?"
        )
        XCTAssertEqual(packet.evidence.count, packet.sources.count)
        for item in packet.evidence {
            XCTAssertFalse(item.excerpt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        XCTAssertLessThanOrEqual(packet.promptBlock.count, profile.resolvedWebEvidenceCharBudget)
    }

    /// La numérotation citée par le modèle doit désigner la source affichée.
    func testSourceNumberingFollowsEvidenceOrder() {
        let sources = [
            SearchSourceDTO(id: "web_1", title: "Hors sujet", url: "https://a.example", domain: "a.example", snippet: "chat"),
            SearchSourceDTO(id: "web_2", title: "Lasagnes vegan maison", url: "https://b.example", domain: "b.example", snippet: "lasagnes vegan tofu"),
        ]
        let packet = WebEvidenceBuilder.build(
            query: "lasagnes vegan",
            sources: sources,
            pageTexts: ["https://b.example": "Les lasagnes vegan se préparent avec du tofu ferme et une béchamel végétale."],
            profile: profile
        )
        XCTAssertEqual(packet.sources.first?.domain, "b.example")
        XCTAssertEqual(packet.sources.first?.id, "web_1")
        XCTAssertEqual(packet.evidence.first?.sourceId, "web_2")
        XCTAssertTrue(packet.promptBlock.contains("SOURCE_ID: web_1"))
    }

    /// La couverture pilote la relance : si les extraits ne parlent pas de la
    /// demande, mieux vaut une seconde requête qu'une réponse à côté.
    func testCoverageDetectsMissingTerms() {
        let sources = [
            SearchSourceDTO(id: "web_1", title: "Autonomie batterie", url: "https://a.example", domain: "a.example", snippet: "batterie"),
        ]
        let packet = WebEvidenceBuilder.build(
            query: "autonomie batterie",
            sources: sources,
            pageTexts: ["https://a.example": "La batterie tient une journée complète en usage normal quotidien."],
            profile: profile,
            userRequest: "autonomie batterie et recharge sans fil",
            coverageTerms: ["batterie", "recharge"]
        )
        XCTAssertEqual(packet.uncoveredTerms, ["recharge"])
        XCTAssertEqual(packet.coverage, 0.5, accuracy: 0.001)
    }

    /// Un terme cité une fois en pied de page ne vaut pas un article qui traite
    /// le sujet : le score binaire ne faisait pas la différence.
    func testWeightedScoreRewardsRepetitionInTitle() {
        let focused = SearchSourceDTO(
            id: "a", title: "Test RTX 5070 : performances RTX 5070 en jeu",
            url: "https://a.example", domain: "a.example", snippet: "RTX 5070 testée"
        )
        let incidental = SearchSourceDTO(
            id: "b", title: "Actualités matériel informatique de la semaine",
            url: "https://b.example", domain: "b.example", snippet: "un article évoque la RTX 5070"
        )
        let terms = WebEvidenceBuilder.tokens("rtx 5070")
        XCTAssertGreaterThan(
            WebEvidenceBuilder.weightedLexicalScore(focused, terms: terms),
            WebEvidenceBuilder.weightedLexicalScore(incidental, terms: terms)
        )
    }
}

// MARK: - Cache

final class WebRetrievalCacheTests: XCTestCase {
    /// Régénérer une réponse ne doit pas refaire tout le réseau.
    func testPageRoundTrip() async {
        let cache = WebRetrievalCache.shared
        await cache.purge()
        await cache.store(page: "contenu", title: "Titre", for: "https://x.example/a")
        let hit = await cache.page(for: "https://x.example/a")
        XCTAssertEqual(hit?.text, "contenu")
        XCTAssertEqual(hit?.title, "Titre")
        await cache.purge()
    }

    func testKeyIgnoresCaseAndTrailingSlash() {
        XCTAssertEqual(
            WebRetrievalCache.key("https://X.example/A/"),
            WebRetrievalCache.key("https://x.example/a")
        )
    }

    func testMissingEntryReturnsNil() async {
        let cache = WebRetrievalCache.shared
        await cache.purge()
        let hit = await cache.page(for: "https://absent.example")
        XCTAssertNil(hit)
    }
}
