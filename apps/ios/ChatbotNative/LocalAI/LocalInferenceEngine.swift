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
    /// Tokens du prompt servis depuis le KV du tour précédent (0 = prefill complet).
    var reusedPrefixTokens: Int = 0

    /// Part du prompt qui n'a pas eu besoin d'être réencodée.
    var prefixReuseRatio: Double? {
        guard promptTokens > 0 else { return nil }
        return Double(reusedPrefixTokens) / Double(promptTokens)
    }

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
        nGpuLayersConfigured: nil,
        reusedPrefixTokens: 0
    )
}

/// Moteur d’inférence locale — encapsule `LlamaContext` derrière `#if canImport(llama)`.
actor LocalInferenceEngine {
    static let shared = LocalInferenceEngine()

    private var isLoaded = false
    private var loadedPath: String?
    private var loadedModelId: String?
    private var cancelGeneration = false
    private var generationInFlight = false
    private var activeConfig: LlamaInferenceConfig = .a15Default
    /// Préfixe système à écrire sur disque après la première génération réussie.
    private var pendingPrefixCache: (signature: PromptPrefixCache.Signature, tokens: [Int32])?

#if canImport(llama)
    private var llama: LlamaContext?
#endif

    private(set) var lastMetrics = LocalInferenceMetrics.empty
    private(set) var lastLoadDiagnostics: LlamaLoadDiagnostics?

    var isModelLoaded: Bool { isLoaded }
    var modelPath: String? { loadedPath }
    var loadedModelIdentifier: String? { loadedModelId }

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
            loadedModelId = modelId
            lastLoadDiagnostics = LlamaContext.lastDiagnostics
            // La config effective peut avoir été dégradée par l'échelle de contexte :
            // l'empreinte du cache de prompt doit refléter ce qui a réellement été ouvert.
            activeConfig = Self.effectiveConfig(requested: config, diagnostics: lastLoadDiagnostics)
            pendingPrefixCache = nil
            var metrics = lastMetrics
            metrics.loadDuration = Date().timeIntervalSince(started)
            metrics.backendEffective = lastLoadDiagnostics?.backendEffective
            metrics.nGpuLayersConfigured = lastLoadDiagnostics?.nGpuLayersConfigured
            lastMetrics = metrics
        } catch let LlamaError.couldNotInitializeContext(detail) {
            isLoaded = false
            loadedPath = nil
            loadedModelId = nil
            llama = nil
            lastLoadDiagnostics = LlamaContext.lastDiagnostics
            LocalModelFileAudit.snapshotFS(point: "E-after-create_context-fail", finalPath: path)
            throw LocalInferenceError.loadFailed(detail)
        } catch {
            isLoaded = false
            loadedPath = nil
            loadedModelId = nil
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

#if canImport(llama)
    func setThreads(_ n: Int32, batch: Int32) {
        llama?.setThreads(n, batch: batch)
    }

    func currentThreads() -> (threads: Int32, batch: Int32)? {
        llama?.currentThreads()
    }

    func gdnSnapshot() -> LlamaGdnProbeObservation {
        let diag = lastLoadDiagnostics
        let obs = LlamaGdnRuntimeObserver.shared.snapshot(
            modelHasGdnLayers: LlamaGdnProbeObservation.modelImpliesGdnLayers(
                modelId: loadedModelId ?? diag?.modelId
            ),
            backendEffective: diag?.backendEffective
        )
        if var next = lastLoadDiagnostics {
            next.gdn = obs
            lastLoadDiagnostics = next
        }
        LlamaContext.updateGdn(obs)
        LocalModelFileAudit.log("local-ai:gdn", [
            "path": obs.pathKind.rawValue,
            "label": obs.userFacingFusedLabel,
            "probe": obs.probe,
            "source": obs.source,
            "compute": LlamaGdnRuntimeObserver.shared.didObserveCompute ? "yes" : "no",
            "asks": "\(LlamaGdnRuntimeObserver.shared.evalAskCount())",
        ])
        return obs
    }
#else
    func setThreads(_ n: Int32, batch: Int32) {
        _ = n
        _ = batch
    }

    func currentThreads() -> (threads: Int32, batch: Int32)? { nil }

    func gdnSnapshot() -> LlamaGdnProbeObservation { .unknown }
#endif

    func unload() async {
#if canImport(llama)
        cancelGeneration = true
        llama?.stop()
        await unloadInternal()
#else
        isLoaded = false
        loadedPath = nil
        loadedModelId = nil
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
        maxTokens: Int = 256,
        options: LocalGenerationOptions = .default
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runGeneration(
                        prompt: prompt,
                        maxTokens: maxTokens,
                        options: options,
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
        images: [Data] = [],
        mmprojPath: String? = nil,
        options: LocalGenerationOptions = .default,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
        try await runGeneration(
            prompt: prompt,
            maxTokens: maxTokens,
            images: images,
            mmprojPath: mmprojPath,
            options: options,
            onToken: onToken
        )
    }

    /// Fenêtre de contexte **réellement ouverte**, après l'échelle de repli.
    ///
    /// Le profil décrit ce qu'on demande ; si l'allocation a échoué en 6144 et
    /// que le contexte tourne en 4096, budgéter sur le profil garantit un
    /// dépassement au premier prompt un peu long.
    var activeContextTokens: Int { Int(activeConfig.nCtx) }

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

    /// Config telle qu'ouverte réellement (l'échelle de contexte peut avoir dégradé
    /// `n_ctx` ou repassé le KV en f16).
    private static func effectiveConfig(
        requested: LlamaInferenceConfig,
        diagnostics: LlamaLoadDiagnostics?
    ) -> LlamaInferenceConfig {
        guard let diagnostics else { return requested }
        var config = requested
        config.nCtx = diagnostics.nCtx
        if let typeK = LlamaKVCacheType(rawValue: diagnostics.kvCacheTypeK) {
            config.kvCacheTypeK = typeK
        }
        if let typeV = LlamaKVCacheType(rawValue: diagnostics.kvCacheTypeV) {
            config.kvCacheTypeV = typeV
        }
        if let mode = LlamaFlashAttentionMode(rawValue: diagnostics.flashAttention) {
            config.flashAttention = mode
        }
        return config
    }

    /// Amorce le KV avec le préfixe système stable depuis le cache disque.
    ///
    /// La réutilisation en mémoire couvre déjà tous les tours d'une session ;
    /// ceci ne sert qu'au premier message après un lancement ou un rechargement
    /// de modèle. Sans effet si le cache est absent, incompatible, ou incohérent.
    func primeStablePrefix(_ prefix: String) {
#if canImport(llama)
        guard isLoaded, let llama, !prefix.isEmpty else { return }
        let modelId = loadedModelId ?? loadedPath ?? "unknown"
        let signature = PromptPrefixCache.signature(
            modelId: modelId,
            config: activeConfig,
            prompt: prefix
        )

        var tokens = llama.tokenIds(for: prefix)
        // La dernière frontière de token n'est pas stable : le caractère suivant
        // du prompt complet peut fusionner avec elle. On sacrifie quelques tokens
        // pour garantir que le cache est bien un préfixe du prompt réel.
        guard tokens.count > 100 else { return }
        tokens.removeLast(4)

        if let url = PromptPrefixCache.existingState(for: signature) {
            let restored = llama.loadPrefixState(
                from: url.path(percentEncoded: false),
                expectedTokens: tokens
            )
            if restored > 0 {
                print("[local-ai:prefix-cache] restauré \(restored) tokens depuis le disque")
                pendingPrefixCache = nil
                return
            }
            print("[local-ai:prefix-cache] état illisible ou incohérent — purge")
            PromptPrefixCache.discard(signature: signature)
        }
        pendingPrefixCache = (signature, tokens)
#else
        _ = prefix
#endif
    }

#if canImport(llama)
    /// Écrit le cache après une génération réussie, quand le KV contient bien
    /// le préfixe attendu.
    private func persistPendingPrefixCache() {
        guard let pending = pendingPrefixCache, let llama else { return }
        guard let url = PromptPrefixCache.stateURLForWriting(
            signature: pending.signature,
            tokenCount: pending.tokens.count
        ) else {
            pendingPrefixCache = nil
            return
        }
        let saved = llama.savePrefixState(
            to: url.path(percentEncoded: false),
            expectedTokens: pending.tokens
        )
        if saved {
            PromptPrefixCache.writeMetadata(pending.signature)
            print("[local-ai:prefix-cache] écrit \(pending.tokens.count) tokens")
        } else {
            PromptPrefixCache.discard(signature: pending.signature)
        }
        pendingPrefixCache = nil
    }
#endif

    /// Comptage par lot — un seul aller-retour vers l'actor pour tout un prompt.
    /// Sans ça, ajuster un historique de 24 messages coûte 24 sauts de contexte.
    /// Repli sur l'estimation caractères si le modèle n'est pas chargé.
    func countTokens(batch texts: [String]) -> [Int] {
#if canImport(llama)
        if isLoaded, let llama {
            return texts.map { llama.countTokens($0) }
        }
#endif
        return texts.map { GenerationContextBudget.estimateTokens($0) }
    }

    private func runGeneration(
        prompt: String,
        maxTokens: Int,
        images: [Data] = [],
        mmprojPath: String? = nil,
        options: LocalGenerationOptions = .default,
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
        let bitmaps: [LocalVision.RGBBitmap] = images.prefix(LocalVision.maxImagesPerTurn).compactMap {
            LocalVision.rgbBitmap(from: $0)
        }
        if !images.isEmpty && bitmaps.isEmpty {
            throw LocalInferenceError.generatingFailed("Impossible de décoder l’image jointe.")
        }

        let deadline = options.timeout.map { started.addingTimeInterval($0) }
        do {
            try await llama.generate(
                prompt: prompt,
                maxTokens: Int32(maxTokens),
                images: bitmaps,
                mmprojPath: mmprojPath,
                sampling: options.sampling,
                grammar: options.grammar,
                deadline: deadline
            ) { piece in
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

        // Le KV contient maintenant le prompt complet : le préfixe système en est
        // le début, donc il est sauvegardable tel quel.
        persistPendingPrefixCache()

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
        metrics.reusedPrefixTokens = llama.lastReusedPrefixTokens
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
                format: "[local-ai:perf] backend=%@ gpuLayers=%d prompt=%d tok (kvReuse=%d/%.0f%%, %.0fms, %.1f t/s) gen=%d tok TTFT=%.0fms gen=%.1f t/s total=%.0fms",
                metrics.backendEffective ?? "?",
                metrics.nGpuLayersConfigured ?? -999,
                metrics.promptTokens,
                metrics.reusedPrefixTokens,
                (metrics.prefixReuseRatio ?? 0) * 100,
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
        _ = images
        _ = mmprojPath
        _ = options
        _ = onToken
        throw LocalInferenceError.notAvailable
#endif
    }

    func unloadVisionProjector() {
#if canImport(llama)
        llama?.unloadVision()
#endif
    }

#if canImport(llama)
    private func unloadInternal() async {
        llama?.clear()
        llama?.unloadVision()
        llama = nil
        isLoaded = false
        loadedPath = nil
        loadedModelId = nil
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
