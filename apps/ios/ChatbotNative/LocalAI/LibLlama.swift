import Foundation
import Darwin

#if canImport(llama)
import llama

enum LlamaError: Error, LocalizedError {
    case couldNotInitializeContext(String)
    case promptExceedsContext(promptTokens: Int, nCtx: Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext(let detail):
            return detail
        case .promptExceedsContext:
            return "Le contexte de cette recherche est trop volumineux. Je réduis automatiquement les résultats."
        case .cancelled:
            return "Génération annulée."
        }
    }
}

/// Capture les logs C de llama.cpp pour diagnostiquer un load GGUF nil.
private final class LlamaLogCapture: @unchecked Sendable {
    static let shared = LlamaLogCapture()
    private let lock = NSLock()
    private var lines: [String] = []
    private var gdnLines: [String] = []
    private var fileDiagnostics: [String] = []

    func clear() {
        lock.lock()
        lines.removeAll(keepingCapacity: true)
        gdnLines.removeAll(keepingCapacity: true)
        fileDiagnostics.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        lines.append(trimmed)
        if lines.count > 250 { lines.removeFirst(lines.count - 250) }
        if LlamaGdnProbeObservation.isRelevantLogLine(trimmed) {
            gdnLines.append(trimmed)
            LocalModelFileAudit.log("local-ai:gdn-raw", ["line": trimmed])
        }
        lock.unlock()
    }

    func recordFileDiagnostic(_ report: String) {
        lock.lock()
        fileDiagnostics.append(report)
        if fileDiagnostics.count > 3 { fileDiagnostics.removeFirst(fileDiagnostics.count - 3) }
        lock.unlock()
        print("[local-ai:file-diagnostic] \(report)")
    }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        let tail = lines.suffix(6)
        let logs = tail.joined(separator: " · ")
        let diagnostics = fileDiagnostics.joined(separator: "\n\n")
        guard !logs.isEmpty || !diagnostics.isEmpty else { return "" }
        if diagnostics.isEmpty { return " — " + logs }
        if logs.isEmpty { return " — " + diagnostics }
        return " — \(logs)\n\n\(diagnostics)"
    }

    func gdnLogLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return gdnLines
    }

    var reportsMissingGGUF: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lines.contains { line in
            line.localizedCaseInsensitiveContains("failed to open GGUF file")
                || line.localizedCaseInsensitiveContains("no such file or directory")
        }
    }
}

/// Audit temporaire du fichier transmis à llama.cpp. Les appels POSIX utilisent
/// exactement la même C-string que `llama_model_load_from_file`.
private enum LlamaFileDiagnostics {
    static func report(path: String, phase: String) -> String {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
        let parent = url.deletingLastPathComponent()
        let entries = ((try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])) ?? [])
            .map { entry -> String in
                let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                let size = values?.fileSize.map { String($0) } ?? "—"
                let regular = values?.isRegularFile.map { String($0) } ?? "—"
                return "\(entry.lastPathComponent){path=\(entry.path(percentEncoded: false)),size=\(size),regular=\(regular)}"
            }
            .joined(separator: "; ")

        let posix = path.withCString { cPath -> String in
            func failure(_ code: Int32) -> String {
                "errno=\(code): \(String(cString: strerror(code)))"
            }

            let bytes = Array(path.utf8).map { String(format: "%02X", $0) }.joined(separator: " ")
            errno = 0
            let exists = access(cPath, F_OK)
            let existsErrno = errno
            errno = 0
            let readable = access(cPath, R_OK)
            let readableErrno = errno
            var info = stat()
            errno = 0
            let statResult = stat(cPath, &info)
            let statErrno = errno
            errno = 0
            let descriptor = open(cPath, O_RDONLY)
            let openErrno = errno
            if descriptor >= 0 { _ = close(descriptor) }
            errno = 0
            let stream = fopen(cPath, "rb")
            let fopenErrno = errno
            if let stream { _ = fclose(stream) }

            let accessF = exists == 0 ? "PASS" : "FAIL(\(failure(existsErrno)))"
            let accessR = readable == 0 ? "PASS" : "FAIL(\(failure(readableErrno)))"
            let statText = statResult == 0
                ? "PASS(size=\(info.st_size),mode=\(info.st_mode))"
                : "FAIL(\(failure(statErrno)))"
            let openText = descriptor >= 0 ? "PASS(fd=\(descriptor))" : "FAIL(\(failure(openErrno)))"
            let fopenText = stream == nil ? "FAIL(\(failure(fopenErrno)))" : "PASS"
            return "cString.length=\(strlen(cPath)),utf8.length=\(path.utf8.count),utf8.hex=[\(bytes)],debug=\(String(reflecting: path)),access(F_OK)=\(accessF),access(R_OK)=\(accessR),stat=\(statText),open=\(openText),fopen=\(fopenText)"
        }

        let size = attrs[.size].map { String(describing: $0) } ?? "—"
        let modified = attrs[.modificationDate].map { String(describing: $0) } ?? "—"
        let type = attrs[.type].map { String(describing: $0) } ?? "—"
        let protection = attrs[.protectionKey].map { String(describing: $0) } ?? "—"
        return "[\(phase)] absolute=\(url.absoluteString),path=\(url.path(percentEncoded: false)),standardized=\(url.standardizedFileURL.path(percentEncoded: false)),symlinks=\(url.resolvingSymlinksInPath().path(percentEncoded: false)); FileManager{exists=\(fm.fileExists(atPath: path)),readable=\(fm.isReadableFile(atPath: path)),size=\(size),modified=\(modified),type=\(type),protection=\(protection)}; parent.entries=[\(entries.isEmpty ? "<empty>" : entries)]; POSIX{\(posix)}"
    }
}

private func llamaCppLogLevelRaw(_ level: ggml_log_level) -> Int32 {
    unsafeBitCast(level, to: Int32.self)
}

private func llamaTensorName(_ tensor: UnsafeMutablePointer<ggml_tensor>) -> String {
    withUnsafePointer(to: tensor.pointee.name) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
    }
}

private func llamaInstallLogCapture() {
    llama_log_set({ level, text, _ in
        guard let text else { return }
        let line = String(cString: text)
        LlamaGdnRuntimeObserver.shared.appendLog(levelRaw: llamaCppLogLevelRaw(level), text: line)
        LlamaLogCapture.shared.append(line)
    }, nil)
}

private func llamaGdnEvalCallback(
    _ tensor: UnsafeMutablePointer<ggml_tensor>?,
    _ ask: Bool,
    _ userData: UnsafeMutableRawPointer?
) -> Bool {
    _ = userData
    guard let tensor else { return true }
    let op = tensor.pointee.op
    let opName = String(cString: ggml_op_name(op))
    let name = llamaTensorName(tensor)
    if ask {
        LlamaGdnRuntimeObserver.shared.noteAsk()
        // Observer seulement quelques nœuds GDN — ask=true sur tout le graphe casse le batching.
        return LlamaGdnRuntimeObserver.shared.shouldObserve(opName: opName, tensorName: name)
    }
    var deviceName = "unknown"
    var isCPU = false
    var isGPU = false
    if let buffer = tensor.pointee.buffer {
        if let cName = ggml_backend_buffer_name(buffer) {
            deviceName = String(cString: cName)
        }
        let buft = ggml_backend_buffer_get_type(buffer)
        if let dev = ggml_backend_buft_get_device(buft) {
            deviceName = String(cString: ggml_backend_dev_name(dev))
            switch ggml_backend_dev_type(dev) {
            case GGML_BACKEND_DEVICE_TYPE_CPU:
                isCPU = true
            case GGML_BACKEND_DEVICE_TYPE_GPU, GGML_BACKEND_DEVICE_TYPE_IGPU, GGML_BACKEND_DEVICE_TYPE_ACCEL:
                isGPU = true
            default:
                break
            }
        }
        let lower = deviceName.lowercased()
        if lower.contains("metal") || lower.contains("gpu") { isGPU = true }
        if lower.contains("cpu") { isCPU = true }
    }
    LlamaGdnRuntimeObserver.shared.recordEvalHit(
        LlamaGdnEvalHit(
            opName: opName,
            tensorName: name,
            deviceName: deviceName,
            deviceIsCPU: isCPU,
            deviceIsGPU: isGPU
        )
    )
    LocalModelFileAudit.log("local-ai:gdn-eval", [
        "op": opName,
        "tensor": name,
        "device": deviceName,
        "cpu": isCPU ? "yes" : "no",
        "gpu": isGPU ? "yes" : "no",
    ])
    return true
}

