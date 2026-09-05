import SwiftUI
import UIKit

/// Blocs markdown natifs — headings, listes, code, tables, quotes, paragraphes.
public enum MarkdownBlock: Identifiable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case bullet([String])
    case numbered([String])
    case quote(String)
    case table(headers: [String], rows: [[String]])
    case thematicBreak

    public var id: String {
        switch self {
        case .heading(let l, let t): return "h\(l)-\(t.hashValue)"
        case .paragraph(let t): return "p-\(t.hashValue)"
        case .code(_, let c): return "c-\(c.hashValue)"
        case .bullet(let items): return "ul-\(items.joined().hashValue)"
        case .numbered(let items): return "ol-\(items.joined().hashValue)"
        case .quote(let t): return "q-\(t.hashValue)"
        case .table(let h, _): return "t-\(h.joined().hashValue)"
        case .thematicBreak: return "hr"
        }
    }
}

public enum MarkdownBlockParser {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            let text = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphBuffer = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.code(language: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                i += 1
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("> ") {
                        quoteLines.append(String(t.dropFirst(2)))
                        i += 1
                    } else if t == ">" {
                        quoteLines.append("")
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix("|") && trimmed.contains("|") {
                flushParagraph()
                var tableLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("|") {
                        tableLines.append(t)
                        i += 1
                    } else {
                        break
                    }
                }
                if let table = parseTable(tableLines) {
                    blocks.append(table)
                } else {
                    paragraphBuffer.append(contentsOf: tableLines)
                    flushParagraph()
                }
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") {
                        items.append(String(t.dropFirst(2)))
                        i += 1
                    } else if t.hasPrefix("* ") {
                        items.append(String(t.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bullet(items))
                continue
            }

            if let numbered = parseNumbered(trimmed) {
                flushParagraph()
                var items: [String] = [numbered]
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let n = parseNumbered(t) {
                        items.append(n)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.numbered(items))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraphBuffer.append(line)
            i += 1
        }
        flushParagraph()
        return blocks.isEmpty ? [.paragraph(markdown)] : blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, line.count > level else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " || rest.isEmpty else { return nil }
        return .heading(level: level, text: String(rest).trimmingCharacters(in: .whitespaces))
    }

    private static func parseNumbered(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dot]
        guard Int(prefix) != nil else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.hasPrefix(" ") else { return nil }
        return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func parseTable(_ lines: [String]) -> MarkdownBlock? {
        guard lines.count >= 2 else { return nil }
        let headers = splitRow(lines[0])
        guard !headers.isEmpty else { return nil }
        let sep = splitRow(lines[1])
        guard sep.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) || $0.contains("-") }) else {
            return nil
        }
        let rows = lines.dropFirst(2).map(splitRow).filter { !$0.isEmpty }
        return .table(headers: headers, rows: rows)
    }

    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Cache inline markdown — évite AttributedString(markdown:) à chaque body pass.
private final class InlineMarkdownCache {
    private var map: [String: AttributedString] = [:]
    private let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )

    func attributed(_ text: String) -> AttributedString {
        if let hit = map[text] { return hit }
        let value = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        if map.count > 256 {
            map.removeAll(keepingCapacity: true)
        }
        map[text] = value
        return value
    }
}

private struct RenderedMarkdownBlock: Identifiable, Equatable {
    let id: String
    let block: MarkdownBlock
}

/// Split stable pour stream : préfixe figé (blocs complets hors fence) + queue live.
private enum StreamingMarkdownSplit {
    static func split(_ source: String) -> (prefix: String, tail: String) {
        guard !source.isEmpty else { return ("", "") }
        var inFence = false
        var lastStable = source.startIndex
        var i = source.startIndex
        while i < source.endIndex {
            if source[i] == "`" {
                let rest = source[i...]
                if rest.hasPrefix("```") {
                    inFence.toggle()
                    i = source.index(i, offsetBy: 3, limitedBy: source.endIndex) ?? source.endIndex
                    continue
                }
            }
            if !inFence, source[i] == "\n" {
                let next = source.index(after: i)
                if next < source.endIndex, source[next] == "\n" {
                    lastStable = source.index(after: next)
                }
            }
            i = source.index(after: i)
        }
        if lastStable == source.startIndex {
            return ("", source)
        }
        return (String(source[..<lastStable]), String(source[lastStable...]))
    }

    static func renderBlocks(prefix: String, tail: String) -> [RenderedMarkdownBlock] {
        var out: [RenderedMarkdownBlock] = []
        let frozen = prefix.isEmpty ? [] : MarkdownBlockParser.parse(prefix)
        for (idx, block) in frozen.enumerated() {
            out.append(RenderedMarkdownBlock(id: "f-\(idx)-\(blockStableKey(block))", block: block))
        }
        let live = tail.isEmpty ? [] : MarkdownBlockParser.parse(tail)
        for (idx, block) in live.enumerated() {
            out.append(RenderedMarkdownBlock(id: "l-\(idx)", block: block))
        }
        return out
    }

    private static func blockStableKey(_ block: MarkdownBlock) -> String {
        switch block {
        case .heading(let level, let text):
            return "h\(level)-\(text.count)-\(text.prefix(24).hashValue)"
        case .paragraph(let text):
            return "p-\(text.count)-\(text.prefix(24).hashValue)"
        case .code(let language, let code):
            return "c-\(language ?? "")-\(code.count)"
        case .bullet(let items):
            return "ul-\(items.count)-\(items.first?.prefix(16).hashValue ?? 0)"
        case .numbered(let items):
            return "ol-\(items.count)-\(items.first?.prefix(16).hashValue ?? 0)"
        case .quote(let text):
            return "q-\(text.count)"
        case .table(let headers, let rows):
            return "t-\(headers.count)x\(rows.count)"
        case .thematicBreak:
            return "hr"
        }
    }
}

