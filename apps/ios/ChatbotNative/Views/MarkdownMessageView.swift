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

struct MarkdownMessageView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                            Text(h)
                                .font(CNFont.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.foreground)
                                .padding(AppTheme.space8)
                                .frame(minWidth: 88, alignment: .leading)
                        }
                    }
                    .background(AppTheme.surfaceElevated)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(CNFont.caption)
                                    .foregroundStyle(AppTheme.muted)
                                    .padding(AppTheme.space8)
                                    .frame(minWidth: 88, alignment: .leading)
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
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
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
