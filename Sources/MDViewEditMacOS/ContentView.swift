import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: DocumentStore
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("editorMode") private var editorModeRaw = EditorMode.preview.rawValue
    @AppStorage("showNavigationPane") private var showNavigationPane = false
    @StateObject private var webBridge = WebEditorBridge()
    @State private var dropIsTargeted = false
    @State private var showingMarkdownHelp = false
    @State private var scrollTarget: MarkdownScrollTarget?

    private var editorText: Binding<String> {
        Binding(
            get: { store.text },
            set: { store.updateText($0) }
        )
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var editorMode: EditorMode {
        EditorMode(rawValue: editorModeRaw) ?? .preview
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                appearanceModeRaw: $appearanceModeRaw,
                editorModeRaw: $editorModeRaw,
                showNavigationPane: $showNavigationPane,
                showingMarkdownHelp: $showingMarkdownHelp,
                onSelectMode: setEditorMode(_:)
            )

            Divider()

            workspace

            Divider()
            StatusBar()
        }
        .overlay {
            if dropIsTargeted {
                DropOverlay()
            }
        }
        .overlay {
            if store.isEmptyState {
                EmptyStateView()
            }
        }
        .background(AppearanceBridge(mode: appearanceMode))
        .onAppear {
            webBridge.attach(store: store)
        }
        .onChange(of: store.text) { newText in
            webBridge.storeTextDidChange(newText, reload: false)
        }
        .onChange(of: store.fileURL) { _ in
            // File opened/saved-as: force a refresh-style update so the web
            // editor re-renders unconditionally and images re-resolve.
            webBridge.storeTextDidChange(store.text, reload: true)
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $dropIsTargeted,
            perform: store.handleDrop(providers:)
        )
        .sheet(isPresented: $showingMarkdownHelp) {
            MarkdownHelpView()
                .frame(width: 720, height: 620)
        }
        .alert(item: $store.error) { error in
            Alert(
                title: Text(error.message),
                message: Text(error.recovery ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var workspace: some View {
        if showNavigationPane {
            HSplitView {
                NavigationPane { heading in
                    scrollTarget = MarkdownScrollTarget(blockID: heading.id, line: heading.line, source: .navigation)
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

                mainEditorArea
                    .frame(minWidth: 420)
            }
        } else {
            mainEditorArea
        }
    }

    /// Single full-width surface: either the source code editor or the rich
    /// (WYSIWYG) web preview/editor. Both stay alive in the ZStack so mode
    /// switches are instant and no state is lost; the inactive one is
    /// transparent and does not receive events.
    private var mainEditorArea: some View {
        let isCode = editorMode == .code
        return ZStack {
            EditorPane(
                text: editorText,
                fontSize: store.fontSize,
                scrollTarget: scrollTarget,
                onLineSelected: syncFromEditor(line:)
            )
            .opacity(isCode ? 1 : 0)
            .zIndex(isCode ? 1 : 0)
            .allowsHitTesting(isCode)

            WebEditorPane(bridge: webBridge)
                .opacity(isCode ? 0 : 1)
                .zIndex(isCode ? 0 : 1)
                .allowsHitTesting(!isCode)
        }
    }

    private func setEditorMode(_ mode: EditorMode) {
        guard mode != editorMode else { return }

        if editorMode == .preview && mode == .code {
            // Flush the web editor's latest markdown into the store first so
            // the code editor never shows stale text.
            Task { @MainActor in
                await webBridge.flushIntoStore()
                editorModeRaw = mode.rawValue
            }
        } else {
            editorModeRaw = mode.rawValue
            if mode == .preview {
                webBridge.pushStoreTextNow()
            }
        }
    }

    private func syncFromEditor(line: Int) {
        guard let target = store.scrollTarget(forLine: line) else { return }
        scrollTarget = target
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text("No Markdown file open")
                    .font(.title3.weight(.semibold))
                Text("Open a local file or start with the bundled demo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    store.openDemoFile()
                } label: {
                    Label("Open DEMO file", systemImage: "play.rectangle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.openPanel()
                } label: {
                    Label("Open file", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary)
        }
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }
}

private struct AppearanceBridge: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        applyAppearance(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        applyAppearance(from: view)
    }

    private func applyAppearance(from view: NSView) {
        DispatchQueue.main.async {
            let appearance = mode.nsAppearance
            NSApp.appearance = appearance
            NSApp.windows.forEach { $0.appearance = appearance }
            view.window?.appearance = appearance
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var appearanceModeRaw: String
    @Binding var editorModeRaw: String
    @Binding var showNavigationPane: Bool
    @Binding var showingMarkdownHelp: Bool
    let onSelectMode: (EditorMode) -> Void

    private var editorMode: EditorMode {
        EditorMode(rawValue: editorModeRaw) ?? .preview
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(store.currentFileName)
                        .font(.headline)
                        .lineLimit(1)

                    if store.isDirty {
                        Text("Edited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(store.fileURL?.path ?? (store.displayNameOverride == nil ? "Open or drop a local Markdown file" : "Bundled DEMO file"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                store.openPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }

            Button {
                store.save()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(!store.canSave)

            HeaderSeparator()

            HStack(spacing: 4) {
                PaneToggleButton(
                    title: "Navigation",
                    icon: "list.bullet.indent",
                    isOn: showNavigationPane,
                    action: { showNavigationPane.toggle() }
                )

                ModeToggleButton(
                    title: "Code",
                    icon: "chevron.left.forwardslash.chevron.right",
                    isOn: editorMode == .code,
                    action: { onSelectMode(.code) }
                )

                ModeToggleButton(
                    title: "Preview",
                    icon: "doc.richtext",
                    isOn: editorMode == .preview,
                    action: { onSelectMode(.preview) }
                )
            }

            HeaderSeparator()

            HStack(spacing: 4) {
                Button {
                    store.adjustFont(by: -1)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help("Decrease font size (Code mode)")

                Text("\(Int(store.fontSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 26)
                    .foregroundStyle(.secondary)

                Button {
                    store.adjustFont(by: 1)
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Increase font size (Code mode)")
            }
            .buttonStyle(.bordered)

            HeaderSeparator()

            AppearanceButtonGroup(selection: $appearanceModeRaw)

            HeaderSeparator()

            Button {
                showingMarkdownHelp = true
            } label: {
                Image(systemName: "keyboard.badge.ellipsis")
                    .imageScale(.large)
            }
            .help("Markdown formatting guide")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct PaneToggleButton: View {
    let title: String
    let icon: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isOn ? Color.accentColor : Color.secondary)
        .help(title)
    }
}

private struct ModeToggleButton: View {
    let title: String
    let icon: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(isOn ? Color.accentColor : Color.secondary.opacity(0.6))
        .help(title)
    }
}

private struct AppearanceButtonGroup: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            appearanceButton(mode: .system, icon: "circle.lefthalf.filled")
            appearanceButton(mode: .light, icon: "sun.max")
            appearanceButton(mode: .dark, icon: "moon")
        }
    }

    private func appearanceButton(mode: AppearanceMode, icon: String) -> some View {
        Button {
            selection = mode.rawValue
        } label: {
            Image(systemName: icon)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selection == mode.rawValue ? Color.accentColor : Color.secondary)
        .help(mode.title)
    }
}

private struct HeaderSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
    }
}

private struct EditorPane: View {
    @Binding var text: String
    let fontSize: CGFloat
    let scrollTarget: MarkdownScrollTarget?
    let onLineSelected: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Code", icon: "chevron.left.forwardslash.chevron.right")
            MarkdownTextView(
                text: $text,
                fontSize: fontSize,
                scrollTarget: scrollTarget,
                onLineSelected: onLineSelected
            )
        }
    }
}

private struct NavigationPane: View {
    @EnvironmentObject private var store: DocumentStore
    let onSelect: (MarkdownHeading) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Navigation", icon: "list.bullet.indent")

            if store.headings.isEmpty {
                Text("No headings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.headings) { heading in
                            Button {
                                onSelect(heading)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("H\(heading.level)")
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .leading)

                                    Text(heading.text)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct PaneTitle: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        HStack(spacing: 10) {
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("Loading")
            } else {
                Text(store.fileSizeDescription.isEmpty ? "Ready" : store.fileSizeDescription)
            }

            Spacer()

            Text("\(store.text.count) characters")
            Text("UTF-8")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

private struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.tint.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 42, weight: .semibold))
                    Text("Drop Markdown File")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(.tint)
            }
            .padding(16)
    }
}
