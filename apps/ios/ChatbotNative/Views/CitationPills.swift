import SwiftUI
import UIKit

// MARK: - Model

struct InlineCitation: Identifiable, Hashable {
    let id: String
    let source: SearchSourceDTO
    let label: String
    /// Citations supplémentaires regroupées (affichage « +N »).
    var extraCount: Int = 0

    var accessibilityLabel: String {
        extraCount > 0 ? "Source \(label), plus \(extraCount)" : "Source \(label)"
    }
}

enum CitationSegment: Hashable {
    case text(String)
    case citation(InlineCitation)
}

// MARK: - Parser

enum CitationParser {
    /// Toute parenthèse contenant au moins un `web_N` :
    /// `(Digitiz, web_1)`, `(voir web_3, web_8)`, `(web_13)`, `(voir web_15, web_17, web_13)`.
    private static let parenGroupRegex = try! NSRegularExpression(
        pattern: #"\(([^)\n]*\bweb_\d+\b[^)\n]*)\)"#,
        options: [.caseInsensitive]
    )
    private static let bracketWebRegex = try! NSRegularExpression(
        pattern: #"\[web_(\d+)\]"#,
        options: [.caseInsensitive]
    )
    private static let bareWebRegex = try! NSRegularExpression(
        pattern: #"(?<![\w/])web_(\d+)(?!\w)"#,
        options: [.caseInsensitive]
    )
    private static let webIndexRegex = try! NSRegularExpression(
        pattern: #"\bweb_(\d+)\b"#,
        options: [.caseInsensitive]
    )
    /// `[label](https://…)`
    private static let markdownLinkRegex = try! NSRegularExpression(
        pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#,
        options: [.caseInsensitive]
    )
    /// `(https://…)` — URL seule entre parenthèses (souvent en fin de puce).
    private static let parenURLRegex = try! NSRegularExpression(
        pattern: #"\((https?://[^)\s]+)\)"#,
        options: [.caseInsensitive]
    )
    /// URL nue dans le texte.
    private static let bareURLRegex = try! NSRegularExpression(
        pattern: #"(?<![\w/@])(https?://[^\s<>\[\]\"']+)"#,
        options: [.caseInsensitive]
    )

    static func containsMarker(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return parenGroupRegex.firstMatch(in: text, range: range) != nil
            || bracketWebRegex.firstMatch(in: text, range: range) != nil
            || bareWebRegex.firstMatch(in: text, range: range) != nil
            || markdownLinkRegex.firstMatch(in: text, range: range) != nil
            || parenURLRegex.firstMatch(in: text, range: range) != nil
            || bareURLRegex.firstMatch(in: text, range: range) != nil
    }

    static func segments(in text: String, sources: [SearchSourceDTO]) -> [CitationSegment] {
        guard !text.isEmpty, containsMarker(text) else { return [.text(text)] }

        struct Hit {
            let range: Range<String.Index>
            let citations: [InlineCitation]
        }

        var hits: [Hit] = []
        let full = NSRange(text.startIndex..<text.endIndex, in: text)

        parenGroupRegex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let innerRange = Range(match.range(at: 1), in: text)
            else { return }
            let inner = String(text[innerRange])
            let citations = citations(fromWebRefsIn: inner, sources: sources, location: match.range.location)
            // Toujours consommer le marqueur — même si aucun index n’est résolu (évite le texte brut).
            hits.append(Hit(range: fullRange, citations: citations))
        }

