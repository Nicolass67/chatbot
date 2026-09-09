import Foundation

/// Erreurs d’inférence locale (indépendante de LM Studio PC).
enum LocalInferenceError: Error, LocalizedError, Sendable {
    case notAvailable
    case modelMissing
    case notLoaded
    case loadFailed(String)
    case outOfMemory
    case cancelled
    case generatingFailed(String)
    case contextTooLarge

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Le runtime llama.cpp n’est pas disponible dans ce build."
        case .modelMissing:
            return "Modèle GGUF introuvable. Installez-le d’abord."
        case .notLoaded:
            return "Modèle non chargé en mémoire. Appuyez sur Charger."
        case .loadFailed(let detail):
            return "Échec de chargement du modèle : \(detail)"
        case .outOfMemory:
            return "Mémoire insuffisante pour charger le modèle. Fermez d’autres apps et réessayez."
        case .cancelled:
            return "Génération annulée."
        case .generatingFailed(let detail):
            return "Échec de génération : \(detail)"
        case .contextTooLarge:
            return "Le contexte de cette recherche est trop volumineux. Je réduis automatiquement les résultats."
        }
    }
}

struct LocalInferenceMetrics: Sendable, Equatable, Codable {
    var loadDuration: TimeInterval?
    var promptEvalSeconds: TimeInterval?
    var timeToFirstToken: TimeInterval?
    var generationSeconds: TimeInterval?
    var totalSeconds: TimeInterval?
    var promptTokens: Int
    var generatedTokens: Int
    var promptTokensPerSecond: Double?
    var tokensPerSecond: Double?
    var cancellationLatencyMs: Double?
    var peakMemoryBytesHint: UInt64?
    var backendEffective: String?
    var nGpuLayersConfigured: Int32?

    static let empty = LocalInferenceMetrics(
        loadDuration: nil,
        promptEvalSeconds: nil,
        timeToFirstToken: nil,
        generationSeconds: nil,
        totalSeconds: nil,
        promptTokens: 0,
        generatedTokens: 0,
        promptTokensPerSecond: nil,
        tokensPerSecond: nil,
        cancellationLatencyMs: nil,
        peakMemoryBytesHint: nil,
        backendEffective: nil,
        nGpuLayersConfigured: nil
    )
}