func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

func llama_batch_add(
    _ batch: inout llama_batch,
    _ id: llama_token,
    _ pos: llama_pos,
    _ seq_ids: [llama_seq_id],
    _ logits: Bool
) {
    batch.token[Int(batch.n_tokens)] = id
    batch.pos[Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id[Int(batch.n_tokens)]![Int(i)] = seq_ids[i]
    }
    batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
}

/// Contexte llama.cpp — paramètres via `LlamaInferenceConfig` (ExecutionProfile).
/// Historique : CPU était **forcé** (`n_gpu_layers=0`) car Metal+devices NULL échouait.
/// Désormais : tentative Metal + GPU layers, fallback CPU automatique (pas de régression load).
/// Classe `@unchecked Sendable` (pointeurs C) : accès sérialisé via `LocalInferenceEngine` (actor).
final class LlamaContext: @unchecked Sendable {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer?
    private var sampling: UnsafeMutablePointer<llama_sampler>?
    private var batch: llama_batch
    private var tokens_list: [llama_token]
    private var temporary_invalid_cchars: [CChar]
    private var cancelRequested = false
    private let inferenceConfig: LlamaInferenceConfig
    /// Projecteur vision — chargé à la demande, jamais à la place du GGUF texte.
    private var mtmdCtx: OpaquePointer?

    /// Miroir exact des tokens présents dans le KV de la séquence 0.
    /// Mis à jour uniquement après un `llama_decode` réussi, donc toujours
    /// cohérent avec l'état réel du cache, y compris après annulation.
    private var kvTokens: [llama_token] = []
    /// `false` quand le KV contient des tokens dont on ignore les ids (image mtmd) :
    /// le miroir n'est plus exact, aucune réutilisation de préfixe n'est permise.
    private var kvMirrorValid = true
    /// Config d'échantillonnage actuellement compilée dans la chaîne.
    private var activeSampling: LlamaSamplingConfig
    private var activeGrammar: String?
    /// Tokens du prompt réutilisés depuis le KV lors de la dernière génération.
    private(set) var lastReusedPrefixTokens: Int = 0

    /// Dernier diagnostic de load (protégé par `diagLock`).
    private static let diagLock = NSLock()
    nonisolated(unsafe) private static var _lastDiagnostics: LlamaLoadDiagnostics?
    static var lastDiagnostics: LlamaLoadDiagnostics? {
        diagLock.lock(); defer { diagLock.unlock() }
        return _lastDiagnostics
    }

    static func updateGdn(_ obs: LlamaGdnProbeObservation) {
        diagLock.lock()
        defer { diagLock.unlock() }
        guard var diag = _lastDiagnostics else { return }
        diag.gdn = obs
        _lastDiagnostics = diag
    }

    var is_done: Bool = false
    /// Longueur max de génération (tokens prompt + completion).
    var n_len: Int32 = 1024
    var n_cur: Int32 = 0
    var n_decode: Int32 = 0
    /// Tokens du prompt après `completion_init`.
    private(set) var promptTokenCount: Int = 0
    /// Secondes d’évaluation prompt (préfill).
    private(set) var lastPromptEvalSeconds: TimeInterval = 0

    init(model: OpaquePointer, context: OpaquePointer, config: LlamaInferenceConfig) {
        self.model = model
        self.context = context
        self.inferenceConfig = config
        self.tokens_list = []
        let batchCap = Int(max(config.nBatch, 64))
        self.batch = llama_batch_init(Int32(batchCap), 0, 1)
        self.temporary_invalid_cchars = []
        let resolvedVocab = llama_model_get_vocab(model)
        self.vocab = resolvedVocab
        self.activeSampling = config.sampling
        self.activeGrammar = nil
        self.sampling = LlamaContext.makeSamplerChain(
            vocab: resolvedVocab,
            sampling: config.sampling,
            grammar: nil
        )
    }

    /// Chaîne d'échantillonnage dans l'ordre de référence llama.cpp :
    /// `grammaire → pénalités → top_k → top_p → min_p → température → tirage`.
    ///
    /// L'ordre n'est pas cosmétique : appliquer la température avant `top_p`
    /// aiguise la distribution, si bien que `top_p` ne tronque plus le même
    /// ensemble que celui sur lequel le modèle a été calibré.
    private static func makeSamplerChain(
        vocab: OpaquePointer?,
        sampling: LlamaSamplingConfig,
        grammar: String?
    ) -> UnsafeMutablePointer<llama_sampler>? {
        let sparams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(sparams)

        // 1) Grammaire GBNF : masque les tokens structurellement invalides.
        if let grammar, !grammar.isEmpty {
            let grammarSampler: UnsafeMutablePointer<llama_sampler>? = grammar.withCString { gPtr in
                "root".withCString { rootPtr in
                    llama_sampler_init_grammar(vocab, gPtr, rootPtr)
                }
            }
            if let grammarSampler {
                llama_sampler_chain_add(chain, grammarSampler)
            } else {
                print("[local-ai:sampler] grammaire GBNF invalide — génération non contrainte")
            }
        }

        // 2) Pénalités : sur les logits bruts, avant toute troncature.
        if sampling.usesPenalties {
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(
                llama_vocab_n_tokens(vocab),
                sampling.penaltyLastN,
                sampling.repeatPenalty,
                sampling.frequencyPenalty,
                sampling.presencePenalty
            ))
        }

