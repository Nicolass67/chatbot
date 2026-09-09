import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Embeddings de texte via le modèle système `NLEmbedding`.
///
/// Choisi plutôt qu'un modèle GGUF d'embedding : il ne consomme aucun octet du
/// budget mémoire réservé au LLM, ne demande aucun téléchargement, et n'oblige
/// pas à décharger Qwen pour vectoriser une phrase.
///
/// Limite assumée : `sentenceEmbedding` n'est pas disponible pour toutes les
/// langues sur tous les appareils. Chaque appelant doit avoir un repli lexical.
final class TextEmbedder: @unchecked Sendable {
    static let shared = TextEmbedder()

    private let lock = NSLock()
    private var resolved = false

#if canImport(NaturalLanguage)
    private var embedding: NLEmbedding?

    /// Phrases françaises d'abord, anglais ensuite, mots en dernier recours.
    private func resolveEmbedding() -> NLEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if resolved { return embedding }
        resolved = true
        embedding = NLEmbedding.sentenceEmbedding(for: .french)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
            ?? NLEmbedding.wordEmbedding(for: .french)
        return embedding
    }
#endif

    var isAvailable: Bool {
#if canImport(NaturalLanguage)
        resolveEmbedding() != nil
#else
        false
#endif
    }

    /// Vecteur normalisé (norme 1) — la similarité se réduit alors au produit scalaire.
    func vector(for text: String) -> [Double]? {
#if canImport(NaturalLanguage)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, let embedding = resolveEmbedding() else { return nil }
        guard let raw = embedding.vector(for: trimmed) else { return nil }
        return TextEmbedder.normalize(raw)
#else
        _ = text
        return nil
#endif
    }

    func vectors(for texts: [String]) -> [[Double]?] {
        texts.map { vector(for: $0) }
    }

    static func normalize(_ vector: [Double]) -> [Double]? {
        var norm = 0.0
        for value in vector { norm += value * value }
        guard norm > 0 else { return nil }
        let inverse = 1.0 / norm.squareRoot()
        return vector.map { $0 * inverse }
    }

    /// Similarité cosinus de deux vecteurs **déjà normalisés**.
    static func similarity(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0
        for i in a.indices { dot += a[i] * b[i] }
        return dot
    }
}
