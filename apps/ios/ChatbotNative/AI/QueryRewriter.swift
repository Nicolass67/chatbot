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

        // Un pronom dans les trois premiers mots reprend quasi toujours le tour
        // précédent ; plus loin dans la phrase il réfère souvent à un sujet déjà
        // nommé dans la même phrase.
        return words.prefix(3).contains { anaphoricMarkers.contains($0) }
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
