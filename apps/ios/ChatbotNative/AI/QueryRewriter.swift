import Foundation

/// Réécriture de requête pour la **recherche** (mémoire, embeddings, routage).
///
/// « et lui ? », « pourquoi ça », « le deuxième » ne portent aucun signal
/// exploitable : un embedding calculé dessus est du bruit, et la mémoire
/// remonte des faits au hasard. Les vrais assistants font passer la requête par
/// une étape de réécriture contextuelle avant le retrieval.
///
/// Ici la réécriture est **déterministe** et n'ajoute aucun tour de décodage :
/// on rattache le tour courant aux derniers tours quand il est anaphorique.
/// Le prompt envoyé au modèle n'est jamais modifié — seule la clé de recherche
/// l'est, donc une mauvaise détection dégrade au pire le rappel, jamais la
/// réponse elle-même.
enum QueryRewriter {
    /// Marqueurs anaphoriques : pronoms, déictiques, ellipses de reprise.
    private static let anaphoricMarkers: Set<String> = [
        "il", "elle", "ils", "elles", "lui", "leur", "eux",
        "ça", "ca", "cela", "ceci", "celui", "celle", "ceux", "celles",
        "le", "la", "les", "l", "y", "en",
        "son", "sa", "ses", "leurs",
        "ce", "cet", "cette", "cettes",
        "dernier", "dernière", "derniere", "précédent", "precedent",
        "premier", "première", "premiere", "deuxième", "deuxieme", "troisième", "troisieme",
        "autre", "autres", "même", "meme", "pareil", "idem",
        "it", "its", "this", "that", "these", "those", "them", "they",
    ]

    /// Formules de suite qui n'apportent aucun contenu propre.
    private static let continuationPrefixes: [String] = [
        "et ", "et alors", "donc ", "alors ", "ok et ", "d'accord et ",
        "encore", "continue", "poursuis", "développe", "developpe",
        "plus de détails", "plus de details", "détaille", "detaille",
        "résume", "resume", "reformule", "traduis", "et ensuite", "ensuite",
        "pourquoi", "comment", "et après", "et apres",
    ]

    /// Mots dont le sens dominant hors contexte n'est pas celui de la conversation
    /// (« modèle » → voiture Tesla, « souris » → animal). Sans ancrage, un 2B
    /// bascule sur ce sens-là.
    private static let ambiguousNouns: Set<String> = [
        "modele", "modeles", "modèle", "modèles", "model", "models",
        "prix", "tarif", "tarifs", "cout", "coût", "couts", "coûts",
        "avis", "note", "notes", "score", "test", "tests",
        "version", "versions", "serie", "série", "generation", "génération",
    ]

    /// Au-delà, la requête se suffit à elle-même : pas de réécriture.
    private static let selfContainedWordCount = 8

    /// Requête enrichie destinée au retrieval (mémoire, embeddings), jamais au prompt.
    static func retrievalQuery(userText: String, history: [LLMChatMessage]) -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard needsContext(trimmed) else { return trimmed }

        let anchors = recentAnchors(history: history)
        guard !anchors.isEmpty else { return trimmed }

        // La requête d'origine reste en tête : elle porte l'intention, le
        // contexte ne fait que la désambiguïser.
        return ([trimmed] + anchors).joined(separator: " \u{2014} ")
    }

    /// La requête dépend-elle d'un tour précédent pour être interprétable ?
    static func needsContext(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = tokenize(lower)
        guard !words.isEmpty else { return false }

        // Une question longue et spécifique se suffit presque toujours.
        if words.count > selfContainedWordCount { return false }

        if words.count <= 3 { return true }
        if continuationPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        if words.contains(where: { ambiguousNouns.contains($0) }), words.count <= 8 {
            return true
        }

        // Un pronom dans les trois premiers mots reprend quasi toujours le tour
        // précédent ; plus loin dans la phrase il réfère souvent à un sujet déjà
        // nommé dans la même phrase.
        return words.prefix(3).contains { anaphoricMarkers.contains($0) }
    }

    /// Sujet explicite à rappeler au modèle quand le tour courant est une
    /// relance elliptique.
    ///
    /// « le prix des modèles » après « les meilleures souris gamer » : le
    /// modèle a bien l'historique, mais un 2B se laisse capturer par le sens le
    /// plus fréquent de « modèle » et part sur des voitures. Nommer le sujet
    /// coûte une ligne et supprime la classe entière de dérapages.
    static func subjectAnchor(userText: String, history: [LLMChatMessage]) -> String? {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needsContext(trimmed) else { return nil }
        for message in history.reversed() {
            guard message.role == .user else { continue }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard content.count >= 12, !needsContext(content) else { continue }
            return String(content.prefix(180))
        }
        return nil
    }

    /// Message réellement envoyé au modèle. Le tour elliptique reste affiché
    /// tel quel dans l'UI ; le moteur, lui, reçoit une phrase autonome.
    ///
    /// Sans ça, « le prix des modèles » après une liste de souris est lu comme
    /// une question sur les Tesla Model 3/Y — le sens le plus fréquent de
    /// « modèle » + « prix » dans les données d'entraînement.
    static func groundedUserTurn(userText: String, history: [LLMChatMessage]) -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let subject = subjectAnchor(userText: trimmed, history: history) else {
            return trimmed
        }
        return """
        \(trimmed)

        Contexte obligatoire — le message ci-dessus porte sur ce sujet, et uniquement celui-là :
        « \(subject) »
        Ne change pas de domaine (pas de voitures, pas d’un autre produit) même si un mot est ambigu.
        """
    }

    /// Derniers tours porteurs de contenu, du plus récent au plus ancien.
    private static func recentAnchors(history: [LLMChatMessage], limit: Int = 2) -> [String] {
        var anchors: [String] = []
        for message in history.reversed() {
            guard message.role == .user || message.role == .assistant else { continue }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard content.count >= 12 else { continue }
            // Un tour lui-même anaphorique n'ancre rien : on remonte plus haut.
            if message.role == .user, needsContext(content) { continue }
            anchors.append(String(content.prefix(240)))
            if anchors.count >= limit { break }
        }
        return anchors
    }

    private static func tokenize(_ lowercased: String) -> [String] {
        lowercased
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
