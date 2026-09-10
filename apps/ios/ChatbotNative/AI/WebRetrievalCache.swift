import Foundation

/// Cache TTL des résultats web (SERP + texte de page).
///
/// Sans lui, « régénère », une question de suivi sur le même sujet ou une
/// relance de couverture refont l'intégralité des requêtes et des fetchs : sur
/// réseau mobile c'est plusieurs secondes par page, pour un contenu identique.
/// Le PC dispose déjà d'un cache d'extraction ; l'app locale n'en avait aucun.
///
/// Deux durées de vie distinctes : un SERP se périme vite (actualité), le
/// contenu d'une page beaucoup moins.
actor WebRetrievalCache {
    static let shared = WebRetrievalCache()

    /// Résultats de recherche : au-delà, on risque de servir des résultats
    /// d'hier sur une question d'actualité.
    static let serpTTL: TimeInterval = 20 * 60
    /// Texte de page : le contenu éditorial bouge rarement dans la journée.
    static let pageTTL: TimeInterval = 6 * 3600

    private static let maxSerpEntries = 48
    private static let maxPageEntries = 96

    private struct SourcesEntry: Codable {
        var storedAt: Date
        var sources: [SearchSourceDTO]
    }

    private struct PageEntry: Codable {
        var storedAt: Date
        var text: String
        var title: String?
    }

    private var serp: [String: SourcesEntry] = [:]
    private var pages: [String: PageEntry] = [:]
    private var loaded = false
    private var dirty = false

    // MARK: - API

    func sources(for query: String) -> [SearchSourceDTO]? {
        load()
        let key = Self.key(query)
        guard let entry = serp[key] else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) < Self.serpTTL else {
            serp.removeValue(forKey: key)
            return nil
        }
        return entry.sources
    }

    func store(sources: [SearchSourceDTO], for query: String) {
        guard !sources.isEmpty else { return }
        load()
        serp[Self.key(query)] = SourcesEntry(storedAt: Date(), sources: sources)
        evict(&serp, limit: Self.maxSerpEntries) { $0.storedAt }
        dirty = true
        persist()
    }

    func page(for url: String) -> (text: String, title: String?)? {
        load()
        let key = Self.key(url)
        guard let entry = pages[key] else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) < Self.pageTTL else {
            pages.removeValue(forKey: key)
            return nil
        }
        return (entry.text, entry.title)
    }

    func store(page text: String, title: String?, for url: String) {
        guard !text.isEmpty else { return }
        load()
        pages[Self.key(url)] = PageEntry(storedAt: Date(), text: text, title: title)
        evict(&pages, limit: Self.maxPageEntries) { $0.storedAt }
        dirty = true
        persist()
    }

    func purge() {
        serp.removeAll()
        pages.removeAll()
        dirty = true
        persist()
    }

    // MARK: - Persistance

    private func evict<V>(_ store: inout [String: V], limit: Int, date: (V) -> Date) {
        guard store.count > limit else { return }
        let ordered = store.sorted { date($0.value) > date($1.value) }
        store = Dictionary(uniqueKeysWithValues: ordered.prefix(limit).map { ($0.key, $0.value) })
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let directory = Self.directory else { return }
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: directory.appendingPathComponent("serp.json")),
           let decoded = try? decoder.decode([String: SourcesEntry].self, from: data) {
            serp = decoded.filter { Date().timeIntervalSince($0.value.storedAt) < Self.serpTTL }
        }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("pages.json")),
           let decoded = try? decoder.decode([String: PageEntry].self, from: data) {
            pages = decoded.filter { Date().timeIntervalSince($0.value.storedAt) < Self.pageTTL }
        }
    }

    private func persist() {
        guard dirty, let directory = Self.directory else { return }
        dirty = false
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(serp) {
            try? data.write(to: directory.appendingPathComponent("serp.json"), options: .atomic)
        }
        if let data = try? encoder.encode(pages) {
            try? data.write(to: directory.appendingPathComponent("pages.json"), options: .atomic)
        }
    }

    /// Dossier `Caches` : purgeable par le système, jamais sauvegardé iCloud.
    private static let directory: URL? = {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("WebRetrieval", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    /// Clé stable, insensible à la casse et aux variations de fin d'URL.
    static func key(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return String(hash, radix: 36)
    }
}
