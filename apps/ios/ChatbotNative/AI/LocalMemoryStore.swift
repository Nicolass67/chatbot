import Foundation

/// Fait mémorisé, avec son vecteur pour le rappel sémantique.
struct LocalMemoryFact: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var text: String
    var createdAt: Date
    var lastRecalledAt: Date?
    var recallCount: Int
    /// Vecteur `NLEmbedding` normalisé. Absent si les embeddings système
    /// n'étaient pas disponibles au moment de l'écriture — recalculé à la demande.
    var vector: [Double]?

    init(text: String, vector: [Double]? = nil) {
        self.id = UUID().uuidString
        self.text = text
        self.createdAt = Date()
        self.lastRecalledAt = nil
        self.recallCount = 0
        self.vector = vector
    }
}

/// Mémoire long terme locale.
///
/// Deux corrections par rapport à la version précédente :
///
/// 1. **Elle est écrite.** `remember` n'était appelé par aucun chemin de code :
///    le store restait vide en permanence, et `memory_recall` répondait toujours
///    « aucun fait mémorisé ». L'alimentation vient maintenant de
///    `ConversationMemoryService` après chaque tour.
/// 2. **Le rappel est sémantique.** La sélection par sous-chaîne ne retrouvait
///    « je suis développeur Swift » sur la question « quel est mon métier ? »,
///    faute de mot commun. Les embeddings comparent le sens ; le lexical reste
///    en repli quand `NLEmbedding` est indisponible.
@MainActor
final class LocalMemoryStore {
    static let shared = LocalMemoryStore()

    private let storeKey = "localAI.memory.facts.v2"
    private let legacyKey = "localAI.memory.facts.v1"
    private let maxFacts = 240

    private var facts: [LocalMemoryFact]

    init() {
        facts = Self.loadPersisted(key: storeKey)
        // Migration des anciens faits (tableau de chaînes, sans vecteur).
        if facts.isEmpty, let legacy = UserDefaults.standard.stringArray(forKey: legacyKey), !legacy.isEmpty {
            facts = legacy.map { LocalMemoryFact(text: $0) }
            persist()
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    var allFacts: [LocalMemoryFact] { facts }
    var count: Int { facts.count }

    // MARK: Écriture

    @discardableResult
    func remember(_ fact: String) -> Bool {
        let cleaned = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 4, cleaned.count <= 400 else { return false }

        let vector = TextEmbedder.shared.vector(for: cleaned)

        // Déduplication : identique à la casse près, ou très proche sémantiquement.
        // Sans ça, « il aime le café » réapparaît à chaque conversation qui l'évoque.
        let normalized = Self.normalizedKey(cleaned)
        if facts.contains(where: { Self.normalizedKey($0.text) == normalized }) {
            return false
        }
        if let vector {
            for existing in facts {
                guard let other = existing.vector,
                      let similarity = TextEmbedder.similarity(vector, other) else { continue }
                if similarity >= 0.93 { return false }
            }
        }

        facts.insert(LocalMemoryFact(text: cleaned, vector: vector), at: 0)
        evictIfNeeded()
        persist()
        return true
    }

    func rememberAll(_ newFacts: [String]) -> Int {
        var inserted = 0
        for fact in newFacts where remember(fact) { inserted += 1 }
        return inserted
    }

    func forget(id: String) {
        facts.removeAll { $0.id == id }
        persist()
    }

    func forgetAll() {
        facts.removeAll()
        persist()
    }

    // MARK: Rappel

    /// Faits pertinents formatés pour un prompt, dans la limite de `budget` caractères.
    func recall(matching query: String, budget: Int) -> String {
        let selected = rankedFacts(matching: query, limit: 10)
        guard !selected.isEmpty else { return "" }

        var out = ""
        var touched: [String] = []
        for fact in selected {
            let line = "- " + fact.text
            if out.count + line.count + 1 > budget { break }
            out += (out.isEmpty ? "" : "\n") + line
            touched.append(fact.id)
        }
        noteRecall(ids: touched)
        return out
    }

    /// Classement par pertinence : sémantique si disponible, sinon lexical.
    func rankedFacts(matching query: String, limit: Int) -> [LocalMemoryFact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !facts.isEmpty else { return [] }
        guard !trimmed.isEmpty else { return Array(facts.prefix(limit)) }

        if let queryVector = TextEmbedder.shared.vector(for: trimmed) {
            ensureVectors()
            var scored: [(LocalMemoryFact, Double)] = []
            for fact in facts {
                guard let vector = fact.vector,
                      let similarity = TextEmbedder.similarity(queryVector, vector) else { continue }
                scored.append((fact, similarity))
            }
            if !scored.isEmpty {
                // Seuil : sous 0,45 la « proximité » n'est plus qu'un artefact.
                // Un fait hors sujet injecté dans le prompt système ne fait pas
                // que ne rien apporter : un petit modèle s'y accroche et répond
                // à côté. Le silence vaut mieux qu'un rappel douteux.
                let relevant = scored
                    .filter { $0.1 >= 0.45 }
                    .sorted { $0.1 > $1.1 }
                    .prefix(limit)
                    .map(\.0)
                if !relevant.isEmpty { return Array(relevant) }
                return []
            }
        }

        return lexicalMatches(query: trimmed, limit: limit)
    }

    private func lexicalMatches(query: String, limit: Int) -> [LocalMemoryFact] {
        let lower = query.lowercased()
        let tokens = lower
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 4 }
        guard !tokens.isEmpty else { return [] }

        var scored: [(LocalMemoryFact, Int)] = []
        for fact in facts {
            let factLower = fact.text.lowercased()
            let hits = tokens.reduce(0) { $0 + (factLower.contains($1) ? 1 : 0) }
            if hits > 0 { scored.append((fact, hits)) }
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: Interne

    /// Recalcule les vecteurs manquants (faits migrés, ou écrits alors que
    /// `NLEmbedding` n'était pas encore disponible).
    private func ensureVectors() {
        guard TextEmbedder.shared.isAvailable else { return }
        var changed = false
        for index in facts.indices where facts[index].vector == nil {
            if let vector = TextEmbedder.shared.vector(for: facts[index].text) {
                facts[index].vector = vector
                changed = true
            }
        }
        if changed { persist() }
    }

    private func noteRecall(ids: [String]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        for index in facts.indices where set.contains(facts[index].id) {
            facts[index].recallCount += 1
            facts[index].lastRecalledAt = Date()
        }
        persist()
    }

    /// Éviction par utilité : on sacrifie d'abord les faits jamais rappelés et
    /// les plus anciens, pas simplement la fin du tableau.
    private func evictIfNeeded() {
        guard facts.count > maxFacts else { return }
        let ordered = facts.sorted { lhs, rhs in
            if lhs.recallCount != rhs.recallCount { return lhs.recallCount > rhs.recallCount }
            return lhs.createdAt > rhs.createdAt
        }
        facts = Array(ordered.prefix(maxFacts))
    }

    private static func normalizedKey(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(facts) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    private static func loadPersisted(key: String) -> [LocalMemoryFact] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LocalMemoryFact].self, from: data) else {
            return []
        }
        return decoded
    }
}
