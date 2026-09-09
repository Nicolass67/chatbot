import Foundation

/// Chemin GDN réellement observé — pas une déduction « logs vides = UNKNOWN ».
enum LlamaGdnPathKind: String, Equatable, Sendable, Codable {
    case fusedMetal
    case decomposedMetal
    case cpuFallback
    case notApplicable
    case indeterminable

    var userFacingLabel: String {
        switch self {
        case .fusedMetal: return "Fused Metal confirmé"
        case .decomposedMetal: return "Chemin décomposé Metal confirmé"
        case .cpuFallback: return "CPU fallback confirmé"
        case .notApplicable: return "Sans GDN"
        case .indeterminable: return "Indéterminable"
        }
    }
}

struct LlamaGdnEvalHit: Equatable, Sendable, Codable {
    var opName: String
    var tensorName: String
    var deviceName: String
    var deviceIsCPU: Bool
    var deviceIsGPU: Bool
}

/// Observation runtime GDN : logs llama.cpp **et** nœuds réellement évalués (`cb_eval`).
struct LlamaGdnProbeObservation: Equatable, Sendable, Codable {
    var fusedAR: String
    var fusedCH: String
    var autoFgdn: String
    var probe: String
    var reason: String
    var rawLines: [String]
    var pathKind: LlamaGdnPathKind
    var source: String

    static let unknown = LlamaGdnProbeObservation(
        fusedAR: "UNKNOWN",
        fusedCH: "UNKNOWN",
        autoFgdn: "NOT_OBSERVED",
        probe: "INDETERMINABLE",
        reason: "Aucune instrumentation n’a encore observé le chemin GDN.",
        rawLines: [],
        pathKind: .indeterminable,
        source: "none"
    )

    var userFacingFusedLabel: String { pathKind.userFacingLabel }

    var userFacingFusedCaption: String {
        switch pathKind {
        case .fusedMetal:
            return "Opération GGML_OP_GATED_DELTA_NET exécutée sur Metal."
        case .decomposedMetal:
            return "Modèle GDN sur Metal, sans op fused observé — graphe décomposé."
        case .cpuFallback:
            return "Les nœuds GDN (ou le backend effectif) tournent sur CPU."
        case .notApplicable:
            return "Ce modèle n’utilise pas Gated Delta Net."
        case .indeterminable:
            return "Le runtime n’a pas fourni d’observation fiable (logs et callback d’exécution)."
        }
    }

    var explicitReport: String {
        var lines = [
            "[local-ai:gdn] Qwen3.5 GDN:",
            "path = \(pathKind.rawValue)",
            "label = \(userFacingFusedLabel)",
            "fused_ar = \(fusedAR)",
            "fused_ch = \(fusedCH)",
            "auto_fgdn = \(autoFgdn)",
            "probe = \(probe)",
            "source = \(source)",
        ]
        if !reason.isEmpty {
            lines.append("reason = \(reason)")
        }
        return lines.joined(separator: "\n")
    }

    static func modelImpliesGdnLayers(modelId: String?, architectureHint: String? = nil) -> Bool {
        let id = (modelId ?? "").lowercased()
        let arch = (architectureHint ?? "").lowercased()
        if id.contains("qwen35") || id.contains("qwen3.5") { return true }
        if arch.contains("qwen35") || arch.contains("qwen3.5") { return true }
        return false
    }

