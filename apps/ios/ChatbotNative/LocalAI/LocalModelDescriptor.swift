import Foundation

/// Descripteur d’un modèle GGUF installable sur l’appareil.
/// L’IA locale est **indépendante** de LM Studio sur le PC — jamais de bascule auto des modèles distants.
struct LocalModelDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let quant: String
    /// Taille attendue du fichier GGUF (validation ±5 %).
    let expectedBytes: Int64
    let filename: String
    /// `nil` = pas encore téléchargeable (entrée catalogue future).
    let downloadURL: URL?
    /// Empreinte SHA-256 optionnelle (nil = pas de vérif crypto pour l’instant).
    let sha256: String?
    let version: String

    var isDownloadable: Bool { downloadURL != nil }

    var expectedSizeLabel: String {
        let gb = Double(expectedBytes) / 1_073_741_824.0
        return String(format: "%.2f Go", gb)
    }

    /// Modèle principal recommandé (Qwen3 1.7B Q4_K_M).
    static var primary: LocalModelDescriptor {
        catalog.first { $0.id == "qwen3-1.7b-q4_k_m" }!
    }

    static let catalog: [LocalModelDescriptor] = [
        LocalModelDescriptor(
            id: "qwen3-1.7b-q4_k_m",
            displayName: "Qwen3 1.7B",
            quant: "Q4_K_M",
            expectedBytes: 1_374_389_535, // ~1.28 Go
            filename: "Qwen3-1.7B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"),
            sha256: nil,
            version: "1.0"
        ),
        LocalModelDescriptor(
            id: "gemma2-2b",
            displayName: "Gemma 2 2B",
            quant: "—",
            expectedBytes: 0,
            filename: "gemma2-2b.gguf",
            downloadURL: nil,
            sha256: nil,
            version: "0"
        ),
        LocalModelDescriptor(
            id: "gemma4-e2b",
            displayName: "Gemma 4 E2B",
            quant: "—",
            expectedBytes: 0,
            filename: "gemma4-e2b.gguf",
            downloadURL: nil,
            sha256: nil,
            version: "0"
        ),
    ]

    static func descriptor(id: String) -> LocalModelDescriptor? {
        catalog.first { $0.id == id }
    }
}
