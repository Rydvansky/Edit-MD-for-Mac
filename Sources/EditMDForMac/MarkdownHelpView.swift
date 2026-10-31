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

    var body: some View {
        Text(.init(source))
            .font(.system(size: 14))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
