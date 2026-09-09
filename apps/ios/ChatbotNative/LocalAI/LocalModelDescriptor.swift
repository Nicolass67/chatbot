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

/// Projecteur vision (`mmproj`) optionnel — fichier **séparé**, jamais un remplacement du GGUF texte.
struct LocalMmprojDescriptor: Equatable, Hashable, Sendable {
    let filename: String
    let downloadURL: URL
    let expectedBytes: Int64
    let quant: String
    let sourceRepo: String
    let compatibilityNote: String

    var expectedSizeLabel: String {
        let mb = Double(expectedBytes) / 1_048_576.0
        if mb >= 1024 {
            return String(format: "%.2f Go", mb / 1024.0)
        }
        return String(format: "%.0f Mo", mb)
    }
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
    /// `mmproj` compagnon. `nil` = texte seul. Ne jamais substituer ce fichier au GGUF texte.
    /// Pas de valeur par défaut sur ce `let` : Swift exclurait alors le paramètre du memberwise init.
    let mmproj: LocalMmprojDescriptor?

    var isDownloadable: Bool { downloadURL != nil && expectedBytes > 0 }
    var hasOptionalVisionProjector: Bool { mmproj != nil }

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

    var userFacingBlurb: String {
        switch id {
        case "qwen35-2b-q4_k_m":
            return "Rapide · recommandé"
        case "qwen3-1.7b-q4_k_m":
            return "Très rapide · léger"
        case "lfm25-1.2b-instruct-q4_k_m":
            return "Ultra léger · rapide"
        default:
            return "Local"
        }
    }

    var nativeVision: Bool { capabilities.vision && mmproj != nil }
    var nativeAudio: Bool { capabilities.audio }
    var nativeToolCalling: Bool { false }
    var runtimeSupport: String { "llama.cpp · Metal" }
    var recommended: Bool { id == "qwen35-2b-q4_k_m" }

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
            statusNote: "Stable",
            mmproj: nil
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
            runtimeProfile: .chatmlInstruct,
            minimumRecommendedRAMGB: 3,
            estimatedRuntimeMemoryGB: 1.6,
            compatibilityIPhone14Plus: .recommended,
            compatibilityNote: "Très léger — bon pour comparer vitesse vs Qwen3 1.7B.",
            statusNote: "À tester",
            mmproj: nil
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
            capabilities: LocalModelCapabilities(vision: true, audio: false, reasoning: true, multilingual: true),
            runtimeProfile: .chatmlQwen,
            minimumRecommendedRAMGB: 4,
            estimatedRuntimeMemoryGB: 2.8,
            compatibilityIPhone14Plus: .recommended,
            compatibilityNote: "Texte Q4_K_M (~1,18 Go) conservé. Vision = mmproj compagnon du même dépôt (~640 Mo), chargée seulement à la demande.",
            statusNote: "Référence",
            mmproj: LocalMmprojDescriptor(
                filename: "mmproj-Qwen3.5-2B-BF16.gguf",
                downloadURL: URL(string: "https://huggingface.co/lmstudio-community/Qwen3.5-2B-GGUF/resolve/main/mmproj-Qwen3.5-2B-BF16.gguf")!,
                expectedBytes: 671_372_416,
                quant: "BF16",
                sourceRepo: "lmstudio-community/Qwen3.5-2B-GGUF",
                compatibilityNote: "Même dépôt que le GGUF texte (projection_dim 2048 = embedding 2048, clip.projector_type=qwen3vl_merger). Ne pas substituer le Q4_K_M bartowski (~1,40 Go, MTP)."
            )
        ),
    ]

    /// Hors UI utilisateur : trop lourds, sans URL, ou Gemma 4 E2B (~3,35 Go + KV, trop juste sur 6 Go).
    static let experimentalInternal: [LocalModelDescriptor] = [
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
            statusNote: "Catalogue — download bientôt",
            mmproj: nil
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
            runtimeProfile: .granite,
            minimumRecommendedRAMGB: 6,
            estimatedRuntimeMemoryGB: 3.8,
            compatibilityIPhone14Plus: .experimental,
            compatibilityNote: "~2.1 Go — à tester ; pas encore d’URL GGUF figée dans l’app.",
            statusNote: "Catalogue",
            mmproj: nil
        ),

        // MARK: Rouge — non recommandé 6 Go
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
            runtimeProfile: .phi,
            minimumRecommendedRAMGB: 8,
            estimatedRuntimeMemoryGB: 5.5,
            compatibilityIPhone14Plus: .notRecommended,
            compatibilityNote: "Intéressant raisonnement/code mais lourd pour A15 / 6 Go.",
            statusNote: "Non recommandé",
            mmproj: nil
        ),
        LocalModelDescriptor(
            id: "gemma4-e2b-it-q4_0",
            displayName: "Gemma 4 E2B",
            provider: "Google",
            architecture: "gemma4",
            parameterCountLabel: "E2B",
            quant: "Q4_0",
            expectedBytes: 3_349_516_256,
            filename: "gemma-4-E2B_q4_0-it.gguf",
            downloadURL: nil,
            sha256: nil,
            version: "0",
            license: "Gemma",
            contextLength: 32_768,
            capabilities: LocalModelCapabilities(vision: true, audio: true, reasoning: false, multilingual: true),
            runtimeProfile: .chatmlInstruct,
            minimumRecommendedRAMGB: 8,
            estimatedRuntimeMemoryGB: 5.4,
            compatibilityIPhone14Plus: .notRecommended,
            compatibilityNote: "Étudié seulement. Q4_0 officiel ~3,35 Go + mmproj 0,34–0,99 Go. Pas équivalent mémoire à Qwen3.5 2B (1,18+0,64 Go). Non téléchargeable.",
            statusNote: "Expérimental interne — hors UI",
            mmproj: nil
        ),
    ]

    static func descriptor(id: String) -> LocalModelDescriptor? {
        catalog.first { $0.id == id } ?? experimentalInternal.first { $0.id == id }
    }

    static var downloadable: [LocalModelDescriptor] {
        catalog.filter(\.isDownloadable)
    }
}