    static func isRelevantLogLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("gated delta net")
            || lower.contains("fused_gdn")
            || lower.contains("auto_fgdn")
            || lower.contains("fgdn")
            || lower.contains("gated_delta")
    }

    static func parse(lines: [String]) -> LlamaGdnProbeObservation {
        let relevant = expandedRelevantLines(lines)
        guard !relevant.isEmpty else { return .unknown }

        let probed = relevant.contains {
            $0.localizedCaseInsensitiveContains("resolving fused gated delta net support")
        }
        let ar = endpointState(lines: relevant, needle: "fused gated delta net (autoregressive)")
        let ch = endpointState(lines: relevant, needle: "fused gated delta net (chunked)")
        let mismatch = relevant.filter {
            $0.localizedCaseInsensitiveContains("usually due to missing support")
                || $0.localizedCaseInsensitiveContains("not supported, set to disabled")
        }
        let auto: String = probed ? "PROBED" : "NOT_OBSERVED"
        let probe: String
        switch (ar, ch) {
        case ("ENABLED", "ENABLED"):
            probe = "ENABLED"
        case ("DISABLED", "DISABLED"):
            probe = "DISABLED"
        default:
            if ar == "UNKNOWN" && ch == "UNKNOWN" {
                probe = "PARTIAL"
            } else {
                probe = "PARTIAL"
            }
        }
        var reasonParts: [String] = []
        if !probed {
            reasonParts.append("pas de ligne « resolving fused Gated Delta Net support »")
        }
        if ar == "UNKNOWN" || ch == "UNKNOWN" {
            reasonParts.append("endpoint enabled/disabled incomplet")
        }
        if !mismatch.isEmpty {
            reasonParts.append(mismatch.suffix(2).joined(separator: " | "))
        }
        if probe == "DISABLED" {
            reasonParts.append("probe Metal a désactivé le fused GDN")
        }
        let path: LlamaGdnPathKind
        if probe == "ENABLED" {
            path = .fusedMetal
        } else if probe == "DISABLED" {
            path = .decomposedMetal
        } else {
            path = .indeterminable
        }
        return LlamaGdnProbeObservation(
            fusedAR: ar,
            fusedCH: ch,
            autoFgdn: auto,
            probe: probe,
            reason: reasonParts.isEmpty ? "—" : reasonParts.joined(separator: "; "),
            rawLines: relevant,
            pathKind: path,
            source: "llama.cpp logs"
        )
    }

    /// Fusion logs + nœuds réellement évalués. Les logs vides ne forcent plus UNKNOWN.
    static func synthesize(
        logLines: [String],
        evalHits: [LlamaGdnEvalHit],
        modelHasGdnLayers: Bool,
        backendEffective: String?,
        didObserveCompute: Bool = false,
        evalAskCount: Int = 0
    ) -> LlamaGdnProbeObservation {
        if !modelHasGdnLayers {
            return LlamaGdnProbeObservation(
                fusedAR: "N/A",
                fusedCH: "N/A",
                autoFgdn: "N/A",
                probe: "NOT_APPLICABLE",
                reason: "Modèle sans couches Gated Delta Net.",
                rawLines: [],
                pathKind: .notApplicable,
                source: "architecture"
            )
        }

        let fromLogs = parse(lines: logLines)
        let fusedHits = evalHits.filter {
            $0.opName == "GATED_DELTA_NET" || $0.tensorName.lowercased().contains("fgdn")
        }
        let decomposedHits = evalHits.filter {
            $0.opName == "CUMSUM" || $0.opName == "SOLVE_TRI"
        }
        let backend = (backendEffective ?? "").lowercased()
        let backendIsCPU = backend == "cpu"
        let backendIsMetal = backend.contains("metal") || backend == "gpu"

        func arCh(from hits: [LlamaGdnEvalHit]) -> (String, String) {
            let names = hits.map { $0.tensorName.lowercased() }.joined(separator: " ")
            let ar = names.contains("fgdn_ar") || names.contains("fgdn-ar") ? "ENABLED" : fromLogs.fusedAR
            let ch = names.contains("fgdn_ch") || names.contains("fgdn-ch") ? "ENABLED" : fromLogs.fusedCH
            return (ar, ch)
        }

        func kindForHits(_ hits: [LlamaGdnEvalHit], fused: Bool) -> LlamaGdnPathKind {
            let onCPU = hits.contains(where: { $0.deviceIsCPU && !$0.deviceIsGPU })
            let onGPU = hits.contains(where: { $0.deviceIsGPU })
            if onCPU && !onGPU { return .cpuFallback }
            if onGPU { return fused ? .fusedMetal : .decomposedMetal }
            if backendIsCPU { return .cpuFallback }
            if backendIsMetal { return fused ? .fusedMetal : .decomposedMetal }
            return fused ? .fusedMetal : .decomposedMetal
        }

        if !fusedHits.isEmpty {
            let (ar, ch) = arCh(from: fusedHits)
            let kind = kindForHits(fusedHits, fused: true)
            let device = fusedHits.first?.deviceName ?? "?"
            if kind == .cpuFallback {
                return LlamaGdnProbeObservation(
                    fusedAR: ar,
                    fusedCH: ch,
                    autoFgdn: fromLogs.autoFgdn == "NOT_OBSERVED" ? "EVAL" : fromLogs.autoFgdn,
                    probe: "CPU_FALLBACK",
                    reason: "GGML_OP_GATED_DELTA_NET évalué sur CPU (\(device)).",
                    rawLines: fromLogs.rawLines,
                    pathKind: .cpuFallback,
                    source: "cb_eval"
                )
            }
            return LlamaGdnProbeObservation(
                fusedAR: ar == "UNKNOWN" ? "ENABLED" : ar,
                fusedCH: ch,
                autoFgdn: fromLogs.autoFgdn == "NOT_OBSERVED" ? "EVAL" : fromLogs.autoFgdn,
                probe: "ENABLED",
                reason: "GGML_OP_GATED_DELTA_NET évalué sur \(device).",
                rawLines: fromLogs.rawLines,
                pathKind: .fusedMetal,
                source: "cb_eval"
            )
        }

        if !decomposedHits.isEmpty {
            let kind = kindForHits(decomposedHits, fused: false)
            let device = decomposedHits.first?.deviceName ?? "?"
            if kind == .cpuFallback {
                return LlamaGdnProbeObservation(
                    fusedAR: fromLogs.fusedAR,
                    fusedCH: fromLogs.fusedCH,
                    autoFgdn: fromLogs.autoFgdn == "NOT_OBSERVED" ? "EVAL" : fromLogs.autoFgdn,
                    probe: "CPU_FALLBACK",
                    reason: "Ops GDN décomposées (CUMSUM/SOLVE_TRI) évaluées sur CPU (\(device)).",
                    rawLines: fromLogs.rawLines,
                    pathKind: .cpuFallback,
                    source: "cb_eval"
                )
            }
            return LlamaGdnProbeObservation(
                fusedAR: fromLogs.fusedAR,
                fusedCH: fromLogs.fusedCH,
                autoFgdn: fromLogs.autoFgdn == "NOT_OBSERVED" ? "EVAL" : fromLogs.autoFgdn,
                probe: "DECOMPOSED",
                reason: "Chemin GDN décomposé observé (\(decomposedHits.first?.opName ?? "CUMSUM") sur \(device)).",
                rawLines: fromLogs.rawLines,
                pathKind: .decomposedMetal,
                source: "cb_eval"
            )
        }

        // Le graphe a été parcouru : absence d’op fused = chemin décomposé, pas un UNKNOWN.
        if modelHasGdnLayers, evalAskCount > 0, didObserveCompute {
            if backendIsCPU {
                return LlamaGdnProbeObservation(
                    fusedAR: fromLogs.fusedAR,
                    fusedCH: fromLogs.fusedCH,
                    autoFgdn: fromLogs.autoFgdn,
                    probe: "CPU_FALLBACK",
                    reason: "Graphe parcouru sans GGML_OP_GATED_DELTA_NET ; backend effectif CPU.",
                    rawLines: fromLogs.rawLines,
                    pathKind: .cpuFallback,
                    source: "cb_eval"
                )
            }
            return LlamaGdnProbeObservation(
                fusedAR: fromLogs.fusedAR,
                fusedCH: fromLogs.fusedCH,
                autoFgdn: fromLogs.autoFgdn,
                probe: "DECOMPOSED",
                reason: "Graphe parcouru (\(evalAskCount) nœuds) sans GGML_OP_GATED_DELTA_NET — chemin décomposé.",
                rawLines: fromLogs.rawLines,
                pathKind: .decomposedMetal,
                source: "cb_eval"
            )
        }

        // Pas encore d’exécution observée : les logs de sched_reserve restent un indice, pas un UNKNOWN.
        if fromLogs.pathKind == .fusedMetal || fromLogs.pathKind == .decomposedMetal {
            var merged = fromLogs
            if fromLogs.pathKind == .decomposedMetal, backendIsCPU {
                merged.pathKind = .cpuFallback
                merged.probe = "CPU_FALLBACK"
                merged.reason = "Logs : fused désactivé ; backend effectif CPU."
            } else {
                merged.source = "llama.cpp logs"
                merged.reason = (merged.reason == "—" ? "" : merged.reason + " ; ")
                    + "Lu au load (sched_reserve), pas encore confirmé par cb_eval."
            }
            return merged
        }

        if modelHasGdnLayers, backendIsCPU, didObserveCompute {
            return LlamaGdnProbeObservation(
                fusedAR: fromLogs.fusedAR,
                fusedCH: fromLogs.fusedCH,
                autoFgdn: fromLogs.autoFgdn,
                probe: "CPU_FALLBACK",
                reason: "Modèle GDN exécuté sur backend CPU (callback d’ops non invoqué).",
                rawLines: fromLogs.rawLines,
                pathKind: .cpuFallback,
                source: "backendEffective"
            )
        }

        return LlamaGdnProbeObservation(
            fusedAR: fromLogs.fusedAR,
            fusedCH: fromLogs.fusedCH,
            autoFgdn: fromLogs.autoFgdn,
            probe: "INDETERMINABLE",
            reason: didObserveCompute
                ? "Inférence observée mais le callback d’évaluation n’a pas reçu le graphe (ask=0)."
                : "Pas encore d’exécution observée, et les logs llama.cpp ne tranchent pas.",
            rawLines: fromLogs.rawLines,
            pathKind: .indeterminable,
            source: "none"
        )
    }

    /// Relève aussi les lignes coupées (GGML_LOG_LEVEL_CONT) via le blob concaténé.
    private static func expandedRelevantLines(_ lines: [String]) -> [String] {
        var relevant = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isRelevantLogLine($0) }
        let blob = lines.joined()
        if relevant.isEmpty, isRelevantLogLine(blob) {
            relevant = blob
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && isRelevantLogLine($0) }
        }
        return relevant
    }

    private static func endpointState(lines: [String], needle: String) -> String {
        let hits = lines.filter { $0.lowercased().contains(needle) }
        guard !hits.isEmpty else { return "UNKNOWN" }
        if hits.contains(where: {
            let l = $0.lowercased()
            return l.contains("not supported") || l.contains("set to disabled")
        }) {
            return "DISABLED"
        }
        if hits.contains(where: { $0.lowercased().contains("enabled") }) {
            return "ENABLED"
        }
        return "UNKNOWN"
    }
}

