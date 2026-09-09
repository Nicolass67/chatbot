import Foundation

/// Mémoire locale légère — sélection déterministe (pas tout le store au LLM).
@MainActor
final class LocalMemoryStore {
    static let shared = LocalMemoryStore()

    private let defaultsKey = "localAI.memory.facts.v1"
    private var facts: [String]

    init() {
        facts = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    func remember(_ fact: String) {
        let cleaned = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if !facts.contains(cleaned) {
            facts.insert(cleaned, at: 0)
            if facts.count > 80 { facts = Array(facts.prefix(80)) }
            persist()
        }
    }

    func recall(matching query: String, budget: Int) -> String {
        let q = query.lowercased()
        let scored: [String]
        if q.isEmpty {
            scored = Array(facts.prefix(8))
        } else {
            let tokens = q.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
            scored = facts.filter { fact in
                let lower = fact.lowercased()
                return tokens.contains { lower.contains($0) } || lower.contains(q)
            }
            if scored.isEmpty {
                return Array(facts.prefix(4)).joined(separator: "\n")
            }
        }
        var out = ""
        for fact in scored {
            if out.count + fact.count + 1 > budget { break }
            out += (out.isEmpty ? "" : "\n") + "- " + fact
        }
        return out
    }

    private func persist() {
        UserDefaults.standard.set(facts, forKey: defaultsKey)
    }
}
