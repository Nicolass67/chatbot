import Foundation

/// Suite Vision commune — mêmes images et mêmes prompts pour tous les modèles.
/// Aucun benchmark automatique : lancée uniquement depuis le Tester.
enum LocalVisionProbeCase: String, CaseIterable, Identifiable, Sendable {
    case simpleImage
    case screenshot
    case document
    case ocr
    case table
    case visualQuestion
    case visualReasoning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simpleImage: return "Image simple"
        case .screenshot: return "Capture d’écran"
        case .document: return "Document"
        case .ocr: return "OCR"
        case .table: return "Tableau"
        case .visualQuestion: return "Question visuelle"
        case .visualReasoning: return "Raisonnement visuel"
        }
    }

    var prompt: String {
        switch self {
        case .simpleImage:
            return "Quelle couleur domine cette image ? Réponds en une phrase."
        case .screenshot:
            return "Décris cette capture d’écran en une phrase : écran, titre, action principale."
        case .document:
            return "Quel est le sujet de ce document ? Réponds en une phrase."
        case .ocr:
            return "Transcris exactement tout le texte visible."
        case .table:
            return "Quel est le total TTC indiqué dans le tableau ?"
        case .visualQuestion:
            return "Combien de boutons vois-tu dans cette interface ?"
        case .visualReasoning:
            return "Combien font 3 pommes plus 2 pommes ? Réponds par un nombre, en t’appuyant sur l’image."
        }
    }

    func jpeg() -> Data? {
        switch self {
        case .simpleImage:
            return LocalVision.solidColorJPEG(red: 0.86, green: 0.12, blue: 0.12, size: 96)
        case .screenshot:
            return LocalVision.labeledJPEG(
                title: "Réglages",
                lines: ["Wi-Fi                    Activé", "Bluetooth               Désactivé", "Mode avion                  Off"],
                width: 512,
                height: 384
            )
        case .document:
            return LocalVision.labeledJPEG(
                title: "Note interne",
                lines: [
                    "Objet : revue du 21 mars",
                    "Valider le budget hors réserve.",
                    "Reporter l’atelier au 3 avril.",
                ],
                width: 512,
                height: 384
            )
        case .ocr:
            return LocalVision.labeledJPEG(
                title: "FACTURE 2024",
                lines: ["Client : Atelier Nord", "Réf : INV-8841", "Total 128,50 EUR"],
                width: 512,
                height: 360
            )
        case .table:
            return LocalVision.labeledJPEG(
                title: "Commande",
                lines: ["Article          Qté     HT", "Écran            2    400 €", "Total TTC           480 €"],
                width: 512,
                height: 360
            )
        case .visualQuestion:
            return LocalVision.labeledJPEG(
                title: "Accueil",
                lines: ["[ Chat ]     [ Mail ]", "[ Fichiers ]  [ Réglages ]"],
                width: 512,
                height: 320
            )
        case .visualReasoning:
            return LocalVision.labeledJPEG(
                title: "Fruits",
                lines: ["Pommes à gauche : 3", "Pommes à droite : 2", "Combien en tout ?"],
                width: 512,
                height: 360
            )
        }
    }
}

struct LocalVisionProbeResult: Equatable, Sendable, Identifiable {
    var id: String { testId }
    var testId: String
    var title: String
    var success: Bool
    var timeToFirstTokenMs: Double?
    var tokensPerSecond: Double?
    var totalMs: Double?
    var promptTokens: Int
    var generatedTokens: Int
    var residentMemoryBytes: UInt64?
    var nCtx: UInt32?
    var outputPreview: String
    var errorMessage: String?
}

enum LocalVisionProbeRunner {
    @MainActor
    static func run(
        cases: [LocalVisionProbeCase] = LocalVisionProbeCase.allCases,
        onProgress: ((LocalVisionProbeResult) -> Void)? = nil
    ) async -> [LocalVisionProbeResult] {
        var results: [LocalVisionProbeResult] = []
        let profile = LocalModelManager.shared.activeDescriptor.executionProfile
        let nCtx = profile.inference.nCtx
        for probe in cases {
            let result = await runOne(probe, nCtx: nCtx)
            results.append(result)
            onProgress?(result)
            if Task.isCancelled { break }
        }
        return results
    }

    @MainActor
    private static func runOne(_ probe: LocalVisionProbeCase, nCtx: UInt32) async -> LocalVisionProbeResult {
        func pack(
            success: Bool,
            metrics: LocalInferenceMetrics,
            preview: String,
            error: String?
        ) -> LocalVisionProbeResult {
            LocalVisionProbeResult(
                testId: probe.id,
                title: probe.title,
                success: success,
                timeToFirstTokenMs: metrics.timeToFirstToken.map { $0 * 1000 },
                tokensPerSecond: metrics.tokensPerSecond,
                totalMs: metrics.totalSeconds.map { $0 * 1000 },
                promptTokens: metrics.promptTokens,
                generatedTokens: metrics.generatedTokens,
                residentMemoryBytes: LocalModelComparisonMemory.residentBytes(),
                nCtx: nCtx,
                outputPreview: String(preview.prefix(280)),
                errorMessage: error
            )
        }

        guard let jpeg = probe.jpeg() else {
            return pack(success: false, metrics: .empty, preview: "", error: "Image de test indisponible.")
        }
        do {
            let text = try await LocalAIRuntime.shared.generateStream(
                system: "Tu es un assistant visuel. Réponds de façon concise.",
                messages: [LLMChatMessage(role: .user, content: probe.prompt)],
                maxTokens: 96,
                images: [jpeg],
                onToken: { _ in }
            )
            let metrics = await LocalInferenceEngine.shared.lastMetrics
            let cleaned = LocalChatTemplate.stripControlTokens(
                text,
                profile: LocalModelManager.shared.activeRuntimeProfile
            )
            return pack(success: true, metrics: metrics, preview: cleaned, error: nil)
        } catch {
            let metrics = await LocalInferenceEngine.shared.lastMetrics
            return pack(
                success: false,
                metrics: metrics,
                preview: "",
                error: error.localizedDescription
            )
        }
    }
}
