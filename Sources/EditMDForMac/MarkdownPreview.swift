import Foundation
import AppKit
import SwiftUI

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list([MarkdownListItem])
        case table(MarkdownTable)
        case quote([MarkdownQuoteLine])
        case code(language: String?, text: String)
        case image(MarkdownImage)
        case divider
    }

    let id: String
    let startLine: Int
    let endLine: Int
    let kind: Kind
}

struct MarkdownListItem: Equatable {
    let text: String
    let checked: Bool?
    let isOrdered: Bool
    let number: Int?
    var children: [MarkdownListItem]
}

struct MarkdownQuoteLine: Equatable {
    let level: Int
    let text: String
}

struct MarkdownImage: Equatable {
    let alt: String
    let source: String
    let link: String?
}

struct MarkdownTable: Equatable {
    let columns: [MarkdownTableColumn]
    let rows: [[String]]
}

struct MarkdownTableColumn: Equatable {
    let title: String
    let alignment: MarkdownTableAlignment
}

enum MarkdownTableAlignment: Equatable {
    case left
    case center
    case right
}

struct MarkdownHeading: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
    let line: Int
}

struct MarkdownParseResult: Equatable {
    let blocks: [MarkdownBlock]
    let headings: [MarkdownHeading]
    let references: [String: String]
}

struct MarkdownScrollTarget: Equatable {
    enum Source: Equatable {
        case editor
        case preview
        case navigation
    }

    let requestID = UUID()
    let blockID: String
    let line: Int
    let endLine: Int
    let fraction: Double
    let source: Source

    init(blockID: String, line: Int, endLine: Int? = nil, fraction: Double = 0, source: Source) {
        self.blockID = blockID
        self.line = line
        self.endLine = endLine ?? line
        self.fraction = max(0, min(1, fraction))
        self.source = source
    }

    static func == (lhs: MarkdownScrollTarget, rhs: MarkdownScrollTarget) -> Bool {
        lhs.requestID == rhs.requestID
    }
}

struct HeadingPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum MarkdownInlineStyler {
    static func inline(_ markdown: String, fontSize: CGFloat, references: [String: String] = [:]) -> AttributedString {
        do {
            let resolvedMarkdown = resolveReferenceLinks(in: markdown, references: references)
            var attributed = try AttributedString(
                markdown: resolvedMarkdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )

            for run in attributed.runs {
                if run.inlinePresentationIntent?.contains(.code) == true {
                    attributed[run.range].font = .system(size: max(11, fontSize - 1), design: .monospaced)
                    attributed[run.range].foregroundColor = Color(red: 0.48, green: 0.06, blue: 0.14)
                    attributed[run.range].backgroundColor = Color.secondary.opacity(0.16)
                }
            }

            return attributed
        } catch {
            return AttributedString(markdown)
        }
    }