        // 3) Troncatures.
        if sampling.topK > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(sampling.topK))
        }
        if sampling.topP > 0, sampling.topP < 1 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(sampling.topP, 1))
        }
        if sampling.minP > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(sampling.minP, 1))
        }

        // 4) Température puis tirage stochastique.
        llama_sampler_chain_add(chain, llama_sampler_init_temp(sampling.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(sampling.seed))
        return chain
    }

    /// Recompile la chaîne seulement si la config change ; sinon simple reset.
    private func ensureSampler(_ next: LlamaSamplingConfig, grammar: String?) {
        if next == activeSampling, grammar == activeGrammar {
            llama_sampler_reset(sampling)
            return
        }
        llama_sampler_free(sampling)
        sampling = LlamaContext.makeSamplerChain(vocab: vocab, sampling: next, grammar: grammar)
        activeSampling = next
        activeGrammar = grammar
    }

    // MARK: - KV cache (miroir exact de la séquence 0)

    private func resetKV() {
        llama_memory_clear(llama_get_memory(context), true)
        kvTokens.removeAll(keepingCapacity: true)
        kvMirrorValid = true
        n_cur = 0
    }

    /// Longueur du plus long préfixe commun entre le KV courant et le prompt.
    /// On garde toujours au moins un token à décoder : sans decode, pas de logits.
    private func reusablePrefixLength(for promptTokens: [llama_token]) -> Int {
        guard inferenceConfig.prefixReuseEnabled, kvMirrorValid, !kvTokens.isEmpty else { return 0 }
        let limit = min(kvTokens.count, promptTokens.count)
        var n = 0
        while n < limit, kvTokens[n] == promptTokens[n] { n += 1 }
        if n >= promptTokens.count { n = max(0, promptTokens.count - 1) }
        return n
    }

    /// Tronque le KV au préfixe commun. Renvoie le nombre de tokens conservés.
    private func trimKV(to nKeep: Int) -> Int {
        guard nKeep > 0 else {
            resetKV()
            return 0
        }
        if nKeep >= kvTokens.count {
            n_cur = Int32(kvTokens.count)
            return kvTokens.count
        }
        let memory = llama_get_memory(context)
        // Attention pleine (Qwen3.5) : la suppression partielle réussit toujours.
        // Un `false` signalerait une mémoire récurrente/hybride → repli propre.
        guard llama_memory_seq_rm(memory, 0, llama_pos(nKeep), -1) else {
            resetKV()
            return 0
        }
        kvTokens.removeSubrange(nKeep...)
        n_cur = Int32(nKeep)
        return nKeep
    }

    /// Préfille `tokens[from...]` par paquets de `n_batch`, en positions absolues.
    private func prefill(_ tokens: [llama_token], from start: Int) throws {
        let batchLimit = Int(max(inferenceConfig.nBatch, 1))
        var i = start
        while i < tokens.count {
            if cancelRequested { throw LlamaError.cancelled }
            llama_batch_clear(&batch)
            let end = min(i + batchLimit, tokens.count)
            for j in i..<end {
                let isLast = j == tokens.count - 1
                llama_batch_add(&batch, tokens[j], Int32(j), [0], isLast)
            }
            if decodeObserved(batch) != 0 {
                // Le KV est dans un état indéterminé après un decode raté.
                resetKV()
                throw LlamaError.couldNotInitializeContext(
                    "échec prefill llama_decode (batch \(i)..\(end - 1))"
                )
            }
            kvTokens.append(contentsOf: tokens[i..<end])
            i = end
        }
        n_cur = Int32(tokens.count)
    }

    // MARK: - Cache de prompt sur disque

    /// Sauvegarde le KV du préfixe `[0, count)` pour le réutiliser après un
    /// redémarrage. Ne sert qu'au premier message d'une session : dans la même
    /// session, la réutilisation en mémoire est déjà totale.
    ///
    /// L'état sauvegardé est lié aux paramètres exacts du contexte (n_ctx, type
    /// du KV, Flash Attention). C'est à l'appelant de valider la compatibilité
    /// via une empreinte ; ici on ne fait qu'écrire et relire.
    @discardableResult
    func savePrefixState(to path: String, expectedTokens: [llama_token]) -> Bool {
        guard kvMirrorValid, !expectedTokens.isEmpty, expectedTokens.count <= kvTokens.count else {
            return false
        }
        let tokens = Array(kvTokens.prefix(expectedTokens.count))
        // Le KV ne commence pas par le préfixe attendu (autre prompt système,
        // autre workflow) : sauvegarder produirait un état trompeur.
        guard tokens == expectedTokens else { return false }
        let written = tokens.withUnsafeBufferPointer { buffer -> size_t in
            path.withCString { cPath in
                llama_state_seq_save_file(context, cPath, 0, buffer.baseAddress, size_t(buffer.count))
            }
        }
        return written > 0
    }

    /// Recharge un préfixe sauvegardé. Le miroir KV est remplacé par les tokens
    /// réellement restaurés, donc reste exact.
    @discardableResult
    func loadPrefixState(from path: String, expectedTokens: [llama_token]) -> Int {
        guard !expectedTokens.isEmpty else { return 0 }
        resetKV()

        var restored = [llama_token](repeating: 0, count: expectedTokens.count)
        var count: size_t = 0
        let read = restored.withUnsafeMutableBufferPointer { buffer -> size_t in
            path.withCString { cPath in
                llama_state_seq_load_file(
                    context,
                    cPath,
                    0,
                    buffer.baseAddress,
                    size_t(buffer.count),
                    &count
                )
            }
        }
        guard read > 0, count > 0, Int(count) <= expectedTokens.count else {
            resetKV()
            return 0
        }
        let loaded = Array(restored.prefix(Int(count)))
        // Un état restauré qui ne correspond pas aux tokens attendus produirait
        // des logits sans rapport avec le prompt : on préfère repartir de zéro.
        guard loaded == Array(expectedTokens.prefix(loaded.count)) else {
            resetKV()
            return 0
        }
        kvTokens = loaded
        kvMirrorValid = true
        n_cur = Int32(loaded.count)
        return loaded.count
    }

    /// Tokens du prompt, exposés pour préparer un cache disque.
    func tokenIds(for text: String) -> [llama_token] {
        tokenize(text: text, add_bos: false)
    }

    /// Décodage à vide : compile les pipelines Metal et pagine les poids mmapés
    /// hors du chemin utilisateur. Sans ça, le tout premier token de la session
    /// paie l'intégralité de ce coût.
    @discardableResult
    func warmup() -> TimeInterval {
        let started = Date()
        let bos = llama_vocab_bos(vocab)
        let token = bos >= 0 ? bos : llama_vocab_eos(vocab)
        guard token >= 0 else { return 0 }
        llama_batch_clear(&batch)
        llama_batch_add(&batch, token, 0, [0], true)
        _ = llama_decode(context, batch)
        resetKV()
        return Date().timeIntervalSince(started)
    }

    func setThreads(_ n: Int32, batch: Int32) {
        llama_set_n_threads(context, n, batch)
    }

    func currentThreads() -> (threads: Int32, batch: Int32) {
        (llama_n_threads(context), llama_n_threads_batch(context))
    }

    @discardableResult
    private func decodeObserved(_ batch: llama_batch) -> Int32 {
        let rc = llama_decode(context, batch)
        LlamaGdnRuntimeObserver.shared.markComputeNode()
        return rc
    }

    deinit {
        if let mtmdCtx {
            mtmd_free(mtmdCtx)
        }
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        // Ne pas appeler llama_backend_free() ici — une seule fois pour le process.
    }

    static func probeBackends() -> LlamaBackendProbe {
        ggml_backend_load_all()
        var metalName: String?
        var cpuName: String?
        var summaries: [String] = []
        let count = Int(ggml_backend_dev_count())
        for i in 0..<count {
            guard let dev = ggml_backend_dev_get(i) else { continue }
            let type = ggml_backend_dev_type(dev)
            let name = String(cString: ggml_backend_dev_name(dev))
            let typeLabel: String
            switch type {
            case GGML_BACKEND_DEVICE_TYPE_CPU: typeLabel = "CPU"; cpuName = name
            case GGML_BACKEND_DEVICE_TYPE_GPU: typeLabel = "GPU"; if metalName == nil { metalName = name }
            case GGML_BACKEND_DEVICE_TYPE_ACCEL: typeLabel = "ACCEL"
            default: typeLabel = "OTHER"
            }
            // Metal apparaît typiquement comme GPU nommé « Metal ».
            if name.localizedCaseInsensitiveContains("metal") {
                metalName = name
            }
            summaries.append("\(typeLabel):\(name)")
        }
        if metalName == nil, let gpu = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU) {
            metalName = String(cString: ggml_backend_dev_name(gpu))
        }
        if cpuName == nil, let cpu = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU) {
            cpuName = String(cString: ggml_backend_dev_name(cpu))
        }
        return LlamaBackendProbe(
            metalAvailable: metalName != nil,
            metalName: metalName,
            cpuAvailable: cpuName != nil,
            cpuName: cpuName,
            deviceCount: count,
            deviceSummaries: summaries
        )
    }

    static func create_context(
        path: String,
        config: LlamaInferenceConfig = .a15Default,
        modelId: String? = nil,
        quant: String? = nil
    ) throws -> LlamaContext {
        // F — juste avant create_context (entrée)
        LocalModelFileAudit.snapshotFS(point: "F-before-create_context", finalPath: path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            LocalModelFileAudit.snapshotFS(point: "F-create_context-file-absent", finalPath: path)
            throw LlamaError.couldNotInitializeContext("fichier absent: \(path)")
        }
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 1_000_000 else {
            LocalModelFileAudit.snapshotFS(point: "F-create_context-file-too-small", finalPath: path)
            throw LlamaError.couldNotInitializeContext("fichier trop petit (\(size) octets)")
        }

        LlamaLogCapture.shared.clear()
        LlamaGdnRuntimeObserver.shared.resetForModelLoad()
        llamaInstallLogCapture()

        let loadStarted = Date()
        ggml_backend_load_all()
        llama_backend_init()
        let llamaVer = String(cString: llama_version())
        print("[local-ai:llama] version=\(llamaVer)")
        let probe = probeBackends()
        print("[local-ai:backends] \(probe.deviceSummaries.joined(separator: ", "))")

#if targetEnvironment(simulator)
        let wantMetal = false
#else
        let wantMetal = config.preferMetal && probe.metalAvailable && config.nGpuLayers != 0
#endif

        var fellBack = false
        var fallbackReason: String?
        var effectiveBackend = wantMetal ? "metal" : "cpu"
        var usedMmap = config.useMmap
        var configuredGpuLayers: Int32 = wantMetal ? config.nGpuLayers : 0

        // 1) Tentative Metal (si demandé) — échec → CPU (chemin historique stable).
        var model: OpaquePointer?
        if wantMetal {
            do {
                model = try loadModelPreferring(
                    path: path,
                    size: size,
                    nGpuLayers: config.nGpuLayers,
                    useMetal: true,
                    useMmap: config.useMmap,
                    metalName: probe.metalName
                )
                if model == nil {
                    fellBack = true
                    fallbackReason = "metal_load_nil"
                    effectiveBackend = "cpu"
                    configuredGpuLayers = 0
                    print("[local-ai:metal] load failed → fallback CPU. \(LlamaLogCapture.shared.summary)")
                }
            } catch {
                fellBack = true
                fallbackReason = error.localizedDescription
                effectiveBackend = "cpu"
                configuredGpuLayers = 0
                model = nil
                print("[local-ai:metal] error → fallback CPU: \(error.localizedDescription)")
            }
        }

        if model == nil {
            effectiveBackend = "cpu"
            configuredGpuLayers = 0
            model = try loadModelPreferring(
                path: path,
                size: size,
                nGpuLayers: 0,
                useMetal: false,
                useMmap: config.useMmap,
                metalName: nil
            )
            // Si mmap échoue côté CPU, loadModelPreferring retente sans mmap.
            if model == nil {
                usedMmap = false
                model = try loadModelPreferring(
                    path: path,
                    size: size,
                    nGpuLayers: 0,
                    useMetal: false,
                    useMmap: false,
                    metalName: nil
                )
            }
        }

        guard let model else {
            LocalModelFileAudit.snapshotFS(point: "H-after-all-loadModel-fail", finalPath: path)
            throw LlamaError.couldNotInitializeContext(
                "chargement GGUF impossible (\(byteLabel(size))).\(LlamaLogCapture.shared.summary)"
            )
        }

        let nLayers = llama_model_n_layer(model)
        let opened = try openContext(model: model, config: config)
        let ctx = opened.context
        let effective = opened.effectiveConfig
        if opened.degraded {
            print("[local-ai:context] \(opened.notes.joined(separator: " · "))")
        }

        var warmupMs: Double?
        if effective.warmupOnLoad {
            warmupMs = ctx.warmup() * 1000
        }

        let loadMs = Date().timeIntervalSince(loadStarted) * 1000
        let threads = LlamaInferenceConfig.resolvedThreads(explicit: effective.nThreads)
        let threadsBatch = LlamaInferenceConfig.resolvedThreads(explicit: effective.nThreadsBatch ?? effective.nThreads)
        // KV réel : 2 (K+V) * n_layer * n_embd_kv * n_ctx * octets par élément.
        // `n_embd_kv` n'est pas exposé — on prend `n_embd / 2` comme approximation
        // GQA prudente, recalée par famille dans `KVCacheSizing`.
        let embdApprox = max(Int(llama_model_n_embd(model)) / 2, 256)
        let kvElementBytes = (effective.kvCacheTypeK.bytesPerElement + effective.kvCacheTypeV.bytesPerElement) / 2
        let kvHint = Int64(
            2.0 * Double(max(nLayers, 1)) * Double(embdApprox) * Double(effective.nCtx) * kvElementBytes
        )

        let gdn = LlamaGdnRuntimeObserver.shared.snapshot(
            modelHasGdnLayers: LlamaGdnProbeObservation.modelImpliesGdnLayers(
                modelId: modelId,
                architectureHint: quant
            ),
            backendEffective: effectiveBackend
        )
        let diag = LlamaLoadDiagnostics(
            modelPath: path,
            modelId: modelId,
            quant: quant,
            fileBytes: size,
            backendRequested: wantMetal ? "metal" : "cpu",
            backendEffective: effectiveBackend,
            metalAvailable: probe.metalAvailable,
            metalDeviceName: probe.metalName,
            cpuDeviceName: probe.cpuName,
            nGpuLayersConfigured: configuredGpuLayers,
            nLayerModel: nLayers,
            nCtx: effective.nCtx,
            nCtxRequested: config.nCtx,
            nBatch: effective.nBatch,
            nUbatch: effective.nUbatch,
            nThreads: threads,
            nThreadsBatch: threadsBatch,
            flashAttention: effective.effectiveFlashAttention.rawValue,
            kvCacheTypeK: effective.kvCacheTypeK.rawValue,
            kvCacheTypeV: effective.kvCacheTypeV.rawValue,
            usedMmap: usedMmap,
            loadDurationMs: loadMs,
            warmupDurationMs: warmupMs,
            fellBackToCPU: fellBack || effectiveBackend == "cpu" && wantMetal,
            fallbackReason: fallbackReason,
            llamaLogTail: LlamaLogCapture.shared.summary,
            estimatedKVBytesHint: kvHint,
            availableMemoryAtLoad: DeviceMemoryGuard.availableBytes(),
            gdn: gdn
        )
        diagLock.lock()
        _lastDiagnostics = diag
        diagLock.unlock()
        print("[local-ai:load] \(diag.summaryLine)")
        print(diag.gdn.explicitReport)
        LocalModelFileAudit.log("local-ai:gdn", [
            "path": diag.gdn.pathKind.rawValue,
            "label": diag.gdn.userFacingFusedLabel,
            "probe": diag.gdn.probe,
            "source": diag.gdn.source,
            "backend": diag.backendEffective,
            "asks": "\(LlamaGdnRuntimeObserver.shared.evalAskCount())",
            "compute": LlamaGdnRuntimeObserver.shared.didObserveCompute ? "yes" : "no",
        ])
        return ctx
    }

    /// Charge le GGUF avec backend Metal ou CPU.
    private static func loadModelPreferring(
        path: String,
        size: Int64,
        nGpuLayers: Int32,
        useMetal: Bool,
        useMmap: Bool,
        metalName: String?
    ) throws -> OpaquePointer? {
        guard let cpuDev = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU) else {
            throw LlamaError.couldNotInitializeContext(
                "backend CPU introuvable.\(LlamaLogCapture.shared.summary)"
            )
        }

        let deviceSlots = UnsafeMutablePointer<ggml_backend_dev_t?>.allocate(capacity: 3)
        defer { deviceSlots.deallocate() }

        if useMetal {
            // Préférer le device nommé Metal ; sinon premier GPU.
            var metalDev: ggml_backend_dev_t?
            let count = Int(ggml_backend_dev_count())
            for i in 0..<count {
                guard let dev = ggml_backend_dev_get(i) else { continue }
                let name = String(cString: ggml_backend_dev_name(dev))
                if name.localizedCaseInsensitiveContains("metal") {
                    metalDev = dev
                    break
                }
            }
            if metalDev == nil {
                metalDev = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU)
            }
            guard let metalDev else {
                return nil
            }
            _ = metalName
            deviceSlots[0] = metalDev
            deviceSlots[1] = cpuDev
            deviceSlots[2] = nil
        } else {
            deviceSlots[0] = cpuDev
            deviceSlots[1] = nil
        }

        var model_params = llama_model_default_params()
        model_params.n_gpu_layers = nGpuLayers
        model_params.load_mode = useMmap ? LLAMA_LOAD_MODE_MMAP : LLAMA_LOAD_MODE_NONE
        model_params.devices = deviceSlots

        if let loaded = loadModel(at: path, params: model_params) {
            purgeStagedCopy(of: path)
            return loaded
        }

        // Fallback mmap → none (déjà géré par l’appelant pour CPU ; ici aussi pour Metal).
        if useMmap {
            model_params.load_mode = LLAMA_LOAD_MODE_NONE
            if let loaded = loadModel(at: path, params: model_params) {
                purgeStagedCopy(of: path)
                return loaded
            }
        }

        // Staging path historique (ENOENT Application Support).
        if LlamaLogCapture.shared.reportsMissingGGUF {
            LocalModelFileAudit.snapshotFS(point: "before-stageForLlama", finalPath: path)
            if let stagedPath = try? stageForLlama(from: path, expectedSize: size) {
                LlamaLogCapture.shared.clear()
                if let stagedModel = loadModel(at: stagedPath, params: model_params) {
                    return stagedModel
                }
            }
        }
        return nil
    }

    private static func loadModel(at path: String, params: llama_model_params) -> OpaquePointer? {
        let phase = path.contains("/Library/ChatbotModels/")
            ? "before llama (Library/ChatbotModels sans espace)"
            : "before llama (Application Support)"
        LocalModelFileAudit.snapshotFS(point: "G-before-llama_model_load", finalPath: path)
        LlamaLogCapture.shared.recordFileDiagnostic(LlamaFileDiagnostics.report(path: path, phase: phase))
        let loaded = path.withCString { cPath in
            llama_model_load_from_file(cPath, params)
        }
        if loaded == nil {
            LocalModelFileAudit.snapshotFS(point: "H-after-llama_model_load-fail", finalPath: path)
        } else {
            LocalModelFileAudit.snapshotFS(point: "H-after-llama_model_load-ok", finalPath: path)
        }
        return loaded
    }

    /// Emplacement de la copie de secours pour un GGUF donné.
    private static func stagedCopyURL(for sourcePath: String) -> URL {
        let source = URL(fileURLWithPath: sourcePath)
        let library = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return library
            .appendingPathComponent("ChatbotModels", isDirectory: true)
            .appendingPathComponent(source.lastPathComponent)
    }

    /// La copie de secours n'était jamais reprise : une fois créée elle laissait
    /// un doublon de la taille du modèle (≈1,4 Go) pour toute la vie de l'app.
    /// Dès que le chemin normal fonctionne, elle n'a plus de raison d'exister.
    private static func purgeStagedCopy(of sourcePath: String) {
        let staged = stagedCopyURL(for: sourcePath)
        let path = staged.path(percentEncoded: false)
        guard path != sourcePath, FileManager.default.fileExists(atPath: path) else { return }
        LocalModelFileAudit.logFileDelete(path: path, caller: "purgeStagedCopy")
        try? FileManager.default.removeItem(at: staged)
    }

    /// Copie de secours, uniquement quand le runtime C ne sait pas ouvrir un
    /// GGUF que Foundation vient de lire. Le test est volontairement placé dans
    /// `Library/ChatbotModels`, sans espace, et ne supprime jamais l'original.
    private static func stageForLlama(from sourcePath: String, expectedSize: Int64) throws -> String {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: sourcePath)
        LlamaLogCapture.shared.recordFileDiagnostic(
            LlamaFileDiagnostics.report(path: sourcePath, phase: "before copy source")
        )
        let destination = stagedCopyURL(for: sourcePath)
        let directory = destination.deletingLastPathComponent()

        LocalModelFileAudit.snapshotFS(point: "stageForLlama-before-createDirectory", finalPath: sourcePath)
        let directoryPath = directory.path(percentEncoded: false)
        LocalModelFileAudit.logFSOp(
            "createDirectory",
            phase: "before",
            result: "pending",
            destination: directoryPath,
            watchedFinalPath: sourcePath
        )
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        LocalModelFileAudit.logFSOp(
            "createDirectory",
            phase: "after",
            result: "ok",
            destination: directoryPath,
            watchedFinalPath: sourcePath
        )
        LocalModelFileAudit.snapshotFS(point: "stageForLlama-after-createDirectory", finalPath: sourcePath)

        let destPath = destination.path(percentEncoded: false)
        if fm.fileExists(atPath: destPath) {
            LocalModelFileAudit.snapshotFS(point: "stageForLlama-before-removeItem-staged", finalPath: sourcePath)
            LocalModelFileAudit.logFSOp(
                "removeItem",
                phase: "before",
                result: "pending",
                source: destPath,
                watchedFinalPath: sourcePath
            )
            // Ne touche que la copie ChatbotModels, pas l'original Application Support.
            try fm.removeItem(at: destination)
            LocalModelFileAudit.logFSOp(
                "removeItem",
                phase: "after",
                result: "ok",
                source: destPath,
                watchedFinalPath: sourcePath
            )
            LocalModelFileAudit.snapshotFS(point: "stageForLlama-after-removeItem-staged", finalPath: sourcePath)
        }
        LocalModelFileAudit.snapshotFS(point: "stageForLlama-before-copyItem", finalPath: sourcePath)
        LocalModelFileAudit.logFSOp(
            "copyItem",
            phase: "before",
            result: "pending",
            source: sourcePath,
            destination: destPath,
            watchedFinalPath: sourcePath
        )
        try fm.copyItem(at: source, to: destination)
        LocalModelFileAudit.logFSOp(
            "copyItem",
            phase: "after",
            result: "ok",
            source: sourcePath,
            destination: destPath,
            watchedFinalPath: sourcePath
        )
        LocalModelFileAudit.snapshotFS(point: "stageForLlama-after-copyItem", finalPath: sourcePath)

        let stagedPath = destPath
        let stagedSize = (try fm.attributesOfItem(atPath: stagedPath)[.size] as? NSNumber)?.int64Value ?? 0
        guard stagedSize == expectedSize else {
            LocalModelFileAudit.snapshotFS(point: "stageForLlama-before-removeItem-incomplete", finalPath: sourcePath)
            LocalModelFileAudit.logFSOp(
                "removeItem",
                phase: "before-incomplete-staged",
                result: "pending",
                source: destPath,
                watchedFinalPath: sourcePath
            )
            try? fm.removeItem(at: destination)
            LocalModelFileAudit.snapshotFS(point: "stageForLlama-after-removeItem-incomplete", finalPath: sourcePath)
            throw LlamaError.couldNotInitializeContext("copie de secours GGUF incomplète")
        }
        guard let handle = try? FileHandle(forReadingFrom: destination) else {
            throw LlamaError.couldNotInitializeContext("copie de secours GGUF illisible")
        }
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
            LocalModelFileAudit.snapshotFS(point: "stageForLlama-before-removeItem-invalid", finalPath: sourcePath)
            LocalModelFileAudit.logFSOp(
                "removeItem",
                phase: "before-invalid-staged",
                result: "pending",
                source: destPath,
                watchedFinalPath: sourcePath
            )
            try? fm.removeItem(at: destination)
            LocalModelFileAudit.snapshotFS(point: "stageForLlama-after-removeItem-invalid", finalPath: sourcePath)
            throw LlamaError.couldNotInitializeContext("copie de secours GGUF invalide")
        }
        LlamaLogCapture.shared.recordFileDiagnostic(
            LlamaFileDiagnostics.report(path: stagedPath, phase: "after copy destination")
        )
        return stagedPath
    }

    /// Résultat d'ouverture : la config peut avoir été dégradée par rapport à
    /// la demande (contexte plus court, KV repassé en f16) si l'allocation échoue.
    struct ContextOpenResult {
        var context: LlamaContext
        var effectiveConfig: LlamaInferenceConfig
        var degraded: Bool
        var notes: [String]
    }

    private static func ggmlType(for kind: LlamaKVCacheType) -> ggml_type {
        switch kind {
        case .f16: return GGML_TYPE_F16
        case .q8_0: return GGML_TYPE_Q8_0
        case .q5_1: return GGML_TYPE_Q5_1
        case .q4_0: return GGML_TYPE_Q4_0
        }
    }

    /// Ouvre le contexte en descendant l'échelle `n_ctx`, puis en repliant le KV
    /// sur f16 si la quantification n'est pas supportée. On ne devine pas la
    /// limite jetsam : on tente, et on dégrade proprement.
    private static func openContext(
        model: OpaquePointer,
        config: LlamaInferenceConfig
    ) throws -> ContextOpenResult {
        var notes: [String] = []
        var kvCandidates: [(LlamaKVCacheType, LlamaKVCacheType)] = [(config.kvCacheTypeK, config.kvCacheTypeV)]
        if config.kvCacheTypeK != .f16 || config.kvCacheTypeV != .f16 {
            kvCandidates.append((.f16, .f16))
        }

        for nCtx in config.resolvedContextLadder {
            for (typeK, typeV) in kvCandidates {
                var attempt = config
                attempt.nCtx = nCtx
                attempt.kvCacheTypeK = typeK
                attempt.kvCacheTypeV = typeV
                if let ctx = tryInitContext(model: model, config: attempt) {
                    let degraded = nCtx != config.nCtx
                        || typeK != config.kvCacheTypeK
                        || typeV != config.kvCacheTypeV
                    if degraded {
                        notes.append(
                            "dégradé n_ctx \(config.nCtx)→\(nCtx) kv \(config.kvCacheTypeK.rawValue)/\(config.kvCacheTypeV.rawValue)→\(typeK.rawValue)/\(typeV.rawValue)"
                        )
                    }
                    return ContextOpenResult(
                        context: LlamaContext(model: model, context: ctx, config: attempt),
                        effectiveConfig: attempt,
                        degraded: degraded,
                        notes: notes
                    )
                }
                notes.append("échec n_ctx=\(nCtx) kv=\(typeK.rawValue)/\(typeV.rawValue)")
            }
        }

        llama_model_free(model)
        throw LlamaError.couldNotInitializeContext(
            "init contexte impossible (\(notes.joined(separator: " · "))).\(LlamaLogCapture.shared.summary)"
        )
    }

    private static func tryInitContext(
        model: OpaquePointer,
        config: LlamaInferenceConfig
    ) -> OpaquePointer? {
        var ctx_params = llama_context_default_params()
        ctx_params.n_ctx = config.nCtx
        ctx_params.n_batch = config.nBatch
        ctx_params.n_ubatch = min(config.nUbatch, config.nBatch)
        ctx_params.n_threads = LlamaInferenceConfig.resolvedThreads(explicit: config.nThreads)
        ctx_params.n_threads_batch = LlamaInferenceConfig.resolvedThreads(
            explicit: config.nThreadsBatch ?? config.nThreads
        )
        ctx_params.type_k = ggmlType(for: config.kvCacheTypeK)
        ctx_params.type_v = ggmlType(for: config.kvCacheTypeV)

        // Le callback GDN installe un eval callback sur *tout* le graphe ggml :
        // il empêche la fusion d'opérateurs et casse le batching. Diagnostic seul.
        if config.evalCallbackEnabled {
            ctx_params.cb_eval = llamaGdnEvalCallback
            ctx_params.cb_eval_user_data = nil
        }

        // Le KV quantifié exige Flash Attention côté Metal.
        switch config.effectiveFlashAttention {
        case .auto:
            ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        case .enabled:
            ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
        case .disabled:
            ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED
        }
        ctx_params.no_perf = false
        return llama_init_from_model(model, ctx_params)
    }

    private static func byteLabel(_ bytes: Int64) -> String {
        String(format: "%.0f Mo", Double(bytes) / 1_048_576.0)
    }

    func stop() {
        cancelRequested = true
    }

    func resetCancel() {
        cancelRequested = false
    }

    func model_info() -> String {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        result.initialize(repeating: Int8(0), count: 256)
        defer { result.deallocate() }

        let nChars = llama_model_desc(model, result, 256)
        let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nChars))
        var swiftString = ""
        for char in bufferPointer {
            swiftString.append(Character(UnicodeScalar(UInt8(bitPattern: char))))
        }
        return swiftString
    }

    private func completion_loop() throws -> String {
        if cancelRequested {
            is_done = true
            throw LlamaError.cancelled
        }

        // -1 = dernier logit produit (n_outputs), PAS batch.n_tokens-1 :
        // après un prefill de N tokens, un seul a logits=true → idx N-1 est hors bornes → EOS.
        let new_token_id = llama_sampler_sample(sampling, context, -1)

        // EOG / EOS : ne jamais décoder le token de contrôle en texte utilisateur.
        if llama_vocab_is_eog(vocab, new_token_id) || n_cur == n_len {
            is_done = true
            // Flush éventuels octets UTF-8 incomplets (pas le token EOG lui-même).
            let leftover = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            // Ne pas renvoyer de balises de contrôle résiduelles.
            return LocalChatTemplate.stripControlTokens(leftover, profile: .chatmlQwen)
        }

        let new_token_cchars = token_to_piece(token: new_token_id)
        temporary_invalid_cchars.append(contentsOf: new_token_cchars)
        let new_token_str: String
        if let string = String(validatingUTF8: temporary_invalid_cchars + [0]) {
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else if (0..<temporary_invalid_cchars.count).contains(where: {
            $0 != 0 && String(validatingUTF8: Array(temporary_invalid_cchars.suffix($0)) + [0]) != nil
        }) {
            let string = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else {
            new_token_str = ""
        }

        llama_batch_clear(&batch)
        llama_batch_add(&batch, new_token_id, n_cur, [0], true)

        n_decode += 1
        n_cur += 1

        if decodeObserved(batch) != 0 {
            is_done = true
            // Decode raté : le KV n'est plus fiable, on interdit toute réutilisation.
            resetKV()
        } else {
            // Le token vient d'entrer dans le KV : le miroir doit le refléter.
            kvTokens.append(new_token_id)
        }

        if cancelRequested {
            is_done = true
            throw LlamaError.cancelled
        }

        return new_token_str
    }

    /// Initialise puis boucle la completion en appelant `onToken` pour chaque pièce.
    func generate(
        prompt: String,
        maxTokens: Int32,
        images: [LocalVision.RGBBitmap] = [],
        mmprojPath: String? = nil,
        sampling samplingConfig: LlamaSamplingConfig? = nil,
        grammar: String? = nil,
        deadline: Date? = nil,
        onToken: @Sendable (String) async -> Void
    ) async throws {
        let effectiveSampling = samplingConfig ?? inferenceConfig.sampling
        // Prompt ChatML/Gemma déjà complet → pas de BOS supplémentaire (sinon EOS immédiat fréquent).
        if images.isEmpty {
            try await generateOnce(
                prompt: prompt,
                maxTokens: maxTokens,
                addBos: false,
                sampling: effectiveSampling,
                grammar: grammar,
                deadline: deadline,
                onToken: onToken
            )
            return
        }
        guard let mmprojPath, !mmprojPath.isEmpty else {
            throw LlamaError.couldNotInitializeContext(
                "mmproj absent — le GGUF texte n’embarque pas le projecteur vision."
            )
        }
        // Libère le projecteur après le tour : sur 6 Go, garder CLIP + GGUF texte
        // en parallèle entre deux messages augmente le risque jetsam.
        defer { unloadVision() }
        try await generateWithVision(
            prompt: prompt,
            images: images,
            mmprojPath: mmprojPath,
            maxTokens: maxTokens,
            addBos: false,
            sampling: effectiveSampling,
            deadline: deadline,
            onToken: onToken
        )
    }

    func unloadVision() {
        if let mtmdCtx {
            mtmd_free(mtmdCtx)
            self.mtmdCtx = nil
        }
    }

    private func ensureVision(mmprojPath: String) throws {
        if mtmdCtx != nil { return }
        LlamaLogCapture.shared.clear()
        llamaInstallLogCapture()
        var params = mtmd_context_params_default()
        params.use_gpu = inferenceConfig.preferMetal
        params.warmup = false
        params.print_timings = true
        params.n_threads = LlamaInferenceConfig.resolvedThreads(explicit: inferenceConfig.nThreads)
        params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED
        params.image_min_tokens = LocalVision.imageMinTokens
        let imageCap = inferenceConfig.imageMaxTokens > 0 ? inferenceConfig.imageMaxTokens : LocalVision.imageMaxTokens
        params.image_max_tokens = imageCap
        let loaded = mmprojPath.withCString { cPath in
            mtmd_init_from_file(cPath, model, params)
        }
        guard let loaded else {
            throw LlamaError.couldNotInitializeContext(
                "chargement mmproj impossible.\(LlamaLogCapture.shared.summary)"
            )
        }
        if !mtmd_support_vision(loaded) {
            mtmd_free(loaded)
            throw LlamaError.couldNotInitializeContext("ce mmproj ne déclare pas de vision")
        }
        mtmdCtx = loaded
        print("[local-ai:vision] mmproj loaded path=\(mmprojPath)")
    }

    private func generateWithVision(
        prompt: String,
        images: [LocalVision.RGBBitmap],
        mmprojPath: String,
        maxTokens: Int32,
        addBos: Bool,
        sampling samplingConfig: LlamaSamplingConfig,
        deadline: Date?,
        onToken: @Sendable (String) async -> Void
    ) async throws {
        try ensureVision(mmprojPath: mmprojPath)
        guard let mctx = mtmdCtx else {
            throw LlamaError.couldNotInitializeContext("context mtmd nil")
        }

        cancelRequested = false
        is_done = false
        temporary_invalid_cchars = []
        n_decode = 0
        resetKV()
        // mtmd écrit des tokens image dans le KV dont on ne connaît pas les ids :
        // le miroir devient incomplet, donc inutilisable comme préfixe.
        kvMirrorValid = false
        ensureSampler(samplingConfig, grammar: nil)

        var bitmaps: [OpaquePointer] = []
        defer {
            for bitmap in bitmaps { mtmd_bitmap_free(bitmap) }
        }
        for image in images.prefix(LocalVision.maxImagesPerTurn) {
            let bmp: OpaquePointer? = image.rgb.withUnsafeBytes { raw in
                guard let pixels = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                return mtmd_bitmap_init(UInt32(image.width), UInt32(image.height), pixels)
            }
            guard let bmp else {
                throw LlamaError.couldNotInitializeContext("bitmap RGB impossible")
            }
            bitmaps.append(bmp)
        }
        guard !bitmaps.isEmpty else {
            throw LlamaError.couldNotInitializeContext("aucune image décodable")
        }

        guard let chunks = mtmd_input_chunks_init() else {
            throw LlamaError.couldNotInitializeContext("mtmd_input_chunks_init")
        }
        defer { mtmd_input_chunks_free(chunks) }

        // `const mtmd_bitmap * const *` s’importe en `UnsafePointer<OpaquePointer?>`.
        var bitmapRefs: [OpaquePointer?] = bitmaps.map { Optional($0) }
        let tokenRc: Int32 = prompt.withCString { cPrompt in
            var textIn = mtmd_input_text(
                text: cPrompt,
                text_len: strlen(cPrompt),
                add_special: addBos,
                parse_special: true
            )
            return bitmapRefs.withUnsafeBufferPointer { buf in
                mtmd_tokenize(
                    mctx,
                    chunks,
                    &textIn,
                    buf.baseAddress,
                    buf.count
                )
            }
        }
        if tokenRc != 0 {
            throw LlamaError.couldNotInitializeContext("mtmd_tokenize rc=\(tokenRc)")
        }

        let nTokens = Int(mtmd_helper_get_n_tokens(chunks))
        let nCtx = Int(llama_n_ctx(context))
        if nTokens >= nCtx {
            throw LlamaError.promptExceedsContext(promptTokens: nTokens, nCtx: nCtx)
        }
        let maxGen = min(Int(max(1, maxTokens)), max(1, nCtx - nTokens - 1))
        n_len = Int32(nTokens + maxGen)
        promptTokenCount = nTokens

        let promptStarted = Date()
        var nPast: llama_pos = 0
        let evalRc = mtmd_helper_eval_chunks(
            mctx,
            context,
            chunks,
            0,
            0,
            Int32(inferenceConfig.nBatch),
            true,
            &nPast
        )
        lastPromptEvalSeconds = Date().timeIntervalSince(promptStarted)
        if evalRc != 0 {
            throw LlamaError.couldNotInitializeContext("mtmd_helper_eval_chunks rc=\(evalRc)")
        }
        n_cur = nPast
        print(
            "[local-ai:vision] n_tokens=\(nTokens) n_past=\(nPast) encode=\(Int(lastPromptEvalSeconds * 1000))ms"
        )

        var generatedPieces = 0
        while !is_done {
            if cancelRequested { throw LlamaError.cancelled }
            if let deadline, Date() >= deadline {
                is_done = true
                break
            }
            let piece = try completion_loop()
            if !piece.isEmpty {
                generatedPieces += 1
                await onToken(piece)
            }
        }
        if generatedPieces == 0 {
            throw LlamaError.couldNotInitializeContext("génération vision vide")
        }
    }

    private func generateOnce(
        prompt: String,
        maxTokens: Int32,
        addBos: Bool,
        sampling samplingConfig: LlamaSamplingConfig,
        grammar: String?,
        deadline: Date?,
        onToken: @Sendable (String) async -> Void
    ) async throws {
        cancelRequested = false
        is_done = false
        temporary_invalid_cchars = []
        n_decode = 0
        ensureSampler(samplingConfig, grammar: grammar)

        let promptTokens = tokenize(text: prompt, add_bos: addBos)
        guard !promptTokens.isEmpty else {
            throw LlamaError.couldNotInitializeContext("tokenization vide")
        }
        let nCtx = Int(llama_n_ctx(context))
        if promptTokens.count >= nCtx {
            WorkflowTrace.log("llama", [
                "n_ctx": "\(nCtx)",
                "prompt_tokens": "\(promptTokens.count)",
                "n_batch": "\(inferenceConfig.nBatch)",
                "n_ubatch": "\(inferenceConfig.nUbatch)",
            ])
            throw LlamaError.promptExceedsContext(promptTokens: promptTokens.count, nCtx: nCtx)
        }
        let maxGen = min(Int(max(1, maxTokens)), max(1, nCtx - promptTokens.count - 1))
        n_len = Int32(promptTokens.count + maxGen)
        tokens_list = promptTokens
        promptTokenCount = tokens_list.count

        // Réutilisation du préfixe KV : le prompt système et tout l'historique
        // sont déjà encodés depuis le tour précédent. Seul le delta est préfillé.
        let nKeep = trimKV(to: reusablePrefixLength(for: promptTokens))
        lastReusedPrefixTokens = nKeep

        WorkflowTrace.log("llama", [
            "n_ctx": "\(nCtx)",
            "n_batch": "\(inferenceConfig.nBatch)",
            "n_ubatch": "\(inferenceConfig.nUbatch)",
            "prompt_tokens": "\(promptTokens.count)",
            "kv_reused": "\(nKeep)",
            "prefill_tokens": "\(promptTokens.count - nKeep)",
            "reserved_output": "\(maxGen)",
        ])

        let promptStarted = Date()
        try prefill(promptTokens, from: nKeep)
        lastPromptEvalSeconds = Date().timeIntervalSince(promptStarted)

        var generatedPieces = 0
        var sampledTokens = 0
        while !is_done {
            if cancelRequested { throw LlamaError.cancelled }
            if let deadline, Date() >= deadline {
                // Budget dépassé : rendre le texte déjà produit vaut mieux qu'une erreur.
                print("[local-ai:gen] deadline atteinte après \(sampledTokens) tokens")
                is_done = true
                break
            }
            let piece = try completion_loop()
            sampledTokens += 1
            if sampledTokens == 1 {
                print(
                    "[local-ai:gen] promptTok=\(promptTokens.count) kvReused=\(nKeep) firstPiece=\(piece.prefix(40).debugDescription) empty=\(piece.isEmpty)"
                )
            }
            if !piece.isEmpty {
                generatedPieces += 1
                await onToken(piece)
            }
        }

        guard generatedPieces == 0 else { return }

        // EOG immédiat / aucune pièce → une seule reprise, KV neuf et BOS inversé.
        print("[local-ai:gen] empty generation — retry once (bos=\(!addBos))")
        cancelRequested = false
        is_done = false
        temporary_invalid_cchars = []
        n_decode = 0
        resetKV()
        llama_sampler_reset(sampling)
        let retryTokens = tokenize(text: prompt, add_bos: !addBos)
        guard !retryTokens.isEmpty else {
            throw LlamaError.couldNotInitializeContext("génération vide (EOG immédiat)")
        }
        if retryTokens.count >= nCtx {
            throw LlamaError.promptExceedsContext(promptTokens: retryTokens.count, nCtx: nCtx)
        }
        tokens_list = retryTokens
        promptTokenCount = tokens_list.count
        let retryGen = min(Int(max(1, maxTokens)), max(1, nCtx - retryTokens.count - 1))
        n_len = Int32(retryTokens.count + retryGen)
        lastReusedPrefixTokens = 0
        try prefill(retryTokens, from: 0)
        while !is_done {
            if cancelRequested { throw LlamaError.cancelled }
            if let deadline, Date() >= deadline {
                is_done = true
                break
            }
            let piece = try completion_loop()
            if !piece.isEmpty {
                await onToken(piece)
            }
        }
    }

    func clear() {
        tokens_list.removeAll()
        temporary_invalid_cchars.removeAll()
        cancelRequested = false
        is_done = false
        n_decode = 0
        resetKV()
    }

    func countTokens(_ text: String) -> Int {
        tokenize(text: text, add_bos: false).count
    }

    private func tokenize(text: String, add_bos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        // parse_special=true : <|im_start|> / <think> deviennent des tokens spéciaux, pas du texte brut.
        return text.utf8CString.withUnsafeBufferPointer { buffer -> [llama_token] in
            guard let base = buffer.baseAddress else { return [] }
            let cText = UnsafePointer<CChar>(base)
            var cap = utf8Count + (add_bos ? 1 : 0) + 16
            var tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: cap)
            var count = llama_tokenize(vocab, cText, Int32(utf8Count), tokens, Int32(cap), add_bos, true)
            if count < 0 {
                tokens.deallocate()
                cap = Int(-count)
                tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: cap)
                count = llama_tokenize(vocab, cText, Int32(utf8Count), tokens, Int32(cap), add_bos, true)
            }
            defer { tokens.deallocate() }
            guard count > 0 else { return [] }
            return Array(UnsafeBufferPointer(start: tokens, count: Int(count)))
        }
    }

    /// - note: Le résultat ne contient pas de null-terminator.
    private func token_to_piece(token: llama_token) -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer { result.deallocate() }
        let nTokens = llama_token_to_piece(vocab, token, result, 8, 0, true)

        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
            defer { newResult.deallocate() }
            let nNewTokens = llama_token_to_piece(vocab, token, newResult, -nTokens, 0, true)
            let bufferPointer = UnsafeBufferPointer(start: newResult, count: Int(nNewTokens))
            return Array(bufferPointer)
        } else {
            let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nTokens))
            return Array(bufferPointer)
        }
    }
}

#else

/// Stub quand le module `llama` n’est pas lié — les appels réels passent par `LocalInferenceEngine`.
enum LlamaError: Error, LocalizedError {
    case couldNotInitializeContext(String)
    case promptExceedsContext(promptTokens: Int, nCtx: Int)
    case cancelled
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext(let detail):
            return detail
        case .promptExceedsContext:
            return "Le contexte de cette recherche est trop volumineux. Je réduis automatiquement les résultats."
        case .cancelled:
            return "Génération annulée."
        case .notAvailable:
            return "Runtime llama indisponible."
        }
    }
}

#endif
