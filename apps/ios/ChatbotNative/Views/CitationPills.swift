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
    /// `(Digitiz, web_1)`, `(olud.ai, web_3)`, `[web_1]`, `(web_2)`.
    private static let namedWebRegex = try! NSRegularExpression(
        pattern: #"\(([^)\n]{1,80}?),\s*web_(\d+)\)"#,
        options: [.caseInsensitive]
    )
    private static let bracketWebRegex = try! NSRegularExpression(
        pattern: #"\[web_(\d+)\]"#,
        options: [.caseInsensitive]
    )
    private static let parenWebRegex = try! NSRegularExpression(
        pattern: #"\(\s*web_(\d+)\s*\)"#,
        options: [.caseInsensitive]
    )

    static func containsMarker(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return namedWebRegex.firstMatch(in: text, range: range) != nil
            || bracketWebRegex.firstMatch(in: text, range: range) != nil
            || parenWebRegex.firstMatch(in: text, range: range) != nil
    }

    static func segments(in text: String, sources: [SearchSourceDTO]) -> [CitationSegment] {
        guard !text.isEmpty, containsMarker(text) else { return [.text(text)] }

        struct Hit {
            let range: Range<String.Index>
            let citation: InlineCitation
        }

        var hits: [Hit] = []
        let full = NSRange(text.startIndex..<text.endIndex, in: text)

        namedWebRegex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match,
                      let fullRange = Range(match.range, in: text),
                      let labelRange = Range(match.range(at: 1), in: text),
                      let numRange = Range(match.range(at: 2), in: text),
                      let webIndex = Int(text[numRange])
                else { return }
                let hint = String(text[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let source = source(atWebIndex: webIndex, sources: sources)
                    ?? source(matchingHint: hint, sources: sources)
                else { return }
                hits.append(
                    Hit(
                        range: fullRange,
                        citation: InlineCitation(
                            id: "\(source.id)-n\(webIndex)-\(match.range.location)",
                            source: source,
                            label: displayLabel(hint: hint, source: source)
                        )
                    )
                )
        }

        for regex in [bracketWebRegex, parenWebRegex] {
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match,
                      let fullRange = Range(match.range, in: text),
                      let numRange = Range(match.range(at: 1), in: text),
                      let webIndex = Int(text[numRange]),
                      let source = source(atWebIndex: webIndex, sources: sources)
                else { return }
                hits.append(
                    Hit(
                        range: fullRange,
                        citation: InlineCitation(
                            id: "\(source.id)-w\(webIndex)-\(match.range.location)",
                            source: source,
                            label: displayLabel(hint: nil, source: source)
                        )
                    )
                )
            }
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
            out.append(.citation(hit.citation))
            idx = hit.range.upperBound
        }
        if idx < text.endIndex {
            let chunk = String(text[idx...])
            if !chunk.isEmpty { out.append(.text(chunk)) }
        }
        return mergeAdjacent(out)
    }

    /// Texte nettoyé + pastilles (pour un rendu simple et stable).
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

    private static func source(atWebIndex webIndex: Int, sources: [SearchSourceDTO]) -> SearchSourceDTO? {
        let i = webIndex - 1
        guard i >= 0, i < sources.count else { return nil }
        return sources[i]
    }

    private static func source(matchingHint hint: String, sources: [SearchSourceDTO]) -> SearchSourceDTO? {
        let needle = hint.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        guard !needle.isEmpty else { return nil }
        return sources.first { src in
            let domain = (src.domain ?? URL(string: src.url)?.host ?? "").lowercased()
                .replacingOccurrences(of: "www.", with: "")
            let title = src.title.lowercased()
            return domain.contains(needle) || needle.contains(domain) || title.contains(needle)
        }
    }

    private static func displayLabel(hint: String?, source: SearchSourceDTO) -> String {
        if let hint, !hint.isEmpty {
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
        return truncate(source.title, max: 28)
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

/// Remplace `(source, web_N)` par des pastilles cliquables sous/à côté du texte.
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
