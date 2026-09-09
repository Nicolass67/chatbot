import Foundation

/// Erreurs d’inférence locale (indépendante de LM Studio PC).
enum LocalInferenceError: Error, LocalizedError, Sendable {
    case notAvailable
    case modelMissing
    case loadFailed(String)
    case outOfMemory
    case cancelled
    case generatingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Le runtime llama.cpp n’est pas disponible dans ce build."
        case .modelMissing:
            return "Modèle GGUF introuvable. Installez-le d’abord."
        case .loadFailed(let detail):
            return "Échec de chargement du modèle : \(detail)"
        case .outOfMemory:
            return "Mémoire insuffisante pour charger le modèle."
        case .cancelled:
            return "Génération annulée."
        case .generatingFailed(let detail):
            return "Échec de génération : \(detail)"
        }
    }
}

struct LocalInferenceMetrics: Sendable, Equatable {
    var loadDuration: TimeInterval?
    var timeToFirstToken: TimeInterval?
    var tokensPerSecond: Double?
    var generatedTokens: Int
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

    private(set) var lastMetrics = LocalInferenceMetrics(
        loadDuration: nil,
        timeToFirstToken: nil,
        tokensPerSecond: nil,
        generatedTokens: 0
    )

    var isModelLoaded: Bool { isLoaded }
    var modelPath: String? { loadedPath }

    static var isLlamaRuntimeAvailable: Bool {
#if canImport(llama)
        true
#else
        false
#endif
    }

    func load(path: String) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw LocalInferenceError.modelMissing
        }

#if canImport(llama)
        if generationInFlight {
            cancelGeneration = true
            if let llama {
                await llama.stop()
            }
            generationInFlight = false
        }
        if isLoaded {
            await unloadInternal()
        }

        let started = Date()
        do {
            let ctx = try await LlamaContext.create_context(path: path)
            llama = ctx
            isLoaded = true
            loadedPath = path
            lastMetrics.loadDuration = Date().timeIntervalSince(started)
        } catch LlamaError.couldNotInitializeContext {
            isLoaded = false
            loadedPath = nil
            llama = nil
            throw LocalInferenceError.loadFailed("impossible d’initialiser le contexte")
        } catch {
            isLoaded = false
            loadedPath = nil
            llama = nil
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain && ns.code == ENOMEM {
                throw LocalInferenceError.outOfMemory
            }
            throw LocalInferenceError.loadFailed(error.localizedDescription)
        }
#else
        _ = path
        throw LocalInferenceError.notAvailable
#endif
    }

    func unload() async {
#if canImport(llama)
        cancelGeneration = true
        if let llama {
            await llama.stop()
        }
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
        if let llama {
            await llama.stop()
        }
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

    private func runGeneration(
        prompt: String,
        maxTokens: Int,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
#if canImport(llama)
        guard let llama, isLoaded else {
            throw LocalInferenceError.modelMissing
        }
        cancelGeneration = false
        generationInFlight = true
        defer { generationInFlight = false }

        let started = Date()
        let counter = GenerationCounter()

        do {
            try await llama.generate(prompt: prompt, maxTokens: Int32(maxTokens)) { piece in
                if Task.isCancelled {
                    await llama.stop()
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
        } catch let error as LocalInferenceError {
            throw error
        } catch is CancellationError {
            throw LocalInferenceError.cancelled
        } catch {
            throw LocalInferenceError.generatingFailed(error.localizedDescription)
        }

        let tokenCount = counter.count
        var metrics = LocalInferenceMetrics(
            loadDuration: lastMetrics.loadDuration,
            timeToFirstToken: nil,
            tokensPerSecond: nil,
            generatedTokens: tokenCount
        )
        if let first = counter.firstTokenDate {
            metrics.timeToFirstToken = first.timeIntervalSince(started)
        }
        let totalSec = Date().timeIntervalSince(started)
        if totalSec > 0, tokenCount > 0 {
            metrics.tokensPerSecond = Double(tokenCount) / totalSec
        }
        lastMetrics = metrics
#else
        _ = prompt
        _ = maxTokens
        _ = onToken
        throw LocalInferenceError.notAvailable
#endif
    }

#if canImport(llama)
    private func unloadInternal() async {
        if let llama {
            await llama.clear()
        }
        llama = nil
        isLoaded = false
        loadedPath = nil
        cancelGeneration = false
        generationInFlight = false
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