        bracketWebRegex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let numRange = Range(match.range(at: 1), in: text),
                  let webIndex = Int(text[numRange])
            else { return }
            if hits.contains(where: { $0.range.overlaps(fullRange) }) { return }
            hits.append(
                Hit(
                    range: fullRange,
                    citations: citations(forIndices: [webIndex], sources: sources, location: match.range.location)
                )
            )
        }

        bareWebRegex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let numRange = Range(match.range(at: 1), in: text),
                  let webIndex = Int(text[numRange])
            else { return }
            if hits.contains(where: { $0.range.overlaps(fullRange) }) { return }
            hits.append(
                Hit(
                    range: fullRange,
                    citations: citations(forIndices: [webIndex], sources: sources, location: match.range.location)
                )
            )
        }

        // Liens markdown / URLs nues → mêmes pastilles (persistantes via le contenu message).
        markdownLinkRegex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let labelRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text)
            else { return }
            if hits.contains(where: { $0.range.overlaps(fullRange) }) { return }
            let label = String(text[labelRange])
            let url = String(text[urlRange])
            hits.append(
                Hit(
                    range: fullRange,
                    citations: citations(forURL: url, hint: label, sources: sources, location: match.range.location)
                )
            )
        }

        parenURLRegex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let urlRange = Range(match.range(at: 1), in: text)
            else { return }
            if hits.contains(where: { $0.range.overlaps(fullRange) }) { return }
            let url = String(text[urlRange])
            hits.append(
                Hit(
                    range: fullRange,
                    citations: citations(forURL: url, hint: nil, sources: sources, location: match.range.location)
                )
            )
        }

        bareURLRegex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match,
                  var fullRange = Range(match.range, in: text),
                  let urlRange = Range(match.range(at: 1), in: text)
            else { return }
            if hits.contains(where: { $0.range.overlaps(fullRange) }) { return }
            var url = String(text[urlRange])
            // Trim ponctuation finale hors URL.
            while let last = url.last, ".,;:!?".contains(last) {
                url.removeLast()
                if fullRange.upperBound > fullRange.lowerBound {
                    fullRange = fullRange.lowerBound..<text.index(before: fullRange.upperBound)
                }
            }
            guard url.lowercased().hasPrefix("http") else { return }
            hits.append(
                Hit(
                    range: fullRange,
                    citations: citations(forURL: url, hint: nil, sources: sources, location: match.range.location)
                )
            )
        }

        hits.sort { $0.range.lowerBound < $1.range.lowerBound }

        var filtered: [Hit] = []
        var cursor = text.startIndex
        for hit in hits where hit.range.lowerBound >= cursor {
            filtered.append(hit)
            cursor = hit.range.upperBound
        }
        guard !filtered.isEmpty else { return [.text(text)] }

        var out: [CitationSegment] = []
        var idx = text.startIndex
        for hit in filtered {
            if idx < hit.range.lowerBound {
                let chunk = String(text[idx..<hit.range.lowerBound])
                if !chunk.isEmpty { out.append(.text(chunk)) }
            }
            for cite in hit.citations {
                out.append(.citation(cite))
            }
            idx = hit.range.upperBound
        }
        if idx < text.endIndex {
            let chunk = String(text[idx...])
            if !chunk.isEmpty { out.append(.text(chunk)) }
        }
        return mergeAdjacent(out)
    }

    static func splitContent(in text: String, sources: [SearchSourceDTO]) -> (text: String, citations: [InlineCitation]) {
        let parts = segments(in: text, sources: sources)
        let cleaned = parts.compactMap { seg -> String? in
            if case .text(let t) = seg { return t }
            return nil
        }
        .joined()
        .replacingOccurrences(of: #"  +"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #" +([.,;:!?])"#, with: "$1", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let citations = parts.compactMap { seg -> InlineCitation? in
            if case .citation(let c) = seg { return c }
            return nil
        }
        return (cleaned, citations)
    }

    // MARK: Resolve

    private static func citations(fromWebRefsIn inner: String, sources: [SearchSourceDTO], location: Int) -> [InlineCitation] {
        let indices = extractWebIndices(from: inner)
        let hint = namedDomainHint(from: inner, indices: indices)
        return citations(forIndices: indices, sources: sources, location: location, hint: hint)
    }

    private static func citations(
        forIndices indices: [Int],
        sources: [SearchSourceDTO],
        location: Int,
        hint: String? = nil
    ) -> [InlineCitation] {
        var seenURLs = Set<String>()
        var out: [InlineCitation] = []
        for (offset, webIndex) in indices.enumerated() {
            guard let source = resolveSource(webIndex: webIndex, sources: sources) else { continue }
            if seenURLs.contains(source.url) { continue }
            seenURLs.insert(source.url)
            out.append(
                InlineCitation(
                    id: "\(source.id)-w\(webIndex)-\(location)-\(offset)",
                    source: source,
                    label: displayLabel(hint: offset == 0 ? hint : nil, source: source)
                )
            )
        }
        return out
    }

    private static func extractWebIndices(from text: String) -> [Int] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var indices: [Int] = []
        webIndexRegex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let numRange = Range(match.range(at: 1), in: text),
                  let value = Int(text[numRange])
            else { return }
            indices.append(value)
        }
        return indices
    }

    /// `(Digitiz, web_1)` → `"Digitiz"`. Ignore `voir web_3, web_8`.
    private static func namedDomainHint(from inner: String, indices: [Int]) -> String? {
        guard indices.count == 1, let only = indices.first else { return nil }
        let pattern = #"^\s*(.+?)\s*,\s*web_"# + String(only) + #"\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(inner.startIndex..<inner.endIndex, in: inner)
        guard let match = regex.firstMatch(in: inner, range: range),
              let labelRange = Range(match.range(at: 1), in: inner)
        else { return nil }
        let hint = String(inner[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return isUsableHint(hint) ? hint : nil
    }

    private static func isUsableHint(_ hint: String) -> Bool {
        let lower = hint.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return false }
        if lower.contains("web_") { return false }
        if lower.hasPrefix("voir") { return false }
        if lower == "source" || lower == "sources" { return false }
        return true
    }

    private static func mergeAdjacent(_ segments: [CitationSegment]) -> [CitationSegment] {
        var out: [CitationSegment] = []
        for seg in segments {
            guard case .citation(let cite) = seg else {
                out.append(seg)
                continue
            }
            if case .citation(var last) = out.last,
               last.source.url == cite.source.url {
                last.extraCount += 1 + cite.extraCount
                out[out.count - 1] = .citation(last)
            } else {
                out.append(.citation(cite))
            }
        }
        return out
    }

    private static func resolveSource(webIndex: Int, sources: [SearchSourceDTO]) -> SearchSourceDTO? {
        guard !sources.isEmpty else { return nil }
        let i = webIndex - 1
        guard i >= 0, i < sources.count else { return nil }
        return sources[i]
    }

    /// Pastille pour une URL explicite — réutilise une source serveur si l’URL match, sinon synthétique.
    private static func citations(
        forURL rawURL: String,
        hint: String?,
        sources: [SearchSourceDTO],
        location: Int
    ) -> [InlineCitation] {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return [] }
        let source = sources.first(where: { $0.url == url || urlsMatch($0.url, url) })
            ?? syntheticSource(for: url, hint: hint)
        return [
            InlineCitation(
                id: "\(source.id)-url-\(location)",
                source: source,
                label: displayLabel(hint: hint, source: source)
            )
        ]
    }

    private static func urlsMatch(_ a: String, _ b: String) -> Bool {
        let na = a.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let nb = b.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return na == nb
    }

    private static func syntheticSource(for url: String, hint: String?) -> SearchSourceDTO {
        let host = URL(string: url)?.host
        let domain: String? = {
            guard var h = host, !h.isEmpty else { return nil }
            if h.lowercased().hasPrefix("www.") { h = String(h.dropFirst(4)) }
            return h
        }()
        let title: String = {
            if let hint, isUsableHint(hint) { return hint }
            return domain ?? url
        }()
        return SearchSourceDTO(
            id: "url-\(url.hashValue)",
            title: title,
            url: url,
            domain: domain,
            snippet: nil
        )
    }

    private static func displayLabel(hint: String?, source: SearchSourceDTO) -> String {
        if let hint, isUsableHint(hint) {
            var cleaned = hint
            if cleaned.lowercased().hasPrefix("https://") {
                cleaned = String(cleaned.dropFirst(8))
            } else if cleaned.lowercased().hasPrefix("http://") {
                cleaned = String(cleaned.dropFirst(7))
            }
            if cleaned.lowercased().hasPrefix("www.") {
                cleaned = String(cleaned.dropFirst(4))
            }
            return truncate(cleaned, max: 28)
        }
        if let domain = source.domain, !domain.isEmpty {
            let d = domain.lowercased().hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
            return truncate(d, max: 28)
        }
        if let host = URL(string: source.url)?.host {
            let d = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return truncate(d, max: 28)
        }
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, isUsableHint(title) {
            return truncate(title, max: 28)
        }
        return "Source"
    }

    private static func truncate(_ value: String, max: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max - 1)) + "…"
    }
}

