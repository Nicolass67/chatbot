import Foundation

@MainActor
final class OrganizationHistoryStore {
    static let shared = OrganizationHistoryStore()
    static let maxEntries = 20
    private let defaultsKey = "files.organizer.rollbackHistory"

    private(set) var manifests: [OrganizationRollbackManifest] = []

    init() { load() }

    var last: OrganizationRollbackManifest? { manifests.first }

    func save(_ manifest: OrganizationRollbackManifest) {
        guard !manifest.moves.isEmpty else { return }
        manifests.removeAll { $0.executionId == manifest.executionId }
        manifests.insert(manifest, at: 0)
        if manifests.count > Self.maxEntries {
            manifests = Array(manifests.prefix(Self.maxEntries))
        }
        persist()
    }

    func remove(_ executionId: String) {
        manifests.removeAll { $0.executionId == executionId }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([OrganizationRollbackManifest].self, from: data)
        else {
            manifests = []
            return
        }
        manifests = Array(decoded.prefix(Self.maxEntries))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(manifests) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