/// Moteur d’inférence locale — encapsule `LlamaContext` derrière `#if canImport(llama)`.
actor LocalInferenceEngine {
    static let shared = LocalInferenceEngine()

    private var isLoaded = false
    private var loadedPath: String?
    private var cancelGeneration = false
    private var generationInFlight = false

#if canImport(llama)
    private var llama: LlamaContext?
#endif

    private(set) var lastMetrics = LocalInferenceMetrics.empty
    private(set) var lastLoadDiagnostics: LlamaLoadDiagnostics?

    var isModelLoaded: Bool { isLoaded }
    var modelPath: String? { loadedPath }

    static var isLlamaRuntimeAvailable: Bool {
#if canImport(llama)
        true
#else
        false
#endif
    }

    func load(
        path: String,
        config: LlamaInferenceConfig = .a15Default,
        modelId: String? = nil,
        quant: String? = nil
    ) async throws {
        LocalModelFileAudit.snapshotFS(point: "E-engine-load-start", finalPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            LocalModelFileAudit.snapshotFS(point: "E-engine-load-missing", finalPath: path)
            throw LocalInferenceError.modelMissing
        }

#if canImport(llama)
        if generationInFlight {
            cancelGeneration = true
            llama?.stop()
            generationInFlight = false
        }
        if isLoaded {
            LocalModelFileAudit.logFSOp(
                "unloadInternal",
                phase: "before-reload",
                result: "pending",
                watchedFinalPath: path
            )
            LocalModelFileAudit.snapshotFS(point: "E-before-unloadInternal", finalPath: path)
            await unloadInternal()
            LocalModelFileAudit.snapshotFS(point: "E-after-unloadInternal", finalPath: path)
            LocalModelFileAudit.logFSOp(
                "unloadInternal",
                phase: "after-reload",
                result: "done",
                watchedFinalPath: path
            )
        }

        let started = Date()
        do {
            LocalModelFileAudit.snapshotFS(point: "E-before-create_context-call", finalPath: path)
            let ctx = try LlamaContext.create_context(
                path: path,
                config: config,
                modelId: modelId,
                quant: quant
            )
            LocalModelFileAudit.snapshotFS(point: "E-after-create_context-ok", finalPath: path)
            llama = ctx
            isLoaded = true
            loadedPath = path
            lastLoadDiagnostics = LlamaContext.lastDiagnostics
            var metrics = lastMetrics
            metrics.loadDuration = Date().timeIntervalSince(started)
            metrics.backendEffective = lastLoadDiagnostics?.backendEffective
            metrics.nGpuLayersConfigured = lastLoadDiagnostics?.nGpuLayersConfigured
            lastMetrics = metrics
        } catch let LlamaError.couldNotInitializeContext(detail) {
            isLoaded = false
            loadedPath = nil
            llama = nil
            lastLoadDiagnostics = LlamaContext.lastDiagnostics
            LocalModelFileAudit.snapshotFS(point: "E-after-create_context-fail", finalPath: path)
            throw LocalInferenceError.loadFailed(detail)
        } catch {
            isLoaded = false
            loadedPath = nil
            llama = nil
            lastLoadDiagnostics = LlamaContext.lastDiagnostics
            LocalModelFileAudit.snapshotFS(point: "E-after-create_context-error", finalPath: path)
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain && ns.code == ENOMEM {
                throw LocalInferenceError.outOfMemory
            }
            throw LocalInferenceError.loadFailed(error.localizedDescription)
        }
#else
        _ = path
        _ = config
        _ = modelId
        _ = quant
        throw LocalInferenceError.notAvailable
#endif
    }

    func unload() async {
#if canImport(llama)
        cancelGeneration = true
        llama?.stop()
        await unloadInternal()
#else
        isLoaded = false
        loadedPath = nil
        cancelGeneration = false
#endif
    }

    func cancel() async {
        cancelGeneration = true
#if canImport(llama)
        llama?.stop()
#endif
    }

    /// Stream de tokens (pièces décodées).
    func generate(
        prompt: String,
        maxTokens: Int = 256
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runGeneration(
                        prompt: prompt,
                        maxTokens: maxTokens,
                        onToken: { token in
                            continuation.yield(token)
                        }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.cancel() }
            }
        }
    }

    /// Génération avec callback pièce par pièce.
    func generate(
        prompt: String,
        maxTokens: Int = 256,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
        try await runGeneration(prompt: prompt, maxTokens: maxTokens, onToken: onToken)
    }

    /// Nombre de tokens llama du prompt (nil si moteur non chargé).
    func countTokens(_ text: String) -> Int? {
#if canImport(llama)
        guard isLoaded, let llama else { return nil }
        return llama.countTokens(text)
#else
        _ = text
        return nil
#endif
    }

    private func runGeneration(
        prompt: String,
        maxTokens: Int,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
#if canImport(llama)
        guard let llama, isLoaded else {
            throw LocalInferenceError.notLoaded
        }
        cancelGeneration = false
        generationInFlight = true
        defer { generationInFlight = false }

        let started = Date()
        let counter = GenerationCounter()

        do {
            try await llama.generate(prompt: prompt, maxTokens: Int32(maxTokens)) { piece in
                if Task.isCancelled {
                    llama.stop()
                    return
                }
                if !piece.isEmpty {
                    counter.noteToken()
                    await onToken(piece)
                }
            }
            if cancelGeneration || Task.isCancelled {
                throw LocalInferenceError.cancelled
            }
        } catch LlamaError.cancelled {
            throw LocalInferenceError.cancelled
        } catch let error as LlamaError {
            if case .promptExceedsContext = error {
                throw LocalInferenceError.contextTooLarge
            }
            if case .couldNotInitializeContext(let detail) = error {
                if detail.localizedCaseInsensitiveContains("llama_decode")
                    || detail.localizedCaseInsensitiveContains("prefill") {
                    throw LocalInferenceError.contextTooLarge
                }
                throw LocalInferenceError.generatingFailed(detail)
            }
            throw LocalInferenceError.generatingFailed(error.localizedDescription)
        } catch let error as LocalInferenceError {
            throw error
        } catch is CancellationError {
            throw LocalInferenceError.cancelled
        } catch {
            let detail = error.localizedDescription
            if detail.localizedCaseInsensitiveContains("llama_decode")
                || detail.localizedCaseInsensitiveContains("prefill") {
                throw LocalInferenceError.contextTooLarge
            }
            throw LocalInferenceError.generatingFailed(detail)
        }

        let tokenCount = counter.count
        let totalSec = Date().timeIntervalSince(started)
        let promptSec = llama.lastPromptEvalSeconds
        let promptTok = llama.promptTokenCount
        var metrics = LocalInferenceMetrics.empty
        metrics.loadDuration = lastMetrics.loadDuration
        metrics.backendEffective = lastLoadDiagnostics?.backendEffective ?? lastMetrics.backendEffective
        metrics.nGpuLayersConfigured = lastLoadDiagnostics?.nGpuLayersConfigured ?? lastMetrics.nGpuLayersConfigured
        metrics.promptEvalSeconds = promptSec
        metrics.promptTokens = promptTok
        metrics.generatedTokens = tokenCount
        metrics.totalSeconds = totalSec
        if promptSec > 0, promptTok > 0 {
            metrics.promptTokensPerSecond = Double(promptTok) / promptSec
        }
        if let first = counter.firstTokenDate {
            metrics.timeToFirstToken = first.timeIntervalSince(started)
            let genSec = Date().timeIntervalSince(first)
            metrics.generationSeconds = genSec
            if genSec > 0, tokenCount > 0 {
                // tok/s génération (hors prefill) — plus honnête que total.
                metrics.tokensPerSecond = Double(tokenCount) / genSec
            }
        } else if totalSec > 0, tokenCount > 0 {
            metrics.tokensPerSecond = Double(tokenCount) / totalSec
        }
        if cancelGeneration || Task.isCancelled {
            metrics.cancellationLatencyMs = Date().timeIntervalSince(started) * 1000
        }
        lastMetrics = metrics
        print(
            String(
                format: "[local-ai:perf] backend=%@ gpuLayers=%d prompt=%d tok (%.0fms, %.1f t/s) gen=%d tok TTFT=%.0fms gen=%.1f t/s total=%.0fms",
                metrics.backendEffective ?? "?",
                metrics.nGpuLayersConfigured ?? -999,
                metrics.promptTokens,
                (metrics.promptEvalSeconds ?? 0) * 1000,
                metrics.promptTokensPerSecond ?? 0,
                metrics.generatedTokens,
                (metrics.timeToFirstToken ?? 0) * 1000,
                metrics.tokensPerSecond ?? 0,
                totalSec * 1000
            )
        )
#else
        _ = prompt
        _ = maxTokens
        _ = onToken
        throw LocalInferenceError.notAvailable
#endif
    }

#if canImport(llama)
    private func unloadInternal() async {
        llama?.clear()
        llama = nil
        isLoaded = false
        loadedPath = nil
        cancelGeneration = false
        generationInFlight = false
        lastLoadDiagnostics = nil
    }
#endif
}

/// Compteur thread-safe pour métriques de génération (closures `@Sendable`).
private final class GenerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var firstTokenDate: Date?

    func noteToken() {
        lock.lock()
        defer { lock.unlock() }
        if firstTokenDate == nil {
            firstTokenDate = Date()
        }
        count += 1
    }
}