/// Collecte logs + `cb_eval`. Observation seulement : ne change pas le graphe.
final class LlamaGdnRuntimeObserver: @unchecked Sendable {
    static let shared = LlamaGdnRuntimeObserver()

    private let lock = NSLock()
    private var logChunks: [String] = []
    private var pendingCont = ""
    private var evalHits: [LlamaGdnEvalHit] = []
    private var computeNodes = 0
    private var askCount = 0
    private var fusedAskGranted = 0
    private var decompAskGranted = 0

    var didObserveCompute: Bool {
        lock.lock(); defer { lock.unlock() }
        return computeNodes > 0
    }

    func resetForModelLoad() {
        lock.lock()
        logChunks.removeAll(keepingCapacity: true)
        pendingCont = ""
        evalHits.removeAll(keepingCapacity: true)
        computeNodes = 0
        askCount = 0
        fusedAskGranted = 0
        decompAskGranted = 0
        lock.unlock()
    }

    func noteAsk() {
        lock.lock()
        askCount += 1
        lock.unlock()
    }

    /// `ask=true` uniquement pour quelques nœuds GDN — ne pas casser le batching du graphe.
    func shouldObserve(opName: String, tensorName: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let op = opName.uppercased()
        let name = tensorName.lowercased()
        if op == "GATED_DELTA_NET" || name.contains("fgdn") {
            guard fusedAskGranted < 2 else { return false }
            fusedAskGranted += 1
            return true
        }
        if op == "CUMSUM" || op == "SOLVE_TRI" {
            guard decompAskGranted < 2 else { return false }
            decompAskGranted += 1
            return true
        }
        return false
    }