    private static func resolveReferenceLinks(in markdown: String, references: [String: String]) -> String {
        guard !references.isEmpty else { return markdown }

        var output = markdown
        let pattern = #"(?<!!)\[([^\]]+)\]\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return markdown }

        let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)).reversed()
        for match in matches {
            guard
                let textRange = Range(match.range(at: 1), in: output),
                let idRange = Range(match.range(at: 2), in: output),
                let fullRange = Range(match.range(at: 0), in: output)
            else {
                continue
            }

            let text = String(output[textRange])
            let id = String(output[idRange]).lowercased()
            guard let url = references[id] else { continue }
            output.replaceSubrange(fullRange, with: "[\(text)](\(url))")
        }

        return output
    }
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        parseDocument(markdown).blocks
    }

    static func parseDocument(_ markdown: String) -> MarkdownParseResult {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [MarkdownBlock] = []
        var headings: [MarkdownHeading] = []
        var references: [String: String] = [:]
        var paragraph: [String] = []
        var paragraphStartLine: Int?
        var index = 0
        var blockIndex = 0

        func blockID(prefix: String) -> String {
            defer { blockIndex += 1 }
            return "\(prefix)-\(blockIndex)"
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            if !text.isEmpty {
                let startLine = paragraphStartLine ?? max(0, index - paragraph.count)
                blocks.append(MarkdownBlock(id: blockID(prefix: "paragraph"), startLine: startLine, endLine: startLine + paragraph.count - 1, kind: .paragraph(text)))
            }
            paragraph.removeAll()
            paragraphStartLine = nil
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let reference = referenceDefinition(in: trimmed) {
                flushParagraph()
                references[reference.id] = reference.url
                index += 1
                continue
            }

            if let fence = codeFence(in: trimmed) {
                flushParagraph()
                let startLine = index
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence.marker) {
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(MarkdownBlock(id: blockID(prefix: "code"), startLine: startLine, endLine: max(startLine, index - 1), kind: .code(language: fence.language, text: codeLines.joined(separator: "\n"))))
                continue
            }

            if let table = tableStarting(at: index, in: lines) {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blockID(prefix: "table"), startLine: index, endLine: max(index, table.nextIndex - 1), kind: .table(table.table)))
                index = table.nextIndex
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                let id = "heading-\(index)-\(slug(heading.text))"
                blocks.append(MarkdownBlock(id: id, startLine: index, endLine: index, kind: .heading(level: heading.level, text: heading.text)))
                headings.append(MarkdownHeading(id: id, level: heading.level, text: heading.text, line: index))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blockID(prefix: "divider"), startLine: index, endLine: index, kind: .divider))
                index += 1
                continue
            }

            if let image = imageOnly(in: trimmed) {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blockID(prefix: "image"), startLine: index, endLine: index, kind: .image(image)))
                index += 1
                continue
            }

            if let list = listStarting(at: index, in: lines) {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blockID(prefix: "list"), startLine: index, endLine: max(index, list.nextIndex - 1), kind: .list(list.items)))
                index = list.nextIndex
                continue
            }

            if let firstQuoteLine = quoteLine(in: line) {
                flushParagraph()
                let startLine = index
                var quoteLines: [MarkdownQuoteLine] = [firstQuoteLine]
                index += 1
                while index < lines.count {
                    guard let next = quoteLine(in: lines[index]) else { break }
                    quoteLines.append(next)
                    index += 1
                }
                blocks.append(MarkdownBlock(id: blockID(prefix: "quote"), startLine: startLine, endLine: max(startLine, index - 1), kind: .quote(quoteLines)))
                continue
            }

            if paragraph.isEmpty {
                paragraphStartLine = index
            }
            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        let finalBlocks = blocks.isEmpty ? [MarkdownBlock(id: "empty", startLine: 0, endLine: 0, kind: .paragraph(" "))] : blocks
        return MarkdownParseResult(blocks: finalBlocks, headings: headings, references: references)
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#", level < 6 {
                level += 1
            } else {
                break
            }
        }

        guard level > 0, line.dropFirst(level).first == " " else { return nil }
        let text = String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func codeFence(in line: String) -> (marker: String, language: String?)? {
        if line.hasPrefix("```") {
            let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return ("```", language.isEmpty ? nil : language.lowercased())
        }
        if line.hasPrefix("~~~") {
            let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return ("~~~", language.isEmpty ? nil : language.lowercased())
        }
        return nil
    }

    private static func referenceDefinition(in line: String) -> (id: String, url: String)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let afterClose = line[line.index(after: close)...]
        guard afterClose.hasPrefix(":") else { return nil }

        let id = String(line[line.index(after: line.startIndex)..<close])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let rest = String(afterClose.dropFirst())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, let url = rest.split(separator: " ").first else { return nil }
        return (id, String(url))
    }

    private static func imageOnly(in line: String) -> MarkdownImage? {
        if let linked = firstMatch(in: line, pattern: #"^\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)$"#) {
            return MarkdownImage(alt: linked[1], source: linked[2], link: linked[3])
        }

        if let image = firstMatch(in: line, pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#) {
            return MarkdownImage(alt: image[1], source: image[2], link: nil)
        }

        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : nsText.substring(with: range)
        }
    }

    private static func tableStarting(at index: Int, in lines: [String]) -> (table: MarkdownTable, nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }

        let headerLine = lines[index].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[index + 1].trimmingCharacters(in: .whitespaces)

        guard
            isTableRow(headerLine),
            let alignments = tableAlignments(from: separatorLine)
        else {
            return nil
        }

        let headers = splitTableRow(headerLine)
        guard !headers.isEmpty, headers.count == alignments.count else { return nil }

        var rows: [[String]] = []
        var nextIndex = index + 2

        while nextIndex < lines.count {
            let line = lines[nextIndex].trimmingCharacters(in: .whitespaces)
            guard isTableRow(line), tableAlignments(from: line) == nil else { break }

            var cells = splitTableRow(line)
            if cells.count < headers.count {
                cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
            } else if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }

            rows.append(cells)
            nextIndex += 1
        }

        guard !rows.isEmpty else { return nil }

        let columns = zip(headers, alignments).map { title, alignment in
            MarkdownTableColumn(title: title, alignment: alignment)
        }
        return (MarkdownTable(columns: columns, rows: rows), nextIndex)
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|") && splitTableRow(line).count >= 2
    }

    private static func tableAlignments(from line: String) -> [MarkdownTableAlignment]? {
        guard line.contains("|") else { return nil }

        let cells = splitTableRow(line)
        guard cells.count >= 2 else { return nil }

        var alignments: [MarkdownTableAlignment] = []

        for cell in cells {
            let compact = cell.replacingOccurrences(of: " ", with: "")
            guard compact.contains("-"), compact.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }

            let hyphenCount = compact.filter { $0 == "-" }.count
            guard hyphenCount >= 3 else { return nil }

            let startsWithColon = compact.hasPrefix(":")
            let endsWithColon = compact.hasSuffix(":")

            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }

        return alignments
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in trimmed {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                current.append(character)
                continue
            }

            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll()
            } else {
                current.append(character)
            }
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" } || compact.allSatisfy { $0 == "_" }
    }

    private struct ParsedListLine {
        let indent: Int
        let item: MarkdownListItem
    }

    private static func listStarting(at startIndex: Int, in lines: [String]) -> (items: [MarkdownListItem], nextIndex: Int)? {
        guard let first = listLine(in: lines[startIndex]) else { return nil }
        var index = startIndex

        func parseItems(minIndent: Int) -> [MarkdownListItem] {
            var items: [MarkdownListItem] = []

            while index < lines.count {
                guard let parsed = listLine(in: lines[index]) else { break }
                if parsed.indent < minIndent { break }

                if parsed.indent > minIndent {
                    if !items.isEmpty {
                        let children = parseItems(minIndent: parsed.indent)
                        items[items.count - 1].children.append(contentsOf: children)
                        continue
                    }
                    break
                }

                items.append(parsed.item)
                index += 1
            }

            return items
        }

        let items = parseItems(minIndent: first.indent)
        return items.isEmpty ? nil : (items, index)
    }

    private static func listLine(in line: String) -> ParsedListLine? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { total, character in
            total + (character == "\t" ? 4 : 1)
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let item = unorderedListItem(in: trimmed) {
            return ParsedListLine(indent: indent, item: item)
        }

        if let item = orderedListItem(in: trimmed) {
            return ParsedListLine(indent: indent, item: item)
        }

        return nil
    }

    private static func unorderedListItem(in line: String) -> MarkdownListItem? {
        guard line.count >= 2 else { return nil }
        let marker = line.first
        guard marker == "-" || marker == "*" || marker == "+", line.dropFirst().first == " " else { return nil }
        let text = String(line.dropFirst(2))
        return taskItem(from: text, isOrdered: false, number: nil) ?? MarkdownListItem(text: text, checked: nil, isOrdered: false, number: nil, children: [])
    }

    private static func orderedListItem(in line: String) -> MarkdownListItem? {
        var digitCount = 0
        for character in line {
            if character.isNumber {
                digitCount += 1
            } else {
                break
            }
        }

        guard digitCount > 0 else { return nil }
        let rest = line.dropFirst(digitCount)
        guard rest.hasPrefix(". ") else { return nil }
        let text = String(rest.dropFirst(2))
        let number = Int(line.prefix(digitCount)) ?? 1
        return taskItem(from: text, isOrdered: true, number: number) ?? MarkdownListItem(text: text, checked: nil, isOrdered: true, number: number, children: [])
    }

    private static func taskItem(from text: String, isOrdered: Bool, number: Int?) -> MarkdownListItem? {
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("[x] ") {
            return MarkdownListItem(text: String(text.dropFirst(4)), checked: true, isOrdered: isOrdered, number: number, children: [])
        }
        if lowercased.hasPrefix("[ ] ") {
            return MarkdownListItem(text: String(text.dropFirst(4)), checked: false, isOrdered: isOrdered, number: number, children: [])
        }
        return nil
    }

    private static func quoteLine(in line: String) -> MarkdownQuoteLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        var index = trimmed.startIndex

        while index < trimmed.endIndex {
            if trimmed[index] == ">" {
                level += 1
                index = trimmed.index(after: index)
                if index < trimmed.endIndex, trimmed[index] == " " {
                    index = trimmed.index(after: index)
                }
            } else if trimmed[index] == " " {
                index = trimmed.index(after: index)
            } else {
                break
            }
        }

        guard level > 0 else { return nil }
        return MarkdownQuoteLine(level: level, text: String(trimmed[index...]))
    }

    private static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = text.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar).lowercased() : "-"
        }
        let slug = scalars.joined()
            .split(separator: "-")
            .joined(separator: "-")
        return slug.isEmpty ? "heading" : slug
    }
}

