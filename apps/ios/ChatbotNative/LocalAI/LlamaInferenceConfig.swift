import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Inference performance config (paramétrique, pas de gating features)

enum LlamaFlashAttentionMode: String, Sendable, Codable, Hashable, CaseIterable {
    case auto
    case enabled
    case disabled
}

/// Paramètres llama.cpp / moteur — branchés via ExecutionProfile, pas via if Qwen/Gemma métier.
struct LlamaInferenceConfig: Equatable, Sendable, Hashable, Codable {
    /// -1 = toutes les couches GPU possibles ; 0 = CPU only.
    var nGpuLayers: Int32
    var preferMetal: Bool
    var nCtx: UInt32
    var nBatch: UInt32
    var nUbatch: UInt32
    /// `nil` = dérivé de `processorCount` (A15 ≈ 4 threads utiles).
    var nThreads: Int32?
    var nThreadsBatch: Int32?
    var flashAttention: LlamaFlashAttentionMode
    var useMmap: Bool
    /// Temperature applied to llama sampler chain at context creation.
    var temperature: Float
    var topP: Float
    /// 0 = sampler top-k désactivé.
    var topK: Int32
    /// Plafond tokens image mtmd. Qwen conserve 192 via `a15Default`.
    var imageMaxTokens: Int32

    /// Profil sûr pour A15 / 6 Go — Metal tenté, fallback CPU côté loader.
    static let a15Default = LlamaInferenceConfig(
        nGpuLayers: -1,
        preferMetal: true,
        nCtx: 2048,
        nBatch: 512,
        nUbatch: 256,
        nThreads: nil,
        nThreadsBatch: nil,
        flashAttention: .auto,
        useMmap: true,
        temperature: 0.7,
        topP: 0.9,
        topK: 0,
        imageMaxTokens: 192
    )

    static func resolvedThreads(explicit: Int32?) -> Int32 {
        if let explicit, explicit > 0 { return explicit }
        // A15 : 2P+4E — laisser 2 cœurs au système / UI.
        let count = ProcessInfo.processInfo.processorCount
        return Int32(max(1, min(4, count - 2)))
    }
}

/// Snapshot diagnostic après load — pour confirmer Metal / GPU layers sur appareil.
struct LlamaLoadDiagnostics: Equatable, Sendable, Codable {
    var modelPath: String
    var modelId: String?
    var quant: String?
    var fileBytes: Int64
    var backendRequested: String
    var backendEffective: String
    var metalAvailable: Bool
    var metalDeviceName: String?
    var cpuDeviceName: String?
    var nGpuLayersConfigured: Int32
    var nLayerModel: Int32?
    var nCtx: UInt32
    var nBatch: UInt32
    var nUbatch: UInt32
    var nThreads: Int32
    var nThreadsBatch: Int32
    var flashAttention: String
    var usedMmap: Bool
    var loadDurationMs: Double
    var fellBackToCPU: Bool
    var fallbackReason: String?
    var llamaLogTail: String
    var estimatedKVBytesHint: Int64?
    /// Chemin GDN observé (logs sched_reserve + cb_eval). Pas une déduction « logs vides = UNKNOWN ».
    var gdn: LlamaGdnProbeObservation = .unknown

    var summaryLine: String {
        let layers: String
        if let nLayerModel {
            layers = "layers=\(nLayerModel) gpuCfg=\(nGpuLayersConfigured)"
        } else {
            layers = "gpuCfg=\(nGpuLayersConfigured)"
        }
        return [
            "backend=\(backendEffective)",
            metalAvailable ? "metal=yes(\(metalDeviceName ?? "?"))" : "metal=no",
            layers,
            "ctx=\(nCtx) batch=\(nBatch)/\(nUbatch)",
            "threads=\(nThreads)/\(nThreadsBatch)",
            "fa=\(flashAttention)",
            "gdn=\(gdn.probe)/ar=\(gdn.fusedAR)/ch=\(gdn.fusedCH)/auto=\(gdn.autoFgdn)",
            fellBackToCPU ? "FALLBACK_CPU" : "as_requested",
            String(format: "load=%.0fms", loadDurationMs),
        ].joined(separator: " ")
    }
}

/// Probe backends ggml sans charger de modèle.
struct LlamaBackendProbe: Equatable, Sendable {
    var metalAvailable: Bool
    var metalName: String?
    var cpuAvailable: Bool
    var cpuName: String?
    var deviceCount: Int
    var deviceSummaries: [String]
}
