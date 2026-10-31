import AppKit
import SwiftUI

#if !ARCHITECTURE_SMOKE
@main
struct EditMDForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DocumentWindowView()
                .onAppear {
                    appDelegate.openStartupArgumentsIfNeeded()
                }
        }
        .commands {
            DocumentCommands()
        }
    }
}

#endif

struct DocumentWindowView: View {
    @StateObject private var store: DocumentStore
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue
    private let initialURL: URL?

    init(initialURL: URL? = nil) {
        _store = StateObject(wrappedValue: DocumentStore())
        self.initialURL = initialURL
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some View {
        ContentView()
            .environmentObject(store)
            .focusedSceneValue(\.documentStore, store)
            // Declarative window title — the WindowGroup scene owns
            // NSWindow.title and re-asserts it on state updates, so an
            // imperative set from a representable loses the race (v2.0.5 bug:
            // title showed only the default, no file name). Binding it through
            // .navigationTitle makes SwiftUI itself write the title on every
            // store change. Inert inside AppKit-hosted windows, where
            // WindowTitleSync's imperative set covers save-as renames.
            .navigationTitle(store.windowTitle)
            .background(WindowRegistrationView(store: store))
            .preferredColorScheme(appearanceMode.colorScheme)
            .frame(minWidth: 940, minHeight: 620)
            .task {
                guard let initialURL else { return }
                await store.open(initialURL)
            }
    }
}

struct DocumentCommands: Commands {
    @FocusedValue(\.documentStore) private var store
    @FocusedValue(\.markdownHelpVisible) private var markdownHelpVisible

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open...") {
                if let store {
                    store.openPanel()
                } else {
                    WindowManager.shared.openPanel()
                }
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Save") {
                store?.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(store?.canSave != true)

            Button("Save As…") {
                store?.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(store?.canSave != true)

            Divider()

            Button("Increase Font Size") {
                store?.adjustFont(by: 1)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(store == nil)

            Button("Decrease Font Size") {
                store?.adjustFont(by: -1)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(store == nil)
        }

        CommandGroup(after: .toolbar) {
            Menu("Appearance") {
                AppearanceModeMenuItems()
            }
        }

        CommandGroup(replacing: .help) {
            Button("Markdown Guide") {
                markdownHelpVisible?.wrappedValue = true
            }
            .keyboardShortcut("/", modifiers: .command)
        }
    }
}

/// Radio-style System / Light / Dark items. Writes the same `appearanceMode`
/// UserDefaults key the windows read via @AppStorage, so every window's
/// AppearanceBridge / preferredColorScheme updates immediately.
private struct AppearanceModeMenuItems: View {
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    var body: some View {
        ForEach(AppearanceMode.allCases) { mode in
            Button {
                appearanceModeRaw = mode.rawValue
            } label: {
                if appearanceModeRaw == mode.rawValue {
                    Label(mode.title, systemImage: "checkmark")
                } else {
                    Text(mode.title)
                }
            }
        }
    }
}

struct FocusedDocumentStoreKey: FocusedValueKey {
    typealias Value = DocumentStore
}

struct MarkdownHelpVisibleKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var documentStore: DocumentStore? {
        get { self[FocusedDocumentStoreKey.self] }
        set { self[FocusedDocumentStoreKey.self] = newValue }
    }

