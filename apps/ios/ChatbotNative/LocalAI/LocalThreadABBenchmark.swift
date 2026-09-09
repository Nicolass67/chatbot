import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Mesure isolée threads 2 vs 4. Ne touche pas `LlamaInferenceConfig.a15Default`
/// ni l’ExecutionProfile de production. Restaure les threads d’origine en `defer`.
struct LocalThreadABRun: Codable, Equatable, Sendable {
    var threads: Int32
    var repetition: Int
    var warmup: Bool
    var success: Bool
    var errorMessage: String?
    var timeToFirstTokenMs: Double?
    var tokensPerSecond: Double?
    var promptEvalMs: Double?
    var promptTokens: Int
    var generatedTokens: Int
    var totalMs: Double?
    var residentMemoryBytes: UInt64?
    var thermalState: String
    var nCtx: UInt32?
    var nBatch: UInt32?
    var nUbatch: UInt32?
}

struct LocalThreadABReport: Codable, Equatable, Sendable {
    var modelId: String
    var quant: String
    var deviceModel: String
    var appVersion: String
    var gdn: LlamaGdnProbeObservation
    var backendEffective: String?
    var productionThreads: Int32
    var productionThreadsBatch: Int32
    var promptLabel: String
    var maxTokens: Int
    var repetitions: Int
    var energyNote: String
    var temperatureNote: String
    var runs: [LocalThreadABRun]
    var ranAt: Date

    var explicitSummary: String {
        func med(_ threads: Int32, _ key: (LocalThreadABRun) -> Double?) -> String {
            let vals = runs.filter { $0.threads == threads && !$0.warmup && $0.success }
                .compactMap(key)
            guard !vals.isEmpty else { return "—" }
            let s = vals.sorted()
            let m = s[s.count / 2]
            return String(format: "%.1f", m)
        }
        let t2 = runs.filter { $0.threads == 2 && !$0.warmup }
        let t4 = runs.filter { $0.threads == 4 && !$0.warmup }
        return [
            "[local-ai:thread-ab] report model=\(modelId) device=\(deviceModel)",
            "productionThreads=\(productionThreads)/\(productionThreadsBatch)",
            "gdn probe=\(gdn.probe) ar=\(gdn.fusedAR) ch=\(gdn.fusedCH) auto=\(gdn.autoFgdn)",
            "threads=2 n=\(t2.count) TTFT_med_ms=\(med(2) { $0.timeToFirstTokenMs }) tok_s_med=\(med(2) { $0.tokensPerSecond }) total_med_ms=\(med(2) { $0.totalMs })",
            "threads=4 n=\(t4.count) TTFT_med_ms=\(med(4) { $0.timeToFirstTokenMs }) tok_s_med=\(med(4) { $0.tokensPerSecond }) total_med_ms=\(med(4) { $0.totalMs })",
            "energy=\(energyNote)",
            "thermal=\(temperatureNote)",
        ].joined(separator: "\n")
    }

    /// Résumé lisible pour la feuille Tester (sans dump syslog).
    var userFacingSummary: String {
        func med(_ threads: Int32, _ key: (LocalThreadABRun) -> Double?) -> String {
            let vals = runs.filter { $0.threads == threads && !$0.warmup && $0.success }
                .compactMap(key)
            guard !vals.isEmpty else { return "—" }
            let s = vals.sorted()
            let m = s[s.count / 2]
            return String(format: "%.1f", m)
        }
        let t2 = runs.filter { $0.threads == 2 && !$0.warmup && $0.success }
        let t4 = runs.filter { $0.threads == 4 && !$0.warmup && $0.success }
        if t2.isEmpty && t4.isEmpty {
            return "Aucune mesure. Le modèle n’était pas chargé, ou la génération a échoué."
        }
        return [
            "Threads 2 : \(med(2) { $0.tokensPerSecond }) tok/s · TTFT \(med(2) { $0.timeToFirstTokenMs }) ms · \(t2.count) mesure\(t2.count > 1 ? "s" : "")",
            "Threads 4 : \(med(4) { $0.tokensPerSecond }) tok/s · TTFT \(med(4) { $0.timeToFirstTokenMs }) ms · \(t4.count) mesure\(t4.count > 1 ? "s" : "")",
            "Le profil de production (\(productionThreads) threads) n’a pas été modifié.",
        ].joined(separator: "\n")
    }
}

enum LocalDeviceThermal {
    static func label() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

@MainActor
enum LocalThreadABBenchmark {
    static let promptLabel = "kv_cache_detail_fr"
    static let userPrompt = """
    Explique en détail, en français, le fonctionnement d’un cache KV dans un modèle de langage. \
    Donne une définition, le rôle pendant le préfill, le rôle pendant le decode, et pourquoi la \
    mémoire croît avec le contexte. Vise environ 180 mots, sans liste d’outils.
    """
    static let maxTokens = 192
    static let measuredReps = 3

    private static let reportFileName = "thread-ab-latest.json"