    func appendLog(levelRaw: Int32, text: String) {
        lock.lock()
        defer { lock.unlock() }
        // GGML_LOG_LEVEL_CONT = 5
        if levelRaw == 5 {
            pendingCont += text
            return
        }
        flushPendingLocked()
        pendingCont = text
        if text.contains("\n") {
            flushPendingLocked()
        }
    }

    func appendLogText(_ text: String) {
        appendLog(levelRaw: 2, text: text.hasSuffix("\n") ? text : text + "\n")
    }

    func recordEvalHit(_ hit: LlamaGdnEvalHit) {
        lock.lock()
        evalHits.append(hit)
        if evalHits.count > 64 {
            evalHits.removeFirst(evalHits.count - 64)
        }
        lock.unlock()
    }

    func markComputeNode() {
        lock.lock()
        computeNodes += 1
        lock.unlock()
    }

    func logLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var lines = logChunks
        let extra = pendingCont.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { lines.append(extra) }
        return lines
    }

    func hits() -> [LlamaGdnEvalHit] {
        lock.lock(); defer { lock.unlock() }
        return evalHits
    }

    func evalAskCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return askCount
    }

    func snapshot(modelHasGdnLayers: Bool, backendEffective: String?) -> LlamaGdnProbeObservation {
        LlamaGdnProbeObservation.synthesize(
            logLines: logLines(),
            evalHits: hits(),
            modelHasGdnLayers: modelHasGdnLayers,
            backendEffective: backendEffective,
            didObserveCompute: didObserveCompute,
            evalAskCount: evalAskCount()
        )
    }

    private func flushPendingLocked() {
        let trimmed = pendingCont.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingCont = ""
        guard !trimmed.isEmpty else { return }
        logChunks.append(trimmed)
        if logChunks.count > 400 {
            logChunks.removeFirst(logChunks.count - 400)
        }
    }
}
