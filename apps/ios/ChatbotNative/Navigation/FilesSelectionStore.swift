import Foundation
import Observation

/// Fichier sélectionné dans Files (persiste entre dossiers).
struct FilesSelectedItem: Identifiable, Hashable, Sendable {
    var id: String { fileId }
    let fileId: String
    let filename: String
    let rootId: String
    let relativePath: String
}

/// Multi-sélection Files partagée sur tout le NavigationStack.
@Observable
@MainActor
final class FilesSelectionStore {
    var isSelecting = false
    private(set) var items: [FilesSelectedItem] = []
    private(set) var contentEpoch: Int = 0

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    func contains(_ fileId: String) -> Bool {
        items.contains { $0.fileId == fileId }
    }

    func toggle(_ item: FilesSelectedItem) {
        if let idx = items.firstIndex(where: { $0.fileId == item.fileId }) {
            items.remove(at: idx)
        } else {
            items.append(item)
        }
    }

    func select(_ item: FilesSelectedItem) {
        guard !contains(item.fileId) else { return }
        items.append(item)
    }

    func remove(fileIds: Set<String>) {
        items.removeAll { fileIds.contains($0.fileId) }
    }

    func clear() {
        items = []
    }

    func bumpContent() {
        contentEpoch &+= 1
    }

    func endSelecting() {
        isSelecting = false
        items = []
    }

    func beginSelecting() {
        isSelecting = true
    }
}
