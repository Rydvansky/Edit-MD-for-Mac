import SwiftUI

struct MarkdownHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [HelpItem] = [
        .heading("Headings"),
        .tip("# Heading 1"),
        .tip("## Heading 2"),
        .tip("### Heading 3"),
        .tip("#### Heading 4"),

        .heading("Text"),
        .tip("**bold text**"),
        .tip("*italic text*"),
        .tip("***bold and italic***"),
        .tip("~~strikethrough~~"),
        .tip("`inline code`"),
        .tip("[Apple](https://apple.com)"),

        .heading("Lists"),
        .tip("- First item\n- Second item\n- Third item"),
        .tip("1. First step\n2. Second step\n3. Third step"),
        .tip("- [x] Done task\n- [ ] Open task"),

        .heading("Blocks"),
        .tip("> A quoted passage"),
        .tip("---"),
        .tip("```swift\nlet app = \"native\"\nprint(app)\n```"),

        .heading("App Shortcuts"),
        .shortcut("⌘ O", "Open file"),
        .shortcut("⌘ S", "Save"),
        .shortcut("⌘ +", "Bigger text"),
        .shortcut("⌘ −", "Smaller text")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Markdown Guide")
                    .font(.title2.weight(.bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemView(item)
                            .padding(.vertical, rowPadding(for: item))

                        if shouldShowDivider(after: index) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 1)
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func rowPadding(for item: HelpItem) -> CGFloat {
        switch item {
        case .heading: 10
        default: 8
        }
    }

    private func shouldShowDivider(after index: Int) -> Bool {
        guard index < items.count - 1 else { return false }
        let nextIsHeading: Bool = {
            if case .heading = items[index + 1] { return true }
            return false
        }()
        if case .heading = items[index] { return false }
        return !nextIsHeading
    }

    @ViewBuilder
    private func itemView(_ item: HelpItem) -> some View {
        switch item {
        case let .heading(title):
            Text(title)
                .font(.headline)
                .padding(.top, 6)

        case let .tip(source):
            HStack(alignment: .top, spacing: 18) {
                Text(source)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TipPreview(source: source)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case let .shortcut(keys, action):
            HStack(spacing: 14) {
                Text(keys)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .frame(minWidth: 70, alignment: .leading)
                Text(action)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Help item model

private enum HelpItem: Identifiable {
    case heading(String)
    case tip(String)
    case shortcut(String, String)

    var id: String {
        switch self {
        case let .heading(text): "h-\(text)"
        case let .tip(text): "t-\(text)"
        case let .shortcut(keys, action): "s-\(keys)-\(action)"
        }
    }
}

// MARK: - Inline markdown renderer (no cards, no boxes)

private struct TipPreview: View {
    let source: String

    private var blocks: [MarkdownBlock] { MarkdownParser.parse(source) }
    private let size: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(blocks) { block in
                TipBlockView(block: block, fontSize: size)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TipBlockView: View {
    let block: MarkdownBlock
    let fontSize: CGFloat

    var body: some View {
        switch block.kind {

        case let .heading(level, text):
            Text(text)
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .paragraph(text):
            Text(inlineAttr(text))
                .font(.system(size: fontSize))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .list(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.prefix(6).enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Group {
                            if let checked = item.checked {
                                Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    .foregroundColor(checked ? .accentColor : .secondary)
                            } else {
                                Text(item.isOrdered ? "\(i + 1)." : "•")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: fontSize))
                        .frame(width: 22, alignment: .center)

                        Text(inlineAttr(item.text))
                            .font(.system(size: fontSize))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .quote(lines):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(inlineAttr(line.text.isEmpty ? " " : line.text))
                            .font(.system(size: fontSize))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .code(language, text):
            VStack(alignment: .leading, spacing: 2) {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.system(size: max(11, fontSize - 1), design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .divider:
            Rectangle()
                .fill(.secondary.opacity(0.4))
                .frame(height: 1)
                .padding(.vertical, 4)

        default:
            EmptyView()
        }
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

    private func inlineAttr(_ text: String) -> AttributedString {
        MarkdownInlineStyler.inline(text, fontSize: fontSize)
    }
}