    /// Attend un modèle déjà chargé (ou auto-load local) puis lance la mesure isolée.
    @discardableResult
    static func waitAndRun(source: String) async -> LocalThreadABReport {
        let models = LocalModelManager.shared
        if !models.isReady {
            models.requestAutoLoadIfNeeded(wantsLocalExecution: true)
        }
        for _ in 0..<45 {
            if models.isReady { break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return await runIsolated(source: source)
    }

    /// Source : tester Settings ou deep link `chatbot-native://qa/local-ai/thread-ab`.
    @discardableResult
    static func runIsolated(source: String) async -> LocalThreadABReport {
        let models = LocalModelManager.shared
        let desc = models.activeDescriptor
        let infer = desc.executionProfile.inference
        let gdn = (await LocalInferenceEngine.shared.lastLoadDiagnostics)?.gdn ?? .unknown
        print("[local-ai:thread-ab] start source=\(source) ready=\(models.isReady) model=\(desc.id)")
        print(gdn.explicitReport)

        let productionT = await LocalInferenceEngine.shared.currentThreads()
        let restoreT = productionT?.threads
            ?? LlamaInferenceConfig.resolvedThreads(explicit: infer.nThreads)
        let restoreB = productionT?.batch
            ?? LlamaInferenceConfig.resolvedThreads(explicit: infer.nThreadsBatch ?? infer.nThreads)

        var report = LocalThreadABReport(
            modelId: desc.id,
            quant: desc.quant,
            deviceModel: LocalModelBenchmarkSuite.deviceModelLabel,
            appVersion: LocalModelBenchmarkSuite.appVersionLabel,
            gdn: gdn,
            backendEffective: await LocalInferenceEngine.shared.lastLoadDiagnostics?.backendEffective,
            productionThreads: restoreT,
            productionThreadsBatch: restoreB,
            promptLabel: promptLabel,
            maxTokens: maxTokens,
            repetitions: measuredReps,
            energyNote: "non mesurable depuis l’app (pas d’API publique joules/mW en live)",
            temperatureNote: "ProcessInfo.thermalState seulement (pas de °C CPU/GPU)",
            runs: [],
            ranAt: Date()
        )

        guard models.isReady else {
            print("[local-ai:thread-ab] abort modèle non chargé")
            persist(report)
            print(report.explicitSummary)
            return report
        }

        do {
            // 2 puis 4 : une seule variable. Même GGUF, ctx, batch, sampler, prompt.
            report.runs += await runBlock(threads: 2)
            try await Task.sleep(nanoseconds: 3_000_000_000)
            report.runs += await runBlock(threads: 4)
        } catch {
            print("[local-ai:thread-ab] interrupted \(error.localizedDescription)")
        }

        await LocalInferenceEngine.shared.setThreads(restoreT, batch: restoreB)
        persist(report)
        print(report.explicitSummary)
        if let json = try? JSONEncoder().encode(report), let text = String(data: json, encoding: .utf8) {
            print("[local-ai:thread-ab] json=\(text)")
        }
        return report
    }

    private static func runBlock(threads: Int32) async -> [LocalThreadABRun] {
        await LocalInferenceEngine.shared.setThreads(threads, batch: threads)
        var out: [LocalThreadABRun] = []
        out.append(await oneRun(threads: threads, repetition: 0, warmup: true))
        for i in 1...measuredReps {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            out.append(await oneRun(threads: threads, repetition: i, warmup: false))
        }
        return out
    }

    private static func oneRun(threads: Int32, repetition: Int, warmup: Bool) async -> LocalThreadABRun {
        let models = LocalModelManager.shared
        let desc = models.activeDescriptor
        let infer = desc.executionProfile.inference
        let mem = LocalModelComparisonMemory.residentBytes()
        let thermal = LocalDeviceThermal.label()
        let result = await LocalModelBenchmarkRunner.runPrompt(
            label: "\(promptLabel)-t\(threads)-r\(repetition)\(warmup ? "-wu" : "")",
            prompt: userPrompt,
            maxTokens: maxTokens
        )
        let run = LocalThreadABRun(
            threads: threads,
            repetition: repetition,
            warmup: warmup,
            success: result.success,
            errorMessage: result.errorMessage,
            timeToFirstTokenMs: result.timeToFirstTokenMs,
            tokensPerSecond: result.tokensPerSecond,
            promptEvalMs: result.promptEvalMs,
            promptTokens: result.promptTokens,
            generatedTokens: result.generatedTokens,
            totalMs: result.totalMs,
            residentMemoryBytes: mem,
            thermalState: thermal,
            nCtx: result.nCtx ?? infer.nCtx,
            nBatch: result.nBatch ?? infer.nBatch,
            nUbatch: infer.nUbatch
        )
        print(
            String(
                format: "[local-ai:thread-ab] t=%d rep=%d warmup=%@ ok=%@ TTFT=%.0fms tok/s=%.2f gen=%d total=%.0fms mem=%@ thermal=%@",
                threads,
                repetition,
                warmup ? "yes" : "no",
                result.success ? "yes" : "no",
                result.timeToFirstTokenMs ?? -1,
                result.tokensPerSecond ?? -1,
                result.generatedTokens,
                result.totalMs ?? -1,
                mem.map { String($0) } ?? "na",
                thermal
            )
        )
        if let err = result.errorMessage, !result.success {
            print("[local-ai:thread-ab] error=\(err)")
        }
        return run
    }

    private static func persist(_ report: LocalThreadABReport) {
        guard let json = try? JSONEncoder().encode(report) else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LocalRuntimeMeasures", isDirectory: true)
        guard let dir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(reportFileName)
        try? json.write(to: url, options: .atomic)
    }
}
