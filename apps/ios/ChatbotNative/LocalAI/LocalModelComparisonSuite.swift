import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Résultat d’un test de comparaison (debug Settings). Pas d’auto-switch de modèle.
struct LocalModelComparisonResult: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var modelId: String
    var displayName: String
    var testId: String
    var testTitle: String
    var thinkingEnabled: Bool
    var loadDurationMs: Double?
    var timeToFirstTokenMs: Double?
    var tokensPerSecond: Double?
    var generatedTokens: Int
    var totalMs: Double?
    var residentMemoryBytes: UInt64?
    var success: Bool
    var skipped: Bool
    var skipReason: String?
    var errorMessage: String?
    var outputPreview: String
    var ranAt: Date
}

enum LocalModelComparisonCase: String, CaseIterable, Identifiable, Sendable {
    case simple
    case reasoning
    case constraints
    case french
    case summary
    case document
    case vision
    case visionReasoning
    case web
    case mail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Réponse simple"
        case .reasoning: return "Raisonnement"
        case .constraints: return "Instruction complexe"
        case .french: return "Français naturel"
        case .summary: return "Résumé"
        case .document: return "Extraction document"
        case .vision: return "Vision"
        case .visionReasoning: return "Vision + raisonnement"
        case .web: return "Recherche Web"
        case .mail: return "Mail"
        }
    }
}

enum LocalModelComparisonMemory {
    static func residentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return info.resident_size
    }
}

enum LocalModelComparisonFixtures {
    static let longSummarySource = """
    Le comité s’est réuni mardi. Marie a présenté le budget 2026 : 48 000 € de fonctionnement, \
    12 500 € de matériel, et une réserve de 6 000 €. Julien a signalé un retard sur la livraison \
    des écrans (semaine 14 au lieu de la semaine 11). Camille proposait de reporter l’atelier \
    formation au 3 avril, 14 h, salle B. Décisions : valider le budget hors réserve, commander \
    les écrans chez l’autre fournisseur si le retard dépasse cinq jours, confirmer l’atelier \
    au 3 avril. Prochaine réunion le 21 mars à 9 h 30. Personne à prévenir : service RH et \
    le prestataire réseau.
    """

    static let mailToRewrite = """
    Objet : Point projet
    Bonjour,
    Suite à notre échange, pourriez-vous me confirmer la date de livraison ainsi que le \
    contact technique ? Merci d’avance.
    Cordialement,
    Paul
    """

    static func firstPDFExcerpt(maxChars: Int) -> (name: String, text: String)? {
        let roots = [LocalFilesStore.documentsRootId, LocalFilesStore.inboxRootId]
        for root in roots {
            guard let hit = firstPDF(rootId: root, relative: "", depth: 0) else { continue }
            guard let text = LocalDocumentExtractor.extract(fileId: hit.fileId, maxChars: maxChars),
                  text.count > 40 else { continue }
            return (hit.name, text)
        }
        return nil
    }

    private static func firstPDF(rootId: String, relative: String, depth: Int) -> (fileId: String, name: String)? {
        guard depth < 3 else { return nil }
        guard let list = try? LocalFilesStore.list(relativePath: relative, rootId: rootId) else { return nil }
        for entry in list.entries {
            let name = (entry.name ?? entry.relativePath).lowercased()
            if entry.isDirectory == true {
                if let nested = firstPDF(rootId: rootId, relative: entry.relativePath, depth: depth + 1) {
                    return nested
                }
                continue
            }
            if name.hasSuffix(".pdf"), let fileId = entry.fileId {
                return (fileId, entry.name ?? entry.relativePath)
            }
        }
        return nil
    }
}

@MainActor
final class LocalModelComparisonStore: ObservableObject {
    static let shared = LocalModelComparisonStore()
    private static let defaultsKey = "localAI.comparisonResults.v1"

    @Published private(set) var resultsByModel: [String: [LocalModelComparisonResult]] = [:]

    init() {
        load()
    }

    func replace(modelId: String, results: [LocalModelComparisonResult]) {
        resultsByModel[modelId] = results
        persist()
    }

    func results(for modelId: String) -> [LocalModelComparisonResult] {
        resultsByModel[modelId] ?? []
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [LocalModelComparisonResult]].self, from: data)
        else { return }
        resultsByModel = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(resultsByModel) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Exécute la suite sur le modèle **déjà chargé**. Aucun changement automatique de GGUF.
@MainActor
enum LocalModelComparisonRunner {
    static func runSuite(thinkingEnabled: Bool) async -> [LocalModelComparisonResult] {
        var out: [LocalModelComparisonResult] = []
        for test in LocalModelComparisonCase.allCases {
            out.append(await run(test, thinkingEnabled: thinkingEnabled))
        }
        let models = LocalModelManager.shared
        LocalModelComparisonStore.shared.replace(modelId: models.activeModelId, results: out)
        return out
    }

