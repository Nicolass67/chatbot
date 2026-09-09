import Foundation

/// Compatibilité estimée pour un device type (ex. iPhone 14 Plus 6 Go).
enum LocalModelCompatibility: String, Sendable, Codable, CaseIterable {
    case recommended // vert
    case experimental // orange
    case notRecommended // rouge

    var label: String {
        switch self {
        case .recommended: return "Recommandé"
        case .experimental: return "Expérimental"
        case .notRecommended: return "Non recommandé"
        }
    }

    var symbolName: String {
        switch self {
        case .recommended: return "checkmark.circle.fill"
        case .experimental: return "exclamationmark.triangle.fill"
        case .notRecommended: return "xmark.octagon.fill"
        }
    }
}

/// Capacités déclaratives du modèle (pas d’auto-switch selon la tâche).
struct LocalModelCapabilities: Equatable, Sendable, Hashable {
    var vision: Bool
    var audio: Bool
    var reasoning: Bool
    var multilingual: Bool

    static let textOnly = LocalModelCapabilities(
        vision: false, audio: false, reasoning: false, multilingual: true
    )
}

/// Descripteur d’un modèle GGUF installable.
/// L’IA locale est **indépendante** de LM Studio PC — jamais de bascule auto.
struct LocalModelDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let provider: String
    let architecture: String
    let parameterCountLabel: String
    let quant: String
    /// Taille attendue du fichier GGUF (validation ±5 %).
    let expectedBytes: Int64
    let filename: String
    /// `nil` = pas encore téléchargeable (entrée catalogue).
    let downloadURL: URL?
    let sha256: String?
    let version: String
    let license: String
    let contextLength: Int
    let capabilities: LocalModelCapabilities
    let runtimeProfile: LocalModelRuntimeProfile
    /// RAM device recommandée (Go).
    let minimumRecommendedRAMGB: Double
    /// Estimation prudente RAM runtime (poids + KV + marge iOS), Go.
    let estimatedRuntimeMemoryGB: Double
    let compatibilityIPhone14Plus: LocalModelCompatibility
    let compatibilityNote: String
    let statusNote: String

    var isDownloadable: Bool { downloadURL != nil && expectedBytes > 0 }

    var expectedSizeLabel: String {
        guard expectedBytes > 0 else { return "—" }
        let gb = Double(expectedBytes) / 1_073_741_824.0
        if gb >= 1 {
            return String(format: "%.2f Go", gb)
        }
        return String(format: "%.0f Mo", Double(expectedBytes) / 1_048_576.0)
    }

    var estimatedRAMLabel: String {
        String(format: "~%.1f Go RAM", estimatedRuntimeMemoryGB)
    }

    /// Modèle principal recommandé (Qwen3 1.7B Q4_K_M) — inchangé / validé.
    static var primary: LocalModelDescriptor {
        catalog.first { $0.id == "qwen3-1.7b-q4_k_m" }!
    }

    static let catalog: [LocalModelDescriptor] = [
        // MARK: Vert — validé / léger
        LocalModelDescriptor(
            id: "qwen3-1.7b-q4_k_m",
            displayName: "Qwen3 1.7B",
            provider: "Qwen / second-state",
            architecture: "qwen3",
            parameterCountLabel: "1.7B",
            quant: "Q4_K_M",
            expectedBytes: 1_282_439_264,
            filename: "Qwen3-1.7B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/second-state/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"),
            sha256: nil,
            version: "1.1",
            license: "Apache-2.0",
            contextLength: 32_768,
            capabilities: .textOnly,
            runtimeProfile: .chatmlQwen,
            minimumRecommendedRAMGB: 4,
            estimatedRuntimeMemoryGB: 2.4,
            compatibilityIPhone14Plus: .recommended,
            compatibilityNote: "Validé sur iPhone 14 Plus / A15 — modèle actif par défaut.",
            statusNote: "Stable"
        ),
        LocalModelDescriptor(
            id: "lfm25-1.2b-instruct-q4_k_m",
            displayName: "LFM2.5 1.2B Instruct",
            provider: "LiquidAI",
            architecture: "lfm2",
            parameterCountLabel: "1.2B",
            quant: "Q4_K_M",
            expectedBytes: 730_895_168,
            filename: "LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf"),
            sha256: nil,
            version: "1.0",
            license: "LFM License",
            contextLength: 32_768,
            capabilities: LocalModelCapabilities(vision: false, audio: false, reasoning: false, multilingual: true),
            runtimeProfile: .generic,
            minimumRecommendedRAMGB: 3,
            estimatedRuntimeMemoryGB: 1.6,
            compatibilityIPhone14Plus: .recommended,
            compatibilityNote: "Très léger — bon pour comparer vitesse vs Qwen3 1.7B.",
            statusNote: "À tester"
        ),
        LocalModelDescriptor(
            id: "qwen35-2b-q4_k_m",
            displayName: "Qwen3.5 2B",
            provider: "Qwen / LM Studio community",
            architecture: "qwen35",
            parameterCountLabel: "2B",
            quant: "Q4_K_M",
            expectedBytes: 1_270_808_032, // Hub lmstudio-community exact
            filename: "Qwen3.5-2B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/lmstudio-community/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf"),
            sha256: nil,
            version: "1.0",
            license: "Apache-2.0",
            contextLength: 32_768,
            capabilities: LocalModelCapabilities(vision: false, audio: false, reasoning: true, multilingual: true),
            runtimeProfile: .chatmlQwen,
            minimumRecommendedRAMGB: 4,
            estimatedRuntimeMemoryGB: 2.8,
            compatibilityIPhone14Plus: .recommended,
            compatibilityNote: "Prioritaire qualité/taille — à benchmarker vs Qwen3 1.7B.",
            statusNote: "À tester"
        ),

        // MARK: Orange — expérimental sur 6 Go
        LocalModelDescriptor(
            id: "gemma4-e2b-it-q4_k_m",
            displayName: "Gemma 4 E2B",
            provider: "Google / LM Studio community",
            architecture: "gemma4",
            parameterCountLabel: "~2.3B eff.",
            quant: "Q4_K_M",
            expectedBytes: 3_427_880_384,
            filename: "gemma-4-E2B-it-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/lmstudio-community/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"),
            sha256: nil,
            version: "1.0",
            license: "Gemma",
            contextLength: 128_000,
            capabilities: LocalModelCapabilities(vision: true, audio: false, reasoning: true, multilingual: true),
            runtimeProfile: .gemma,
            minimumRecommendedRAMGB: 6,
            estimatedRuntimeMemoryGB: 4.8,
            compatibilityIPhone14Plus: .experimental,
            compatibilityNote: "Fichier ~3.4 Go + KV : pression mémoire forte sur 6 Go. Charge explicite seulement.",
            statusNote: "Expérimental"
        ),
        LocalModelDescriptor(
            id: "qwen3-4b-q4_k_m",
            displayName: "Qwen3 4B",
            provider: "Qwen",
            architecture: "qwen3",
            parameterCountLabel: "4B",
            quant: "Q4_K_M",
            expectedBytes: 2_500_000_000, // approx
            filename: "Qwen3-4B-Q4_K_M.gguf",
            downloadURL: nil, // URL exacte à valider avant activation download
            sha256: nil,
            version: "0",
            license: "Apache-2.0",
            contextLength: 32_768,
            capabilities: LocalModelCapabilities(vision: false, audio: false, reasoning: true, multilingual: true),
            runtimeProfile: .chatmlQwen,
            minimumRecommendedRAMGB: 6,
            estimatedRuntimeMemoryGB: 4.2,
            compatibilityIPhone14Plus: .experimental,
            compatibilityNote: "~2.5 Go disque — limite sur 6 Go RAM avec contexte utile.",
            statusNote: "Catalogue — download bientôt"
        ),
        LocalModelDescriptor(
            id: "granite4-micro-q4_k_m",
            displayName: "Granite 4.0 Micro",
            provider: "IBM",
            architecture: "granite",
            parameterCountLabel: "~3B",
            quant: "Q4_K_M",
            expectedBytes: 2_100_000_000,
            filename: "granite-4.0-micro-Q4_K_M.gguf",
            downloadURL: nil,
            sha256: nil,
            version: "0",
            license: "Apache-2.0",
            contextLength: 128_000,
            capabilities: .textOnly,
            runtimeProfile: .generic,
            minimumRecommendedRAMGB: 6,
            estimatedRuntimeMemoryGB: 3.8,
            compatibilityIPhone14Plus: .experimental,
            compatibilityNote: "~2.1 Go — à tester ; pas encore d’URL GGUF figée dans l’app.",
            statusNote: "Catalogue"
        ),

        // MARK: Rouge — non recommandé 6 Go
        LocalModelDescriptor(
            id: "gemma4-e4b-it",
            displayName: "Gemma 4 E4B",
            provider: "Google",
            architecture: "gemma4",
            parameterCountLabel: "~4.5B eff.",
            quant: "Q4_K_M",
            expectedBytes: 0,
            filename: "gemma-4-E4B-it-Q4_K_M.gguf",
            downloadURL: nil,
            sha256: nil,
            version: "0",
            license: "Gemma",
            contextLength: 128_000,
            capabilities: LocalModelCapabilities(vision: true, audio: false, reasoning: true, multilingual: true),
            runtimeProfile: .gemma,
            minimumRecommendedRAMGB: 8,
            estimatedRuntimeMemoryGB: 6.5,
            compatibilityIPhone14Plus: .notRecommended,
            compatibilityNote: "Trop ambitieux pour 6 Go (poids + KV + marge iOS).",
            statusNote: "Non recommandé"
        ),
        LocalModelDescriptor(
            id: "phi4-mini-3.8b",
            displayName: "Phi-4 Mini 3.8B",
            provider: "Microsoft",
            architecture: "phi3",
            parameterCountLabel: "3.8B",
            quant: "Q4_K_M",
            expectedBytes: 0,
            filename: "Phi-4-mini-Q4_K_M.gguf",
            downloadURL: nil,
            sha256: nil,
            version: "0",
            license: "MIT",
            contextLength: 128_000,
            capabilities: LocalModelCapabilities(vision: false, audio: false, reasoning: true, multilingual: true),
            runtimeProfile: .generic,
            minimumRecommendedRAMGB: 8,
            estimatedRuntimeMemoryGB: 5.5,
            compatibilityIPhone14Plus: .notRecommended,
            compatibilityNote: "Intéressant raisonnement/code mais lourd pour A15 / 6 Go.",
            statusNote: "Non recommandé"
        ),
    ]

    static func descriptor(id: String) -> LocalModelDescriptor? {
        catalog.first { $0.id == id }
    }

    static var downloadable: [LocalModelDescriptor] {
        catalog.filter(\.isDownloadable)
    }
}
