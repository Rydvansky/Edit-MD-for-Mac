import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: DocumentStore
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue
    @StateObject private var webBridge = WebEditorBridge()
    @State private var dropIsTargeted = false
    @State private var showingMarkdownHelp = false

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some View {
        VStack(spacing: 0) {
            WebEditorPane(bridge: webBridge, store: store)

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
        .background(WindowTitleSync(store: store))
        .focusedSceneValue(\.markdownHelpVisible, $showingMarkdownHelp)
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

/// Keeps the NSWindow chrome in sync with the document: the dirty dot
/// (isDocumentEdited) and the proxy icon (representedURL) — SwiftUI's
/// WindowGroup does not manage those. The title itself is driven declaratively
/// by .navigationTitle on DocumentWindowView (the scene owns NSWindow.title
/// and would clobber this set); the title line here only matters for
/// AppKit-created windows (WindowManager.openNewWindow), where nothing
/// re-asserts the title and save-as renames must still propagate.
private struct WindowTitleSync: NSViewRepresentable {
    let store: DocumentStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(from: view)
    }

    private func apply(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.title = store.windowTitle
            window.isDocumentEdited = store.isDirty
            window.representedURL = store.fileURL
        }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var store: DocumentStore

    private var pathText: String {
        if let path = store.fileURL?.path { return path }
        if store.displayNameOverride != nil { return "markdown_demo.md (bundled demo)" }
        return "No file open"
    }

    var body: some View {
        HStack(spacing: 10) {
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("Loading")
            }

            Text(pathText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if store.isDirty {
                Text("Edited")
            }

            if !store.fileSizeDescription.isEmpty {
                Text(store.fileSizeDescription)
            }

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