struct MarkdownMessageView: View {
    let markdown: String
    /// Pendant le stream SSE : markdown live, reparse cadencé (~30 fps) + préfixe figé.
    var isStreaming: Bool = false

    @State private var rendered: [RenderedMarkdownBlock]
    @State private var parseTask: Task<Void, Never>?
    @State private var lastParseAt = Date.distantPast
    @State private var pendingParse = false
    @State private var frozenPrefix = ""
    @State private var inlineCache = InlineMarkdownCache()

    init(markdown: String, isStreaming: Bool = false) {
        self.markdown = markdown
        self.isStreaming = isStreaming
        let initial = MarkdownBlockParser.parse(markdown).enumerated().map {
            RenderedMarkdownBlock(id: "i-\($0.offset)", block: $0.element)
        }
        _rendered = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            ForEach(rendered) { item in
                blockView(item.block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if rendered.isEmpty, !markdown.isEmpty {
                scheduleParse(immediate: true)
            }
        }
        .onChange(of: markdown) { _, _ in
            scheduleParse(immediate: !isStreaming)
        }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming {
                frozenPrefix = ""
                scheduleParse(immediate: true)
            }
        }
        .onDisappear {
            parseTask?.cancel()
            parseTask = nil
        }
    }

    private func scheduleParse(immediate: Bool) {
        if immediate {
            parseTask?.cancel()
            parseTask = nil
            pendingParse = false
            lastParseAt = Date()
            applyParse(markdown, streaming: false)
            return
        }

        let minInterval: TimeInterval = 0.033
        let elapsed = Date().timeIntervalSince(lastParseAt)
        if elapsed >= minInterval {
            lastParseAt = Date()
            pendingParse = false
            applyParse(markdown, streaming: true)
            return
        }

        pendingParse = true
        guard parseTask == nil else { return }
        let wait = UInt64((minInterval - elapsed) * 1_000_000_000)
        parseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: wait)
            parseTask = nil
            guard !Task.isCancelled else { return }
            guard pendingParse else { return }
            pendingParse = false
            lastParseAt = Date()
            applyParse(markdown, streaming: true)
        }
    }

    private func applyParse(_ source: String, streaming: Bool) {
        if !streaming {
            frozenPrefix = ""
            rendered = MarkdownBlockParser.parse(source).enumerated().map {
                RenderedMarkdownBlock(id: "i-\($0.offset)", block: $0.element)
            }
            return
        }

        let parts = StreamingMarkdownSplit.split(source)
        if parts.prefix.count >= frozenPrefix.count,
           parts.prefix.hasPrefix(frozenPrefix) || frozenPrefix.isEmpty {
            frozenPrefix = parts.prefix
        } else if parts.prefix != frozenPrefix {
            frozenPrefix = parts.prefix
        }
        let tail = String(source.dropFirst(frozenPrefix.count))
        rendered = StreamingMarkdownSplit.renderBlocks(prefix: frozenPrefix, tail: tail)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .foregroundStyle(AppTheme.foreground)
                .textSelection(.enabled)
        case .paragraph(let text):
            Text(inline(text))
                .font(CNFont.body)
                .foregroundStyle(AppTheme.foreground)
                .textSelection(.enabled)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: AppTheme.space8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: AppTheme.space8) {
                        Text("•")
                            .foregroundStyle(AppTheme.accent)
                        Text(inline(item))
                            .font(CNFont.body)
                            .foregroundStyle(AppTheme.foreground)
                            .textSelection(.enabled)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: AppTheme.space8) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: AppTheme.space8) {
                        Text("\(idx + 1).")
                            .font(CNFont.body.monospacedDigit())
                            .foregroundStyle(AppTheme.muted)
                            .frame(minWidth: 22, alignment: .trailing)
                        Text(inline(item))
                            .font(CNFont.body)
                            .foregroundStyle(AppTheme.foreground)
                            .textSelection(.enabled)
                    }
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: AppTheme.space12) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppTheme.accent.opacity(0.5))
                    .frame(width: 3)
                Text(inline(text))
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.muted)
                    .textSelection(.enabled)
            }
            .padding(.vertical, AppTheme.space4)
        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                            Text(inline(h))
                                .font(CNFont.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.foreground)
                                .padding(AppTheme.space8)
                                .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.surfaceElevated)
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(inline(cell))
                                    .font(CNFont.caption)
                                    .foregroundStyle(AppTheme.muted)
                                    .padding(AppTheme.space8)
                                    .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                                    .background(rIdx % 2 == 0 ? AppTheme.surface.opacity(0.35) : Color.clear)
                            }
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
            }
        case .thematicBreak:
            Divider().background(AppTheme.border)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.bold)
        case 2: return .title2.weight(.semibold)
        case 3: return .title3.weight(.semibold)
        default: return .headline
        }
    }

    private func inline(_ text: String) -> AttributedString {
        inlineCache.attributed(text)
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(CNFont.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    AppHaptics.success()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(CNFont.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copier le code")
            }
            .padding(.horizontal, AppTheme.space12)
            .padding(.vertical, AppTheme.space8)
            .background(AppTheme.surfaceElevated)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(CNFont.mono)
                    .foregroundStyle(AppTheme.foreground)
                    .textSelection(.enabled)
                    .padding(AppTheme.space12)
            }
            .background(AppTheme.codeBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
    }
}