    var markdownHelpVisible: Binding<Bool>? {
        get { self[MarkdownHelpVisibleKey.self] }
        set { self[MarkdownHelpVisibleKey.self] = newValue }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didOpenStartupArguments = false
    private var isConfirmingTermination = false

    func openStartupArgumentsIfNeeded() {
        guard !didOpenStartupArguments else { return }
        didOpenStartupArguments = true

        let urls = CommandLine.arguments
            .dropFirst()
            .map(URL.init(fileURLWithPath:))

        guard !urls.isEmpty else { return }
        WindowManager.shared.open(urls: urls, useActiveEmptyWindow: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        WindowManager.shared.open(urls: urls, useActiveEmptyWindow: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isConfirmingTermination else { return .terminateLater }
        isConfirmingTermination = true
        Task { @MainActor in
            let approved = await WindowManager.shared.confirmTermination()
            isConfirmingTermination = false
            sender.reply(toApplicationShouldTerminate: approved)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private struct WeakWindow {
        weak var value: NSWindow?
    }

    private struct WeakStore {
        weak var value: DocumentStore?
    }

    private var retainedDocumentWindows: [ObjectIdentifier: NSWindow] = [:]
    private var closingDocumentWindows: [ObjectIdentifier: NSWindow] = [:]
    private var registeredWindowIDs = Set<ObjectIdentifier>()
    private var windowsByID: [ObjectIdentifier: WeakWindow] = [:]
    private var storesByID: [ObjectIdentifier: WeakStore] = [:]
    private weak var activeStore: DocumentStore?
    private var pendingOpenURLs: [URL] = []
    private var pendingCloseIDs = Set<ObjectIdentifier>()

    func register(window: NSWindow, store: DocumentStore) {
        let id = ObjectIdentifier(window)
        windowsByID[id] = WeakWindow(value: window)
        storesByID[id] = WeakStore(value: store)

        if !registeredWindowIDs.contains(id) {
            registeredWindowIDs.insert(id)
            window.delegate = self
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowBecameKey(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }

        if window.isKeyWindow || activeStore == nil {
            activeStore = store
        }

        if store.isEmptyState, !store.isLoading, !pendingOpenURLs.isEmpty {
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            open(urls: urls, useActiveEmptyWindow: true, preferredStore: store)
        }

        closeExtraEmptyWindowsSoon()
    }

    func openPanel(from store: DocumentStore? = nil) {
        let targetStore = store ?? activeStore

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdown, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose one or more Markdown files to open."
        panel.prompt = "Open"

        guard panel.runModal() == .OK else { return }
        open(urls: panel.urls, useActiveEmptyWindow: true, preferredStore: targetStore)
    }

    func open(urls: [URL], useActiveEmptyWindow: Bool, preferredStore: DocumentStore? = nil) {
        let markdownURLs = urls.filter(DocumentStore.looksLikeMarkdown)
        guard !markdownURLs.isEmpty else {
            preferredStore?.showError("No Markdown file found.", recovery: "Choose a file ending in .md, .markdown, .mdown, .mkd, or .txt.")
            return
        }

        var remaining = markdownURLs
        if useActiveEmptyWindow, preferredStore == nil, activeStore == nil {
            pendingOpenURLs.append(contentsOf: markdownURLs)
            return
        }

        if
            useActiveEmptyWindow,
            let first = remaining.first,
            let store = preferredStore ?? activeStore,
            store.isEmptyState,
            !store.isLoading
        {
            remaining.removeFirst()
            Task { @MainActor in
                await store.open(first)
            }
        }

        for url in remaining {
            openNewWindow(url: url)
        }

        closeExtraEmptyWindowsSoon()
    }

    func openNewWindow(url: URL) {
        let view = DocumentWindowView(initialURL: url)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(url.lastPathComponent) — Edit MD for Mac"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: view)
        retainedDocumentWindows[ObjectIdentifier(window)] = window
        window.makeKeyAndOrderFront(nil)
    }

    func closeExtraEmptyWindowsSoon() {
        Task { @MainActor in
            await Task.yield()
            closeExtraEmptyWindows()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let id = ObjectIdentifier(window)
        let closingStore = storesByID[id]?.value

        if let retainedWindow = retainedDocumentWindows.removeValue(forKey: id) {
            closingDocumentWindows[id] = retainedWindow
            releaseClosedWindowLater(id)
        }

        registeredWindowIDs.remove(id)
        windowsByID[id] = nil
        storesByID[id] = nil

        if let closingStore, activeStore === closingStore {
            activeStore = storesByID.values.compactMap(\.value).first
        }

        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        cleanupReleasedWindows()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let id = ObjectIdentifier(sender)
        guard !pendingCloseIDs.contains(id) else { return false }
        guard let store = storesByID[id]?.value else { return true }
        pendingCloseIDs.insert(id)
        Task { @MainActor in
            let approved = await store.confirmDiscardIfNeeded()
            pendingCloseIDs.remove(id)
            if approved { sender.close() }
        }
        return false
    }

    func confirmTermination() async -> Bool {
        let stores = storesByID.values.compactMap(\.value)
        for store in stores {
            guard await store.confirmDiscardIfNeeded() else {
                stores.forEach { $0.resumeEditing() }
                return false
            }
        }
        return true
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let store = storesByID[ObjectIdentifier(window)]?.value
        else { return }

        activeStore = store
    }

    private func closeExtraEmptyWindows() {
        cleanupReleasedWindows()

        let hasOpenDocument = storesByID.values.contains { weakStore in
            guard let store = weakStore.value else { return false }
            return !store.isEmptyState
        }

        guard hasOpenDocument else { return }

        let emptyWindows = storesByID.compactMap { id, weakStore -> NSWindow? in
            guard
                let store = weakStore.value,
                store.isEmptyState,
                !store.isLoading,
                let window = windowsByID[id]?.value
            else { return nil }

            return window
        }

        for window in emptyWindows {
            // Even an apparently empty editor may have an undelivered edit.
            // Use the same snapshot/confirmation path as a user-initiated close.
            window.performClose(nil)
        }
    }

    private func cleanupReleasedWindows() {
        windowsByID = windowsByID.filter { $0.value.value != nil }
        storesByID = storesByID.filter { $0.value.value != nil }
        registeredWindowIDs = registeredWindowIDs.filter { windowsByID[$0]?.value != nil }
    }

    private func releaseClosedWindowLater(_ id: ObjectIdentifier) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            closingDocumentWindows[id] = nil
        }
    }
}

struct WindowRegistrationView: NSViewRepresentable {
    let store: DocumentStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        register(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        register(from: view)
    }

    private func register(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            WindowManager.shared.register(window: window, store: store)
        }
    }
}
