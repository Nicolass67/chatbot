import Foundation

#if canImport(llama)
import llama

enum LlamaError: Error, LocalizedError {
    case couldNotInitializeContext(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext(let detail):
            return detail
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

    func clear() {
        lock.lock()
        lines.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        lines.append(trimmed)
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
        lock.unlock()
    }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        let tail = lines.suffix(6)
        guard !tail.isEmpty else { return "" }
        return " — " + tail.joined(separator: " · ")
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

private func llamaInstallLogCapture() {
    llama_log_set({ _, text, _ in
        guard let text else { return }
        LlamaLogCapture.shared.append(String(cString: text))
    }, nil)
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

/// Contexte llama.cpp — budget Qwen3 1.7B : `n_ctx = 2048` (KV cache iPhone).
/// Backend **CPU forcé** (Metal via `devices=NULL` fait échouer le load sur iPhone).
/// Classe `@unchecked Sendable` (pointeurs C) : accès sérialisé via `LocalInferenceEngine` (actor).
final class LlamaContext: @unchecked Sendable {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer
    private var sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private var tokens_list: [llama_token]
    private var temporary_invalid_cchars: [CChar]
    private var cancelRequested = false

    var is_done: Bool = false
    /// Longueur max de génération (tokens prompt + completion).
    var n_len: Int32 = 1024
    var n_cur: Int32 = 0
    var n_decode: Int32 = 0

    init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.tokens_list = []
        self.batch = llama_batch_init(512, 0, 1)
        self.temporary_invalid_cchars = []
        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(0.4))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(1234))
        vocab = llama_model_get_vocab(model)
    }

    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        // Ne pas appeler llama_backend_free() ici — une seule fois pour le process.
    }

    static func create_context(path: String) throws -> LlamaContext {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw LlamaError.couldNotInitializeContext("fichier absent: \(path)")
        }
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 1_000_000 else {
            throw LlamaError.couldNotInitializeContext("fichier trop petit (\(size) octets)")
        }

        LlamaLogCapture.shared.clear()
        llamaInstallLogCapture()

        // Charge les backends dynamiques (CPU / Metal) puis force CPU pour le modèle.
        ggml_backend_load_all()
        llama_backend_init()

        guard let cpuDev = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU) else {
            throw LlamaError.couldNotInitializeContext(
                "backend CPU introuvable.\(LlamaLogCapture.shared.summary)"
            )
        }

        // Liste NULL-terminée exigée par llama_model_params.devices.
        let deviceSlots = UnsafeMutablePointer<ggml_backend_dev_t?>.allocate(capacity: 2)
        defer { deviceSlots.deallocate() }
        deviceSlots[0] = cpuDev
        deviceSlots[1] = nil

        var model_params = llama_model_default_params()
        model_params.n_gpu_layers = 0
        model_params.load_mode = LLAMA_LOAD_MODE_MMAP
        // Importé en Swift comme `UnsafeMutablePointer<ggml_backend_dev_t?>`.
        model_params.devices = deviceSlots

        let model = loadModel(at: path, params: model_params)
        guard let model else {
            // Fallback sans mmap (certains volumes iOS / data-protection).
            model_params.load_mode = LLAMA_LOAD_MODE_NONE
            let retry = loadModel(at: path, params: model_params)
            guard let retry else {
                // `FileManager` et `FileHandle` ont déjà ouvert le même fichier
                // avec succès ci-dessus. Certaines builds iOS de llama.cpp échouent
                // néanmoins à faire `fopen` sur le segment "Application Support".
                // Ne copions qu'en présence de cet ENOENT précis : un échec mémoire
                // ou de parsing ne doit pas consommer 1,2 Go supplémentaires.
                if LlamaLogCapture.shared.reportsMissingGGUF,
                   let stagedPath = try? stageForLlama(from: path, expectedSize: size) {
                    LlamaLogCapture.shared.clear()
                    let stagedModel = loadModel(at: stagedPath, params: model_params)
                    if let stagedModel {
                        return try finishContext(model: stagedModel)
                    }
                }
                throw LlamaError.couldNotInitializeContext(
                    "chargement GGUF impossible (\(byteLabel(size))).\(LlamaLogCapture.shared.summary)"
                )
            }
            return try finishContext(model: retry)
        }

        return try finishContext(model: model)
    }

    private static func loadModel(at path: String, params: llama_model_params) -> OpaquePointer? {
        path.withCString { cPath in
            llama_model_load_from_file(cPath, params)
        }
    }

    /// Copie de secours, uniquement quand le runtime C ne sait pas ouvrir un
    /// GGUF que Foundation vient de lire. `tmp` n'a pas le segment avec espace
    /// de `Library/Application Support` et n'est jamais la source persistante.
    private static func stageForLlama(from sourcePath: String, expectedSize: Int64) throws -> String {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: sourcePath)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chatbot-models", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)

        let stagedPath = destination.path(percentEncoded: false)
        let stagedSize = (try fm.attributesOfItem(atPath: stagedPath)[.size] as? NSNumber)?.int64Value ?? 0
        guard stagedSize == expectedSize else {
            try? fm.removeItem(at: destination)
            throw LlamaError.couldNotInitializeContext("copie de secours GGUF incomplète")
        }
        guard let handle = try? FileHandle(forReadingFrom: destination) else {
            throw LlamaError.couldNotInitializeContext("copie de secours GGUF illisible")
        }
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
            try? fm.removeItem(at: destination)
            throw LlamaError.couldNotInitializeContext("copie de secours GGUF invalide")
        }
        return stagedPath
    }

    private static func finishContext(model: OpaquePointer) throws -> LlamaContext {
        let n_threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var ctx_params = llama_context_default_params()
        ctx_params.n_ctx = 2048
        ctx_params.n_batch = 512
        ctx_params.n_ubatch = 512
        ctx_params.n_threads = Int32(n_threads)
        ctx_params.n_threads_batch = Int32(n_threads)

        guard let context = llama_init_from_model(model, ctx_params) else {
            llama_model_free(model)
            throw LlamaError.couldNotInitializeContext(
                "init contexte impossible (mémoire ?).\(LlamaLogCapture.shared.summary)"
            )
        }
        return LlamaContext(model: model, context: context)
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

    func get_n_tokens() -> Int32 {
        batch.n_tokens
    }

    func completion_init(text: String) {
        cancelRequested = false
        is_done = false
        tokens_list = tokenize(text: text, add_bos: true)
        temporary_invalid_cchars = []

        let n_ctx = llama_n_ctx(context)
        let n_kv_req = tokens_list.count + (Int(n_len) - tokens_list.count)
        if n_kv_req > n_ctx {
            // KV trop petit — la génération s’arrêtera tôt ; pas de spam console.
        }

        llama_batch_clear(&batch)
        for i1 in 0..<tokens_list.count {
            let i = Int(i1)
            llama_batch_add(&batch, tokens_list[i], Int32(i), [0], false)
        }
        if batch.n_tokens > 0 {
            batch.logits[Int(batch.n_tokens) - 1] = 1
        }

        if llama_decode(context, batch) != 0 {
            is_done = true
        }
        n_cur = batch.n_tokens
    }

    func completion_loop() throws -> String {
        if cancelRequested {
            is_done = true
            throw LlamaError.cancelled
        }

        var new_token_id: llama_token = 0
        new_token_id = llama_sampler_sample(sampling, context, batch.n_tokens - 1)

        if llama_vocab_is_eog(vocab, new_token_id) || n_cur == n_len {
            is_done = true
            let new_token_str = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            return new_token_str
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

        if llama_decode(context, batch) != 0 {
            is_done = true
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
        onToken: @Sendable (String) async -> Void
    ) async throws {
        cancelRequested = false
        is_done = false
        n_len = Int32(tokenize(text: prompt, add_bos: true).count) + max(1, maxTokens)
        n_decode = 0
        completion_init(text: prompt)

        while !is_done {
            if cancelRequested {
                throw LlamaError.cancelled
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
        n_cur = 0
        n_decode = 0
        llama_memory_clear(llama_get_memory(context), true)
    }

    private func tokenize(text: String, add_bos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let n_tokens = utf8Count + (add_bos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: n_tokens)
        defer { tokens.deallocate() }
        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(n_tokens), add_bos, false)

        var swiftTokens: [llama_token] = []
        if tokenCount > 0 {
            for i in 0..<tokenCount {
                swiftTokens.append(tokens[Int(i)])
            }
        }
        return swiftTokens
    }

    /// - note: Le résultat ne contient pas de null-terminator.
    private func token_to_piece(token: llama_token) -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer { result.deallocate() }
        let nTokens = llama_token_to_piece(vocab, token, result, 8, 0, false)

        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
            defer { newResult.deallocate() }
            let nNewTokens = llama_token_to_piece(vocab, token, newResult, -nTokens, 0, false)
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
    case cancelled
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext(let detail):
            return detail
        case .cancelled:
            return "Génération annulée."
        case .notAvailable:
            return "Runtime llama indisponible."
        }
    }
}

#endif