    static func run(
        _ test: LocalModelComparisonCase,
        thinkingEnabled: Bool
    ) async -> LocalModelComparisonResult {
        let models = LocalModelManager.shared
        let desc = models.activeDescriptor
        let started = Date()
        let memory = LocalModelComparisonMemory.residentBytes()
        let loadMs = (await LocalInferenceEngine.shared.lastMetrics.loadDuration).map { $0 * 1000 }

        func finished(
            success: Bool,
            skipped: Bool = false,
            skipReason: String? = nil,
            error: String? = nil,
            preview: String,
            metrics: LocalInferenceMetrics = .empty
        ) -> LocalModelComparisonResult {
            LocalModelComparisonResult(
                id: "\(desc.id)-\(test.id)-\(started.timeIntervalSince1970)",
                modelId: desc.id,
                displayName: desc.displayName,
                testId: test.id,
                testTitle: test.title,
                thinkingEnabled: thinkingEnabled,
                loadDurationMs: loadMs,
                timeToFirstTokenMs: metrics.timeToFirstToken.map { $0 * 1000 },
                tokensPerSecond: metrics.tokensPerSecond,
                generatedTokens: metrics.generatedTokens,
                totalMs: metrics.totalSeconds.map { $0 * 1000 } ?? Date().timeIntervalSince(started) * 1000,
                residentMemoryBytes: memory,
                success: success,
                skipped: skipped,
                skipReason: skipReason,
                errorMessage: error,
                outputPreview: String(preview.prefix(400)),
                ranAt: started
            )
        }

        func applyPayload(_ payload: ComparisonRunPayload) -> LocalModelComparisonResult {
            finished(
                success: payload.success,
                error: payload.error,
                preview: payload.preview,
                metrics: payload.metrics
            )
        }

        guard models.isReady else {
            return finished(success: false, error: "Modèle non chargé.", preview: "")
        }

        switch test {
        case .web:
            return finished(
                success: false,
                skipped: true,
                skipReason: "Pas de SearXNG local — la recherche Web n’est pas disponible en mode 100 % local.",
                preview: ""
            )
        case .document:
            guard let pdf = LocalModelComparisonFixtures.firstPDFExcerpt(maxChars: 2_400) else {
                return finished(
                    success: false,
                    skipped: true,
                    skipReason: "Aucun PDF trouvé dans Fichiers de l’app.",
                    preview: ""
                )
            }
            return await generateText(
                system: "Tu extraits les informations importantes d’un document. Réponds en français, structuré.",
                user: "Document « \(pdf.name) » :\n\n\(pdf.text)\n\nDonne-moi les informations importantes de ce document.",
                maxTokens: 384,
                thinkingEnabled: thinkingEnabled
            ).then(applyPayload)
        case .vision:
            guard models.isVisionProjectorInstalled else {
                return finished(
                    success: false,
                    skipped: true,
                    skipReason: "Pack vision non installé pour \(desc.displayName).",
                    preview: ""
                )
            }
            guard let jpeg = LocalVision.labeledJPEG(
                title: "Note interne",
                lines: ["Couleur dominante : rouge", "Code : ZX-14", "Lieu : Salle B"]
            ) else {
                return finished(success: false, error: "Image de test impossible.", preview: "")
            }
            return await generateVision(
                system: "Tu es un assistant visuel. Décris précisément et lis le texte visible.",
                user: "Décris précisément ce que tu vois et lis le texte visible.",
                jpeg: jpeg,
                maxTokens: 192
            ).then(applyPayload)
        case .visionReasoning:
            guard models.isVisionProjectorInstalled else {
                return finished(
                    success: false,
                    skipped: true,
                    skipReason: "Pack vision non installé pour \(desc.displayName).",
                    preview: ""
                )
            }
            guard let jpeg = LocalVision.labeledJPEG(
                title: "Facture 204",
                lines: [
                    "Article A : 40 €",
                    "Article B : 25 €",
                    "Remise : 10 %",
                    "Total HT à calculer",
                ]
            ) else {
                return finished(success: false, error: "Image de test impossible.", preview: "")
            }
            return await generateVision(
                system: "Tu lis des documents visuels et tu interprètes les chiffres. Réponds en français.",
                user: "Interprète cette image : quels articles, quels montants, quel total après remise ?",
                jpeg: jpeg,
                maxTokens: 256
            ).then(applyPayload)
        case .simple:
            return await generateText(
                system: "Tu réponds en français, clairement, sans digression.",
                user: "Explique en 3 phrases pourquoi le ciel est bleu.",
                maxTokens: 220,
                thinkingEnabled: thinkingEnabled
            ).then(applyPayload)
        case .reasoning:
            return await generateText(
                system: "Tu résous des problèmes pas à pas, puis tu donnes le résultat final.",
                user: "Un article coûte 80 €. Il augmente de 25 %, puis baisse de 20 %. Quel est le prix final ? Explique.",
                maxTokens: 280,
                thinkingEnabled: thinkingEnabled
            ).then(applyPayload)
        case .constraints:
            return await generateText(
                system: "Tu respectes strictement les contraintes demandées.",
                user: """
                Réponds avec exactement 4 lignes :
                1) un verbe à l’infinitif
                2) un nombre entre 10 et 20
                3) une ville française
                4) le mot « ok » en minuscules
                N’ajoute rien d’autre.
                """,
                maxTokens: 120,
                thinkingEnabled: thinkingEnabled
            ).then(applyPayload)
        case .french:
            return await generateText(
                system: "Tu réécris en français naturel, professionnel mais pas trop formel.",
                user: """
                Réécris ce message de manière naturelle, professionnelle mais pas trop formelle :

                \(LocalModelComparisonFixtures.mailToRewrite)
                """,
                maxTokens: 220,
                thinkingEnabled: thinkingEnabled
            ).then(applyPayload)
        case .summary:
            return await generateText(
                system: "Tu produis des résumés structurés en français.",
                user: "Résume ce texte en 4 puces (décisions, dates, montants, personnes) :\n\n\(LocalModelComparisonFixtures.longSummarySource)",
                maxTokens: 280,
                thinkingEnabled: thinkingEnabled
            ).then(applyPayload)
        case .mail:
            return await generateText(
                system: "Tu rédiges des réponses mail naturelles, concises, pas trop formelles.",
                user: """
                Mail reçu :
                \(LocalModelComparisonFixtures.mailToRewrite)

                Réponds de manière naturelle, concise et pas trop formelle.
                """,
                maxTokens: 220,
                thinkingEnabled: thinkingEnabled
            ).then(applyPayload)
        }
    }

