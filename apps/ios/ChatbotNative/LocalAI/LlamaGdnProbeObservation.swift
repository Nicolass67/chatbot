import Foundation

/// Observation **runtime** du probe Metal GDN de llama.cpp.
/// Parsée exclusivement depuis les logs C — jamais déduite du pin / du code Swift.
struct LlamaGdnProbeObservation: Equatable, Sendable, Codable {
    var fusedAR: String
    var fusedCH: String
    var autoFgdn: String
    var probe: String
    var reason: String
    var rawLines: [String]

    static let unknown = LlamaGdnProbeObservation(
        fusedAR: "UNKNOWN",
        fusedCH: "UNKNOWN",
        autoFgdn: "NOT_OBSERVED",
        probe: "UNKNOWN",
        reason: "aucune ligne GDN dans les logs llama.cpp",
        rawLines: []
    )

    /// Texte demandé pour syslog / rapport iPhone.
    var explicitReport: String {
        var lines = [
            "[local-ai:gdn] Qwen3.5 GDN:",
            "fused_ar = \(fusedAR)",
            "fused_ch = \(fusedCH)",
            "auto_fgdn = \(autoFgdn)",
            "probe = \(probe)",
        ]
        if !reason.isEmpty {
            lines.append("reason = \(reason)")
        }
        return lines.joined(separator: "\n")
    }

    static func isRelevantLogLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("gated delta net")
            || lower.contains("fused_gdn")
            || lower.contains("auto_fgdn")
    }

    static func parse(lines: [String]) -> LlamaGdnProbeObservation {
        let relevant = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isRelevantLogLine($0) }
        guard !relevant.isEmpty else { return .unknown }

        let probed = relevant.contains {
            $0.localizedCaseInsensitiveContains("resolving fused gated delta net support")
        }
        let ar = endpointState(
            lines: relevant,
            needle: "fused gated delta net (autoregressive)"
        )
        let ch = endpointState(
            lines: relevant,
            needle: "fused gated delta net (chunked)"
        )
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
        case ("UNKNOWN", "UNKNOWN"):
            probe = probed ? "UNKNOWN" : "UNKNOWN"
        default:
            if ar == "UNKNOWN" || ch == "UNKNOWN" {
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
        let reason: String
        if probe == "ENABLED", probed {
            reason = "—"
        } else if reasonParts.isEmpty {
            reason = "—"
        } else {
            reason = reasonParts.joined(separator: "; ")
        }
        return LlamaGdnProbeObservation(
            fusedAR: ar,
            fusedCH: ch,
            autoFgdn: auto,
            probe: probe,
            reason: reason,
            rawLines: relevant
        )
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
