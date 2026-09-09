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
    let sha256: String?

    var expectedSizeLabel: String {
        LocalModelByteLabel.binary(expectedBytes)
    }

    var userFacingSizeLabel: String {
        LocalModelByteLabel.decimal(expectedBytes)
    }

    /// Accepte `mmproj-*.gguf` (Qwen) et `*-mmproj.gguf` (Gemma 4). Jamais le GGUF texte.
    func isValidCompanion(ofTextFilename textFilename: String) -> Bool {
        let lower = filename.lowercased()
        guard lower.contains("mmproj") else { return false }
        guard filename != textFilename else { return false }
        return true
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
        LocalModelByteLabel.binary(expectedBytes)
    }

    var estimatedRAMLabel: String {
        String(format: "~%.1f Go RAM", estimatedRuntimeMemoryGB)
    }

    var userFacingBlurb: String {
        switch id {
        case "qwen35-2b-q4_k_m":
            return "Recommandé — polyvalent et rapide au quotidien."
        case "qwen3-1.7b-q4_k_m":
            return "Très léger — réponses plus rapides."
        case "lfm25-1.2b-instruct-q4_k_m":
            return "Ultra compact — le plus économe."
        case "gemma4-e2b-it-q4_0":
            return "Plus puissant, plus lourd."
        default:
            return "Utilisable hors ligne sur cet iPhone."
        }
    }

    var family: String {
        switch architecture {
        case "qwen3", "qwen35": return "qwen"
        case "gemma4", "gemma": return "gemma"
        case "lfm2": return "lfm"
        case "granite": return "granite"
        case "phi3": return "phi"
        default: return architecture
        }
    }

    var modelURL: URL? { downloadURL }
    var modelFilename: String { filename }
    var mmprojURL: URL? { mmproj?.downloadURL }
    var mmprojFilename: String? { mmproj?.filename }
    var mmprojExpectedBytes: Int64? { mmproj?.expectedBytes }
    var mmprojSHA256: String? { mmproj?.sha256 }

    var userFacingTextSizeLabel: String { LocalModelByteLabel.decimal(expectedBytes) }
    var userFacingVisionSizeLabel: String? {
        guard let mmproj else { return nil }
        return LocalModelByteLabel.decimal(mmproj.expectedBytes)
    }
    var userFacingPackSizeLabel: String {
        LocalModelByteLabel.decimal(expectedBytes + (mmproj?.expectedBytes ?? 0))
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
                compatibilityNote: "Même dépôt que le GGUF texte (projection_dim 2048 = embedding 2048, clip.projector_type=qwen3vl_merger). Ne pas substituer le Q4_K_M bartowski (~1,40 Go, MTP).",
                sha256: nil
            )
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
            downloadURL: URL(string: "https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/resolve/main/gemma-4-E2B_q4_0-it.gguf"),
            sha256: "fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634",
            version: "1.0",
            license: "Gemma",
            contextLength: 131_072,
            capabilities: LocalModelCapabilities(vision: true, audio: false, reasoning: true, multilingual: true),
            runtimeProfile: .gemma4E2B,
            minimumRecommendedRAMGB: 8,
            estimatedRuntimeMemoryGB: 5.2,
            compatibilityIPhone14Plus: .experimental,
            compatibilityNote: "Candidat expérimental. Plus lourd que Qwen3.5 2B (~3,35 Go texte + ~987 Mo vision). Qwen reste le modèle recommandé et n’est jamais remplacé automatiquement.",
            statusNote: "Expérimental",
            mmproj: LocalMmprojDescriptor(
                filename: "gemma-4-E2B-it-mmproj.gguf",
                downloadURL: URL(string: "https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/resolve/main/gemma-4-E2B-it-mmproj.gguf")!,
                expectedBytes: 986_833_664,
                quant: "BF16",
                sourceRepo: "google/gemma-4-E2B-it-qat-q4_0-gguf",
                compatibilityNote: "Projecteur Gemma 4 (gemma4v) du dépôt officiel Google. Ne jamais mélanger avec mmproj-Qwen3.5-2B-BF16.gguf.",
                sha256: "021059cce659fe7f9170d5599761d7bbaf644b798dab9503aca30dc43e6beb14"
            )
        ),
    ]

    /// Ordre Settings : référence Qwen3.5, puis Gemma expérimental, puis légers.
    static let userFacingCatalogOrder: [String] = [
        "qwen35-2b-q4_k_m",
        "gemma4-e2b-it-q4_0",
        "lfm25-1.2b-instruct-q4_k_m",
        "qwen3-1.7b-q4_k_m",
    ]

    static var userFacingCatalog: [LocalModelDescriptor] {
        userFacingCatalogOrder
            .compactMap { descriptor(id: $0) }
            .filter { catalog.contains($0) && $0.isDownloadable }
    }

    /// Hors UI utilisateur : trop lourds ou pas encore téléchargeables (Gemma 4 E4B, etc.).
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
            id: "gemma4-e4b-it",
            displayName: "Gemma 4 E4B",
            provider: "Google",
            architecture: "gemma4",
            parameterCountLabel: "E4B",
            quant: "Q4_0",
            expectedBytes: 0,
            filename: "gemma-4-E4B_q4_0-it.gguf",
            downloadURL: nil,
            sha256: nil,
            version: "0",
            license: "Gemma",
            contextLength: 131_072,
            capabilities: LocalModelCapabilities(vision: true, audio: false, reasoning: true, multilingual: true),
            runtimeProfile: .gemma4E2B,
            minimumRecommendedRAMGB: 12,
            estimatedRuntimeMemoryGB: 8.5,
            compatibilityIPhone14Plus: .notRecommended,
            compatibilityNote: "Beaucoup trop lourd pour iPhone 14 Plus / 6 Go. Hors catalogue utilisateur — pas de téléchargement.",
            statusNote: "Hors UI — futur uniquement",
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

/// Libellés de taille : binaire (validation) vs décimal (UX, aligné Hugging Face).
enum LocalModelByteLabel {
    static func binary(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1 {
            return String(format: "%.2f Go", gb)
        }
        return String(format: "%.0f Mo", Double(bytes) / 1_048_576.0)
    }

    static func decimal(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        if bytes >= 1_000_000_000 {
            let gb = Double(bytes) / 1_000_000_000.0
            return String(format: "%.2f Go", gb).replacingOccurrences(of: ".", with: ",")
        }
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.0f Mo", mb)
    }
}