    private static func generateText(
        system: String,
        user: String,
        maxTokens: Int,
        thinkingEnabled: Bool
    ) async -> ComparisonRunPayload {
        let models = LocalModelManager.shared
        var template = models.activeDescriptor.runtimeProfile
        template.enableThinking = thinkingEnabled
        let prompt = LocalChatTemplate.buildPrompt(system: system, user: user, profile: template)
        let acc = ComparisonStringAccumulator()
        do {
            try await LocalInferenceEngine.shared.generate(prompt: prompt, maxTokens: maxTokens) { piece in
                acc.append(piece)
                let cut = LocalChatTemplate.truncateAssistantOutput(acc.value, profile: template)
                acc.replace(with: cut.text)
                if cut.hitStop {
                    await LocalInferenceEngine.shared.cancel()
                }
            }
        } catch {
            let metrics = await LocalInferenceEngine.shared.lastMetrics
            let preview = LocalChatTemplate.truncateAssistantOutput(acc.value, profile: template).text
            return ComparisonRunPayload(
                success: false, error: error.localizedDescription, preview: preview, metrics: metrics
            )
        }
        let clean = LocalChatTemplate.truncateAssistantOutput(acc.value, profile: template).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metrics = await LocalInferenceEngine.shared.lastMetrics
        return ComparisonRunPayload(
            success: !clean.isEmpty,
            error: clean.isEmpty ? "Sortie vide" : nil,
            preview: clean,
            metrics: metrics
        )
    }

    private static func generateVision(
        system: String,
        user: String,
        jpeg: Data,
        maxTokens: Int
    ) async -> ComparisonRunPayload {
        var output = ""
        do {
            let text = try await LocalAIRuntime.shared.generateStream(
                system: system,
                messages: [LLMChatMessage(role: .user, content: user)],
                maxTokens: maxTokens,
                images: [jpeg],
                onToken: { token in output += token }
            )
            output = LocalChatTemplate.truncateAssistantOutput(
                text,
                profile: LocalModelManager.shared.activeRuntimeProfile
            ).text
        } catch {
            let metrics = await LocalInferenceEngine.shared.lastMetrics
            return ComparisonRunPayload(
                success: false, error: error.localizedDescription, preview: output, metrics: metrics
            )
        }
        let metrics = await LocalInferenceEngine.shared.lastMetrics
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return ComparisonRunPayload(
            success: !clean.isEmpty,
            error: clean.isEmpty ? "Sortie vide" : nil,
            preview: clean,
            metrics: metrics
        )
    }
}

private struct ComparisonRunPayload {
    var success: Bool
    var error: String?
    var preview: String
    var metrics: LocalInferenceMetrics

    func then(_ finish: (ComparisonRunPayload) -> LocalModelComparisonResult) -> LocalModelComparisonResult {
        finish(self)
    }
}

private final class ComparisonStringAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    var value: String {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    func append(_ piece: String) {
        lock.lock(); defer { lock.unlock() }
        buffer += piece
    }

    func replace(with text: String) {
        lock.lock(); defer { lock.unlock() }
        buffer = text
    }
}
