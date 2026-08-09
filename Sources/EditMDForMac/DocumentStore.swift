import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published var text = ""
    @Published var fileURL: URL?
    @Published var displayNameOverride: String?
    @Published var isDirty = false
    @Published var isLoading = false
    @Published var isRendering = false
    @Published var previewBlocks = MarkdownParser.parse("Open a Markdown file or drop one here.")
    @Published var headings: [MarkdownHeading] = []
    @Published var referenceLinks: [String: String] = [:]
    @Published var documentBaseURL: URL?
    @Published var error: AppError?
    @Published var fontSize: CGFloat = 15 {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: "editorFontSize")
        }
    }
    @Published var fileSizeDescription = ""
    @Published var previewNotice: String?

    init() {
        let saved = UserDefaults.standard.double(forKey: "editorFontSize")
        if saved >= 11 && saved <= 28 {
            fontSize = saved
        }
    }

    private let previewByteLimit = 1_500_000
    private let largeFileNoticeLimit = 5_000_000
    private var renderTask: Task<Void, Never>?
    private var didOpenStartupArguments = false

    /// Where the most recent text change came from. `.webview` changes must not
    /// be pushed back into the web editor (echo suppression).
    private(set) var lastTextChangeOrigin: TextChangeOrigin = .host

    /// Async hook installed by WebEditorBridge: flushes the web editor's pending
    /// debounced edit and returns its authoritative markdown.
    var markdownFlushProvider: (() async -> String?)?
    /// Synchronous best-effort flush trigger for modal prompts (close/discard).
    var pendingFlushRequest: (() -> Void)?
    /// Reports save lifecycle to the web editor's save indicator (saving/saved/failed).
    var saveStateSink: ((_ state: String, _ flash: Bool) -> Void)?

    /// Apply markdown that came FROM the web editor. Marked dirty, origin .webview.
    func applyWebviewEdit(_ markdown: String) {
        lastTextChangeOrigin = .webview
        text = markdown
        isDirty = true
        scheduleRender()
    }

    var currentFileName: String {
        displayNameOverride ?? fileURL?.lastPathComponent ?? "Untitled Markdown"
    }

    /// Full window title: "<file> — Edit MD for Mac". Driven declaratively via
    /// .navigationTitle in DocumentWindowView (SwiftUI WindowGroup owns
    /// NSWindow.title and would clobber imperative sets — the v2.0.5 title bug).
    var windowTitle: String {
        "\(currentFileName) — Edit MD for Mac"
    }

    var canSave: Bool {
        fileURL != nil || !text.isEmpty
    }

    var isEmptyState: Bool {
        fileURL == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateText(_ newValue: String) {
        lastTextChangeOrigin = .host
        text = newValue
        isDirty = true
        scheduleRender()
    }

    func adjustFont(by delta: CGFloat) {
        fontSize = min(28, max(11, fontSize + delta))
    }

    func scrollTarget(forLine line: Int) -> MarkdownScrollTarget? {
        guard let block = block(containingOrBefore: line) else { return nil }
        return MarkdownScrollTarget(blockID: block.id, line: block.startLine, source: .editor)
    }

    func openStartupArguments() {
        guard !didOpenStartupArguments else { return }
        didOpenStartupArguments = true

        let urls = CommandLine.arguments
            .dropFirst()
            .map(URL.init(fileURLWithPath:))

        guard !urls.isEmpty else {
            scheduleRender()
            return
        }

        Task { @MainActor in
            await openFirstMarkdown(from: Array(urls))
        }
    }

    func openPanel() {
        WindowManager.shared.openPanel(from: self)
    }

    func openDemoFile() {
        guard confirmDiscardIfNeeded() else { return }

        guard let url = Self.demoFileURL() else {
            showError("Demo file is missing.", recovery: "markdown_demo.md was not found in the app bundle or project folder.")
            return
        }

        Task { @MainActor in
            await open(url)
            displayNameOverride = "markdown_demo.md"
            fileURL = nil
            isDirty = false
        }
    }

    func openFirstMarkdown(from urls: [URL]) async {
        guard let url = urls.first(where: { Self.looksLikeMarkdown($0) }) else {
            showError("No Markdown file found.", recovery: "Drop or open a file ending in .md, .markdown, .mdown, or .txt.")
            return
        }

        guard confirmDiscardIfNeeded() else { return }
        await open(url)
    }

    func open(_ url: URL) async {
        guard Self.looksLikeMarkdown(url) else {
            showError("Unsupported file type.", recovery: "\(url.lastPathComponent) does not look like a Markdown file.")
            return
        }

        isLoading = true
        previewNotice = nil

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = values.fileSize ?? 0
            let loaded = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                return String(decoding: data, as: UTF8.self)
            }.value

            fileURL = url
            displayNameOverride = nil
            documentBaseURL = url.deletingLastPathComponent()
            lastTextChangeOrigin = .host
            text = loaded
            isDirty = false
            fileSizeDescription = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)

            if byteCount > largeFileNoticeLimit {
                previewNotice = "Large file mode: editing stays available, and the preview renders only the first readable chunk."
            }

            scheduleRender(immediate: true)
            WindowManager.shared.closeExtraEmptyWindowsSoon()
        } catch {
            showError("Could not open the file.", recovery: error.localizedDescription)
        }

        isLoading = false
    }

    func save() {
        Task { @MainActor in
            // Deterministic flush: pull the web editor's latest markdown
            // (including any pending debounced edit) before writing.
            if let flushed = await markdownFlushProvider?(), flushed != text {
                applyWebviewEdit(flushed)
            }
            performSave()
        }
    }

    private func performSave() {
        if let fileURL {
            save(to: fileURL)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdown]
        panel.nameFieldStringValue = "Untitled.md"
        panel.message = "Save your Markdown file."
        panel.prompt = "Save"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    func save(to url: URL) {
        let content = text
        saveStateSink?("saving", false)
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                }.value

                await MainActor.run {
                    fileURL = url
                    displayNameOverride = nil
                    isDirty = false
                    let bytes = content.data(using: .utf8)?.count ?? 0
                    fileSizeDescription = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                    saveStateSink?("saved", true)
                }
            } catch {
                await MainActor.run {
                    saveStateSink?("failed", false)
                    showError("Could not save the file.", recovery: error.localizedDescription)
                }
            }
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            showError("Drop a Markdown file.", recovery: "This drop did not include a local file URL.")
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
            guard
                let data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }

            Task { @MainActor in
                await self?.openFirstMarkdown(from: [url])
            }
        }

        return true
    }

    private func scheduleRender(immediate: Bool = false) {
        renderTask?.cancel()
        let source = text

        renderTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            await self?.render(source)
        }
    }

    private func render(_ source: String) async {
        isRendering = true
        defer { isRendering = false }

        let bytes = source.utf8.count
        let markdownToRender: String

        if bytes > previewByteLimit {
            let endIndex = source.utf8.index(source.utf8.startIndex, offsetBy: previewByteLimit)
            markdownToRender = String(decoding: source.utf8[..<endIndex], as: UTF8.self)
            previewNotice = "Preview is limited to the first \(ByteCountFormatter.string(fromByteCount: Int64(previewByteLimit), countStyle: .file)) for speed."
        } else if bytes <= largeFileNoticeLimit {
            previewNotice = nil
            markdownToRender = source
        } else {
            markdownToRender = source
        }

        let result = MarkdownParser.parseDocument(markdownToRender.isEmpty ? " " : markdownToRender)
        previewBlocks = result.blocks
        headings = result.headings
        referenceLinks = result.references
    }

    func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }

        // Best-effort flush of any pending web-editor edit before the prompt;
        // the modal alert gives the bridge time to deliver it.
        pendingFlushRequest?()

        let alert = NSAlert()
        alert.messageText = "Save changes to \(currentFileName)?"
        alert.informativeText = "Your edits have not been saved."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveImmediatelyForPrompt()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func saveImmediatelyForPrompt() -> Bool {
        if let fileURL {
            return writeImmediately(to: fileURL)
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdown]
        panel.nameFieldStringValue = "Untitled.md"
        panel.message = "Save your Markdown file."
        panel.prompt = "Save"

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return writeImmediately(to: url)
    }

    private func writeImmediately(to url: URL) -> Bool {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            displayNameOverride = nil
            isDirty = false
            let bytes = text.data(using: .utf8)?.count ?? 0
            fileSizeDescription = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return true
        } catch {
            showError("Could not save the file.", recovery: error.localizedDescription)
            return false
        }
    }

    func showError(_ message: String, recovery: String? = nil) {
        error = AppError(message: message, recovery: recovery)
    }

    private func block(containingOrBefore line: Int) -> MarkdownBlock? {
        if let exact = previewBlocks.first(where: { $0.startLine <= line && line <= $0.endLine }) {
            return exact
        }

        return previewBlocks
            .filter { $0.startLine <= line }
            .max { $0.startLine < $1.startLine }
            ?? previewBlocks.first
    }

    static func looksLikeMarkdown(_ url: URL) -> Bool {
        let allowedExtensions = ["md", "markdown", "mdown", "mkd", "txt"]
        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func demoFileURL() -> URL? {
        if let bundledURL = Bundle.main.url(forResource: "markdown_demo", withExtension: "md") {
            return bundledURL
        }

        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("markdown_demo.md")
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
    }
}

struct AppError: Identifiable {
    let id = UUID()
    let message: String
    let recovery: String?
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum TextChangeOrigin {
    case host
    case webview
}

extension UTType {
    static var markdown: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}
