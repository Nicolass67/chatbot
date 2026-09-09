import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Marge mémoire réelle du processus (jetsam), pas la RAM installée.
///
/// iOS ne publie pas les limites jetsam et elles ne se déduisent pas de la RAM :
/// deux appareils 4 Go peuvent différer de 700 Mo. `os_proc_available_memory()`
/// est la seule source fiable. Avec `increased-memory-limit`, on gagne ~1 Go
/// sur A15/6 Go — mais c'est du best-effort, jamais une garantie.
enum DeviceMemoryGuard {
    /// Octets encore allouables avant jetsam. `nil` si l'API n'est pas disponible.
    static func availableBytes() -> Int64? {
#if canImport(Darwin) && !targetEnvironment(simulator)
        let value = os_proc_available_memory()
        return value > 0 ? Int64(value) : nil
#else
        return nil
#endif
    }

    /// Empreinte physique actuelle du processus.
    static func footprintBytes() -> Int64? {
#if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int64(info.phys_footprint)
#else
        return nil
#endif
    }

    /// Marge conservée pour iOS, les buffers Metal de calcul et l'UI.
    private static let systemReserveBytes: Int64 = 420 * 1_048_576

    /// Budget réellement utilisable par le runtime GGUF (poids + KV + compute).
    static func inferenceBudgetBytes() -> Int64? {
        guard let available = availableBytes() else { return nil }
        return max(0, available - systemReserveBytes)
    }

    /// Le modèle tient-il en mémoire ? `nil` = impossible à déterminer → on laisse passer.
    static func canAfford(weightsBytes: Int64, kvBytes: Int64) -> Bool? {
        guard let budget = inferenceBudgetBytes() else { return nil }
        // ~18 % de surcoût observé : buffers de calcul, graphe, activations, logits.
        let required = Int64(Double(weightsBytes + kvBytes) * 1.18)
        return required <= budget
    }

    static func summaryLine() -> String {
        let available = availableBytes().map { Self.mb($0) } ?? "?"
        let footprint = footprintBytes().map { Self.mb($0) } ?? "?"
        let budget = inferenceBudgetBytes().map { Self.mb($0) } ?? "?"
        return "available=\(available) footprint=\(footprint) inferenceBudget=\(budget)"
    }

    static func mb(_ bytes: Int64) -> String {
        String(format: "%.0fMo", Double(bytes) / 1_048_576.0)
    }
}

/// Estimation du KV cache pour dimensionner `n_ctx` avant d'ouvrir le contexte.
///
/// Formule exacte : `2 (K+V) * n_layer * n_embd_kv * n_ctx * bytesPerElement`.
/// `n_embd_kv = n_head_kv * head_dim` (GQA). Avant chargement on ne connaît pas
/// ces valeurs → estimation par famille, recalée après load via `llama_model_n_layer`.
struct KVCacheSizing: Equatable, Sendable {
    var nLayer: Int
    var nEmbdKV: Int

    /// Qwen3 / Qwen3.5 ~2B : 28 couches, 8 têtes KV × 128 = 1024.
    static let qwen35Dense2B = KVCacheSizing(nLayer: 28, nEmbdKV: 1024)
    /// Repli volontairement pessimiste pour les modèles non catalogués.
    static let conservative = KVCacheSizing(nLayer: 36, nEmbdKV: 1536)

    static func profile(for modelId: String) -> KVCacheSizing {
        modelId.hasPrefix("qwen35-2b") ? .qwen35Dense2B : .conservative
    }

    func bytes(context: Int, typeK: LlamaKVCacheType, typeV: LlamaKVCacheType) -> Int64 {
        let perToken = Double(nLayer) * Double(nEmbdKV)
        let k = perToken * typeK.bytesPerElement
        let v = perToken * typeV.bytesPerElement
        return Int64((k + v) * Double(context))
    }
}