// MARK: - Pill

struct SourcePillView: View {
    let citation: InlineCitation

    private var faviconURL: URL? {
        let host = citation.source.domain
            ?? URL(string: citation.source.url)?.host
            ?? citation.label
        var cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("www.") {
            cleaned = String(cleaned.dropFirst(4))
        }
        guard !cleaned.isEmpty,
              let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(encoded)&sz=64")
    }

    var body: some View {
        Button(action: openURL) {
            HStack(spacing: 5) {
                favicon
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.foreground.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(citation.accessibilityLabel)
        .accessibilityHint("Ouvre la source dans Safari")
    }

    private var title: String {
        citation.extraCount > 0 ? "\(citation.label) +\(citation.extraCount)" : citation.label
    }

    @ViewBuilder
    private var favicon: some View {
        Group {
            if let faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 14, height: 14)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "globe")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(AppTheme.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Circle().fill(AppTheme.surface.opacity(0.9)))
    }

    private func openURL() {
        guard let url = URL(string: citation.source.url) else { return }
        AppHaptics.light()
        UIApplication.shared.open(url)
    }
}

// MARK: - Flow layout

struct CitationFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, maxWidth.isFinite, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            maxX = max(maxX, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(
            width: maxWidth.isFinite ? maxWidth : maxX,
            height: y + rowHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sub.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Inline block

/// Remplace `(source, web_N)` / `(voir web_N, …)` par des pastilles cliquables.
struct CitationAwareInlineText: View {
    let text: String
    let sources: [SearchSourceDTO]
    var font: Font = CNFont.body
    var foreground: Color = AppTheme.foreground
    let attributed: (String) -> AttributedString

    var body: some View {
        let split = CitationParser.splitContent(in: text, sources: sources)
        VStack(alignment: .leading, spacing: 6) {
            if !split.text.isEmpty {
                Text(attributed(split.text))
                    .font(font)
                    .foregroundStyle(foreground)
                    .textSelection(.enabled)
            }
            if !split.citations.isEmpty {
                CitationFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(split.citations) { cite in
                        SourcePillView(citation: cite)
                    }
                }
            }
        }
    }
}
