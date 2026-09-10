import Foundation

/// Décide, pour un message utilisateur, la forme de réponse attendue :
/// budget de sortie, réflexion, échantillonnage.
///
/// Remplace les listes de mots-clés (`contains("explique")`) qui échouaient sur
/// toute formulation non prévue : « je comprends pas bien comment ça marche »
/// ne contient aucun des marqueurs de la liste « explication », et recevait donc
/// le budget d'une question factuelle courte.
///
/// Deux étages :
/// 1. règles lexicales à haute précision (impératifs explicites, salutations) ;
/// 2. similarité d'embeddings `NLEmbedding` contre des phrases prototypes.
///
/// `NLEmbedding` est un modèle système : rien à télécharger, pas de RAM prise
/// sur le budget GGUF. Absent pour le français sur l'appareil, on retombe sur
/// l'étage lexical.
actor SemanticRouter {
    static let shared = SemanticRouter()

    struct Route: Sendable {
        var task: LocalModelExecutionProfile.GenerationTask
        var intent: Intent
        var useThinking: Bool
        var confidence: Double
        var source: String

        enum Intent: String, Sendable {
            /// Salutation, remerciement, accusé de réception.
            case smalltalk
            /// Question fermée à réponse courte.
            case factual
            /// Demande d'explication, de mécanisme, de « pourquoi ».
            case explanation
            /// Comparaison, analyse, raisonnement multi-étapes, calcul.
            case reasoning
            /// Rédaction, reformulation, traduction, résumé.
            case writing
            /// Suivi qui dépend du tour précédent.
            case followUp
        }

        func generationOptions(profile: LocalModelExecutionProfile) -> LocalGenerationOptions {
            var sampling: LlamaSamplingConfig
            if useThinking {
                sampling = .qwenThinking
            } else {
                switch intent {
                case .writing:
                    sampling = .factual
                case .factual, .followUp:
                    // Question fermée : réduire la queue limite les digressions
                    // et les faits inventés en fin de réponse.
                    sampling = .qwenInstruct
                    sampling.temperature = 0.5
                    sampling.topP = 0.75
                case .smalltalk, .explanation, .reasoning:
                    sampling = .qwenInstruct
                }
            }
            return LocalGenerationOptions(
                sampling: sampling,
                grammar: nil,
                timeout: profile.generationTimeoutSeconds,
                enableThinking: profile.adaptiveThinking ? useThinking : nil
            )
        }

        /// Budget de sortie, majoré de la trace de réflexion quand elle est active
        /// (elle n'est pas affichée mais consomme bien des tokens générés).
        func outputTokens(profile: LocalModelExecutionProfile) -> Int {
            let base = profile.outputTokens(for: task)
            guard profile.adaptiveThinking, useThinking else { return base }
            return base + profile.thinkingTokenBudget
        }

        var traceFields: [String: String] {
            [
                "intent": intent.rawValue,
                "task": task.rawValue,
                "thinking": useThinking ? "on" : "off",
                "confidence": String(format: "%.2f", confidence),
                "source": source,
            ]
        }
    }

    // MARK: Prototypes

    /// Phrases de référence par intention. Elles sont plongées une seule fois
    /// puis mises en cache ; c'est la moyenne des similarités qui décide.
    private static let prototypes: [(Route.Intent, [String])] = [
        (.smalltalk, [
            "bonjour comment ça va",
            "merci beaucoup c'est parfait",
            "ok très bien",
            "salut",
        ]),
        (.factual, [
            "quelle est la capitale de l'Italie",
            "combien de temps dure un vol Paris New York",
            "qui a écrit ce livre",
            "quel jour sommes-nous",
        ]),
        (.explanation, [
            "explique moi comment fonctionne un moteur électrique",
            "je ne comprends pas bien pourquoi ça marche comme ça",
            "c'est quoi exactement une base de données",
            "peux-tu me détailler le principe de ce mécanisme",
        ]),
        (.reasoning, [
            "compare ces deux options et dis moi laquelle est la meilleure",
            "analyse les avantages et les inconvénients de cette approche",
            "aide moi à choisir entre ces solutions selon mon budget",
            "calcule le coût total sur trois ans et justifie",
        ]),
        (.writing, [
            "rédige un message pour annoncer la nouvelle",
            "reformule ce paragraphe de façon plus claire",
            "traduis ce texte en anglais",
            "résume ce document en quelques lignes",
        ]),
    ]

    private var prototypeVectors: [(Route.Intent, [[Double]])]?
    private var embeddingUnavailable = false

    // MARK: Routage

    func route(userText: String, history: [LLMChatMessage] = []) async -> Route {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Route(task: .short, intent: .smalltalk, useThinking: false, confidence: 1, source: "empty")
        }

        // Étage 1 — règles à haute précision. Elles gagnent sur les embeddings :
        // « explique en détail » est une consigne, pas une nuance sémantique.
        if let lexical = lexicalRoute(trimmed) {
            return lexical
        }

        // Étage 2 — similarité d'embeddings. Une relance elliptique
        // (« et lui ? », « et pour Berlin ? ») ne porte aucun signal
        // exploitable : on la classe sur sa forme réécrite, sinon tout suivi
        // retombe sur « réponse courte » quel que soit le sujet discuté.
        let isFollowUp = !history.isEmpty && QueryRewriter.needsContext(trimmed)
        let classified = isFollowUp
            ? QueryRewriter.retrievalQuery(userText: trimmed, history: history)
            : trimmed
        if let semantic = semanticRoute(classified) {
            return isFollowUp ? Self.dampenedFollowUp(semantic) : semantic
        }

        // Étage 3 — suivi elliptique non classé : la brièveté du tour prime.
        if isFollowUp {
            return Route(
                task: .short,
                intent: .followUp,
                useThinking: false,
                confidence: 0.5,
                source: "followup:unclassified"
            )
        }

        // Étage 4 — repli structurel : la longueur et la ponctuation restent
        // des signaux faibles mais réels.
        return structuralRoute(trimmed, history: history)
    }

    /// Le sujet d'un suivi vient du contexte, pas du tour lui-même : on garde la
    /// profondeur héritée mais on ne déclenche ni réflexion ni format long sur
    /// trois mots. Sans ce garde-fou, « et lui ? » produit une dissertation.
    private static func dampenedFollowUp(_ route: Route) -> Route {
        var damped = route
        damped.intent = .followUp
        damped.useThinking = false
        damped.task = route.task == .detailed ? .explanation : route.task
        damped.source = route.source + ":followup"
        return damped
    }

    // MARK: Étage lexical

    private func lexicalRoute(_ text: String) -> Route? {
        let lower = text.lowercased()

        let explicitDetail = [
            "en détail", "en detail", "détaille", "detaille", "développe", "developpe",
            "approfondi", "cours complet", "longuement", "de façon exhaustive",
            "de facon exhaustive", "le plus complet possible",
        ]
        if explicitDetail.contains(where: { lower.contains($0) }) {
            return Route(
                task: .detailed,
                intent: .explanation,
                useThinking: false,
                confidence: 0.95,
                source: "lexical:detail"
            )
        }

        let explicitReasoning = [
            "compare", "comparaison", "lequel est le meilleur", "laquelle est la meilleure",
            "avantages et inconvénients", "avantages et inconvenients", "pour et contre",
            "aide moi à choisir", "aide-moi à choisir", "calcule", "combien ça coûte au total",
            "étape par étape", "etape par etape", "démontre", "demontre",
        ]
        if explicitReasoning.contains(where: { lower.contains($0) }) {
            return Route(
                task: .detailed,
                intent: .reasoning,
                useThinking: false,
                confidence: 0.9,
                source: "lexical:reasoning"
            )
        }

        // Salutation pure : court, sans point d'interrogation, très bref.
        let greetings = ["bonjour", "salut", "bonsoir", "coucou", "merci", "ok", "d'accord", "parfait", "super"]
        if text.count <= 24, !text.contains("?"),
           greetings.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") }) {
            return Route(
                task: .short,
                intent: .smalltalk,
                useThinking: false,
                confidence: 0.95,
                source: "lexical:smalltalk"
            )
        }

        // Le suivi elliptique n'est plus traité ici : il est reclassé sur sa
        // forme réécrite (`QueryRewriter`) pour hériter du sujet réel.
        return nil
    }

    // MARK: Étage embeddings

    private func semanticRoute(_ text: String) -> Route? {
        guard !embeddingUnavailable else { return nil }
        let embedder = TextEmbedder.shared
        guard embedder.isAvailable else {
            embeddingUnavailable = true
            return nil
        }
        guard let queryVector = embedder.vector(for: text) else { return nil }

        let vectors = ensurePrototypeVectors(embedder: embedder)
        guard !vectors.isEmpty else {
            embeddingUnavailable = true
            return nil
        }

        var best: (Route.Intent, Double)?
        var runnerUp: Double = -1
        for (intent, samples) in vectors {
            let scores = samples.compactMap { TextEmbedder.similarity(queryVector, $0) }
            guard !scores.isEmpty else { continue }
            // Moyenne des deux meilleurs : robuste à un prototype hors sujet.
            let top = scores.sorted(by: >).prefix(2)
            let score = top.reduce(0, +) / Double(top.count)
            if best == nil || score > best!.1 {
                runnerUp = best?.1 ?? runnerUp
                best = (intent, score)
            } else if score > runnerUp {
                runnerUp = score
            }
        }

        guard let (intent, score) = best else { return nil }
        // Marge trop faible ⇒ la classification n'apporte rien de fiable.
        let margin = score - max(runnerUp, 0)
        guard score >= 0.45, margin >= 0.02 else { return nil }

        // La réflexion se paie en tokens générés : ~25 s d'attente supplémentaire
        // sur l'appareil. Une similarité d'embedding, même correcte, n'est pas une
        // preuve que la question en a besoin — seule la consigne explicite
        // (« compare », « étape par étape ») la déclenche.
        return Route(
            task: Self.task(for: intent),
            intent: intent,
            useThinking: false,
            confidence: min(1, score),
            source: "embedding"
        )
    }

    private func ensurePrototypeVectors(embedder: TextEmbedder) -> [(Route.Intent, [[Double]])] {
        if let cached = prototypeVectors { return cached }
        var built: [(Route.Intent, [[Double]])] = []
        for (intent, samples) in Self.prototypes {
            let vectors = samples.compactMap { embedder.vector(for: $0) }
            if !vectors.isEmpty { built.append((intent, vectors)) }
        }
        prototypeVectors = built
        return built
    }

    // MARK: Étage structurel

    private func structuralRoute(_ text: String, history: [LLMChatMessage]) -> Route {
        let lower = text.lowercased()
        let words = text.split(whereSeparator: { $0.isWhitespace }).count

        if lower.hasPrefix("explique") || lower.hasPrefix("pourquoi")
            || lower.contains("comment ça marche") || lower.contains("comment ca marche")
            || lower.contains("c'est quoi") || lower.contains("c’est quoi") {
            return Route(
                task: .explanation,
                intent: .explanation,
                useThinking: false,
                confidence: 0.6,
                source: "structural:explain"
            )
        }
        if words <= 6, !history.isEmpty {
            return Route(
                task: .short,
                intent: .followUp,
                useThinking: false,
                confidence: 0.4,
                source: "structural:short"
            )
        }
        if words >= 40 {
            return Route(
                task: .explanation,
                intent: .explanation,
                useThinking: false,
                confidence: 0.4,
                source: "structural:long"
            )
        }
        return Route(
            task: .short,
            intent: .factual,
            useThinking: false,
            confidence: 0.3,
            source: "structural:default"
        )
    }

    private static func task(for intent: Route.Intent) -> LocalModelExecutionProfile.GenerationTask {
        switch intent {
        case .smalltalk, .factual, .followUp: return .short
        case .explanation: return .explanation
        case .reasoning: return .detailed
        case .writing: return .explanation
        }
    }
}