struct MarkdownPreview: View {
    let blocks: [MarkdownBlock]
    let fontSize: CGFloat
    let referenceLinks: [String: String]
    let baseURL: URL?
    let availableWidth: CGFloat

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                MarkdownBlockView(
                    block: block,
                    fontSize: fontSize,
                    referenceLinks: referenceLinks,
                    baseURL: baseURL,
                    availableWidth: availableWidth
                )
                    .id(block.id)
                    .contentShape(Rectangle())
                    .background(blockPositionReader(for: block))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: "previewContent")
    }

    @ViewBuilder
    private func blockPositionReader(for block: MarkdownBlock) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: HeadingPositionPreferenceKey.self,
                value: [block.id: geometry.frame(in: .named("previewContent")).minY]
            )
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let fontSize: CGFloat
    let referenceLinks: [String: String]
    let baseURL: URL?
    let availableWidth: CGFloat

    var body: some View {
        switch block.kind {
        case let .heading(level, text):
            Text(inline(text))
                .font(.system(size: headingSize(level), weight: headingWeight(level), design: .default))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, headingTopPadding(level))
                .padding(.bottom, headingBottomPadding(level))

        case let .paragraph(text):
            Text(inline(text))
                .font(.system(size: fontSize))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

        case let .list(items):
            MarkdownListView(items: items, level: 0, fontSize: fontSize, referenceLinks: referenceLinks)
                .padding(.bottom, 12)

        case let .table(table):
            MarkdownTableView(
                table: table,
                fontSize: fontSize,
                referenceLinks: referenceLinks,
                availableWidth: availableWidth
            )
                .padding(.bottom, 18)

        case let .quote(lines):
            quoteView(lines)
            .padding(.bottom, 8)

        case let .code(language, text):
            codeBlock(text: text, language: language)
                .padding(.bottom, 14)

        case let .image(image):
            imageView(image)
                .padding(.bottom, 16)

        case .divider:
            Divider()
                .padding(.vertical, 14)
        }
    }

    private struct MarkdownListView: View {
        let items: [MarkdownListItem]
        let level: Int
        let fontSize: CGFloat
        let referenceLinks: [String: String]

        var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.system(size: fontSize))
                                .foregroundColor(checked ? .accentColor : .secondary)
                                .frame(width: 24, alignment: .center)
                        } else {
                            Text(item.isOrdered ? "\(item.number ?? index + 1)." : bullet(for: level))
                                .font(.system(size: fontSize, weight: item.isOrdered ? .medium : .regular))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        }

                        Text(inline(item.text))
                            .font(.system(size: fontSize))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !item.children.isEmpty {
                        MarkdownListView(items: item.children, level: level + 1, fontSize: fontSize, referenceLinks: referenceLinks)
                            .padding(.leading, 30)
                    }
                }
            }
        }
        .padding(.leading, 2)
        }

        private func bullet(for level: Int) -> String {
            switch level % 3 {
            case 0: "•"
            case 1: "◦"
            default: "▪"
            }
        }

        private func inline(_ markdown: String) -> AttributedString {
            MarkdownInlineStyler.inline(markdown, fontSize: fontSize, references: referenceLinks)
        }
    }

    private func quoteView(_ lines: [MarkdownQuoteLine]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<max(1, line.level), id: \.self) { level in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.secondary.opacity(level == 0 ? 0.45 : 0.26))
                            .frame(width: 3)
                    }

                    Text(inline(line.text.isEmpty ? " " : line.text))
                        .font(.system(size: fontSize))
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func codeBlock(text: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 9)
                    .padding(.bottom, 4)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(CodeHighlighter.highlight(text, language: language, fontSize: max(11, fontSize - 1)))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.top, language == nil ? 12 : 4)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }

    @ViewBuilder
    private func imageView(_ image: MarkdownImage) -> some View {
        let resolvedURL = imageURL(from: image.source)
        VStack(alignment: .leading, spacing: 6) {
            if let resolvedURL {
                if resolvedURL.isFileURL {
                    LocalMarkdownImage(url: resolvedURL, alt: image.alt)
                } else {
                    AsyncImage(url: resolvedURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            imagePlaceholder(alt: image.alt, source: image.source)
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                        @unknown default:
                            imagePlaceholder(alt: image.alt, source: image.source)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                imagePlaceholder(alt: image.alt, source: image.source)
            }

            if !image.alt.isEmpty {
                Text(image.alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func imagePlaceholder(alt: String, source: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(alt.isEmpty ? "Image" : alt)
                    .font(.caption.weight(.semibold))
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }

    private func imageURL(from source: String) -> URL? {
        let cleaned = cleanDestination(source)
        if let url = URL(string: cleaned), url.scheme != nil {
            return url
        }

        if cleaned.hasPrefix("/") {
            return URL(fileURLWithPath: cleaned)
        }

        return baseURL?.appendingPathComponent(cleaned)
    }

    private func cleanDestination(_ destination: String) -> String {
        var cleaned = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("<"), cleaned.hasSuffix(">") {
            cleaned.removeFirst()
            cleaned.removeLast()
            return cleaned
        }
        return cleaned.split(separator: " ").first.map(String.init) ?? cleaned
    }

    private func inline(_ markdown: String) -> AttributedString {
        MarkdownInlineStyler.inline(markdown, fontSize: fontSize, references: referenceLinks)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: fontSize + 14
        case 2: fontSize + 9
        case 3: fontSize + 5
        case 4: fontSize + 3
        default: fontSize + 1
        }
    }

    private func headingWeight(_ level: Int) -> Font.Weight {
        level <= 2 ? .bold : .semibold
    }

    private func headingTopPadding(_ level: Int) -> CGFloat {
        level <= 2 ? 12 : 8
    }

    private func headingBottomPadding(_ level: Int) -> CGFloat {
        level <= 2 ? 10 : 7
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let fontSize: CGFloat
    let referenceLinks: [String: String]
    let availableWidth: CGFloat

    private var columnCount: Int {
        max(table.columns.count, 1)
    }

    private var fallbackColumnWidth: CGFloat {
        160
    }

    private var tableWidth: CGFloat {
        availableWidth > 1 ? availableWidth : fallbackColumnWidth * CGFloat(columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tableGrid(width: tableWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableGrid(width tableWidth: CGFloat) -> some View {
        let columnWidth = tableWidth / CGFloat(columnCount)

        return VStack(alignment: .leading, spacing: 0) {
            MarkdownTableRowView(
                cells: table.columns.map(\.title),
                alignments: table.columns.map(\.alignment),
                columnWidth: columnWidth,
                fontSize: fontSize,
                referenceLinks: referenceLinks,
                isHeader: true
            )

            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                MarkdownTableRowView(
                    cells: table.columns.indices.map { columnIndex in
                        columnIndex < row.count ? row[columnIndex] : ""
                    },
                    alignments: table.columns.map(\.alignment),
                    columnWidth: columnWidth,
                    fontSize: fontSize,
                    referenceLinks: referenceLinks,
                    isHeader: false
                )
            }
        }
        .frame(width: tableWidth, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MarkdownTableRowView: View {
    let cells: [String]
    let alignments: [MarkdownTableAlignment]
    let columnWidth: CGFloat
    let fontSize: CGFloat
    let referenceLinks: [String: String]
    let isHeader: Bool

    private var rowWidth: CGFloat {
        columnWidth * CGFloat(max(cells.count, 1))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, text in
                tableCell(
                    text: text,
                    alignment: index < alignments.count ? alignments[index] : .left
                )
            }
        }
        .frame(width: rowWidth, alignment: .leading)
        .background(isHeader ? Color.secondary.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
        .overlay {
            verticalSeparators
        }
    }

    private var verticalSeparators: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                ForEach(1..<max(cells.count, 1), id: \.self) { index in
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                        .offset(x: columnWidth * CGFloat(index))
                }
            }
        }
        .frame(width: rowWidth)
    }

    private func tableCell(text: String, alignment: MarkdownTableAlignment) -> some View {
        let horizontalPadding = min(12, max(4, columnWidth * 0.12))

        return Text(inline(text.isEmpty ? " " : text))
            .font(.system(size: fontSize, weight: isHeader ? .semibold : .regular))
            .lineLimit(nil)
            .lineSpacing(4)
            .multilineTextAlignment(textAlignment(alignment))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 9)
            .frame(width: columnWidth, alignment: swiftUIAlignment(alignment))
    }

    private func swiftUIAlignment(_ alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    private func textAlignment(_ alignment: MarkdownTableAlignment) -> TextAlignment {
        switch alignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    private func inline(_ markdown: String) -> AttributedString {
        MarkdownInlineStyler.inline(markdown, fontSize: fontSize, references: referenceLinks)
    }
}

private struct LocalMarkdownImage: View {
    let url: URL
    let alt: String

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(alt.isEmpty ? url.lastPathComponent : alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

enum CodeHighlighter {
    static func highlight(_ code: String, language: String?, fontSize: CGFloat) -> AttributedString {
        let source = code.isEmpty ? " " : code
        let attributed = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )

        let language = language?.lowercased() ?? ""
        apply(pattern: #"\b\d+(\.\d+)?\b"#, color: .systemBlue, to: attributed)

        if language == "javascript" || language == "js" || language == "typescript" || language == "ts" {
            apply(pattern: #"\b(const|let|var|function|return|if|else|for|while|class|import|export|from|new|true|false|null|undefined)\b"#, color: .systemPurple, weight: .semibold, to: attributed)
            apply(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: .systemRed, to: attributed)
            apply(pattern: #"//.*"#, color: .systemGreen, to: attributed)
            apply(pattern: #"/\*[\s\S]*?\*/"#, color: .systemGreen, to: attributed)
        } else if language == "json" {
            apply(pattern: #""([^"\\]|\\.)*"(?=\s*:)"#, color: .systemPurple, weight: .semibold, to: attributed)
            apply(pattern: #"\b(true|false|null)\b"#, color: .systemOrange, weight: .semibold, to: attributed)
            apply(pattern: #""([^"\\]|\\.)*""#, color: .systemRed, to: attributed)
            apply(pattern: #""([^"\\]|\\.)*"(?=\s*:)"#, color: .systemPurple, weight: .semibold, to: attributed)
        } else if language == "css" {
            apply(pattern: #"(?m)^\s*[.#]?[A-Za-z0-9_-]+(?=\s*\{)"#, color: .systemPurple, weight: .semibold, to: attributed)
            apply(pattern: #"[A-Za-z-]+(?=\s*:)"#, color: .systemBlue, weight: .semibold, to: attributed)
            apply(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: .systemRed, to: attributed)
            apply(pattern: #"/\*[\s\S]*?\*/"#, color: .systemGreen, to: attributed)
        } else {
            apply(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: .systemRed, to: attributed)
            apply(pattern: #"//.*"#, color: .systemGreen, to: attributed)
        }

        return AttributedString(attributed)
    }

    private static func apply(
        pattern: String,
        color: NSColor,
        weight: NSFont.Weight = .regular,
        to attributed: NSMutableAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let source = attributed.string
        let range = NSRange(location: 0, length: (source as NSString).length)

        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
            if weight != .regular {
                let size = (attributed.attribute(.font, at: max(0, match.range.location), effectiveRange: nil) as? NSFont)?.pointSize ?? 13
                attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: weight), range: match.range)
            }
        }
    }
}
