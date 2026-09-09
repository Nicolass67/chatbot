import Foundation

#if canImport(llama)
import llama

enum LlamaError: Error {
    case couldNotInitializeContext
    case cancelled
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

/// Contexte llama.cpp — budget Qwen3 1.7B : `n_ctx = 4096`.
/// Metal sur appareil ; `n_gpu_layers = 0` sur simulateur.
actor LlamaContext {
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
        llama_model_free(model)
        llama_free(context)
        llama_backend_free()
    }

    static func create_context(path: String) throws -> LlamaContext {
        llama_backend_init()
        var model_params = llama_model_default_params()

#if targetEnvironment(simulator)
        model_params.n_gpu_layers = 0
#else
        // Metal sur appareil (couches GPU gérées par le backend llama Metal).
#endif

        let model = llama_model_load_from_file(path, model_params)
        guard let model else {
            throw LlamaError.couldNotInitializeContext
        }

        let n_threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))

        var ctx_params = llama_context_default_params()
        // Budget contexte Qwen3 1.7B.
        ctx_params.n_ctx = 4096
        ctx_params.n_threads = Int32(n_threads)
        ctx_params.n_threads_batch = Int32(n_threads)

        let context = llama_init_from_model(model, ctx_params)
        guard let context else {
            llama_model_free(model)
            throw LlamaError.couldNotInitializeContext
        }

        return LlamaContext(model: model, context: context)
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
enum LlamaError: Error {
    case couldNotInitializeContext
    case cancelled
    case notAvailable
}

#endif
