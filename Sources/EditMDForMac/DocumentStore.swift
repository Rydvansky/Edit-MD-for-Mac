import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published private(set) var session = DocumentSession()
    @Published private(set) var fileURL: URL?
    @Published private(set) var displayNameOverride: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var error: AppError?
    private weak var editor: (any DocumentEditor)?
    private var pendingSave: Task<Bool, Never>?
    private var openRequest: UUID?
    private var saveRequest: UUID?

    var text: String { session.text }
    var documentID: UUID { session.id }
    var isDirty: Bool { session.isDirty }
    var documentBaseURL: URL? { fileURL?.deletingLastPathComponent() }
    var currentFileName: String { displayNameOverride ?? fileURL?.lastPathComponent ?? "Untitled Markdown" }
    var windowTitle: String { "\(currentFileName) — Edit MD for Mac" }
    var canSave: Bool { !isLoading && (fileURL != nil || !text.isEmpty || isDirty) }
    var isEmptyState: Bool { fileURL == nil && text.isEmpty && !isDirty && !isLoading }
    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
    }

    func attach(editor: any DocumentEditor) { self.editor = editor }

    @discardableResult
    func accept(_ snapshot: EditorSnapshot) -> Bool { session.accept(snapshot) }

    @discardableResult
    func markEdited(documentID: UUID, revision: Int) -> Bool {
        session.markEdited(documentID: documentID, revision: revision)
    }

    func adjustFont(by delta: CGFloat) { editor?.adjustTextSize(by: Int(delta)) }
    func openPanel() { WindowManager.shared.openPanel(from: self) }

    func openDemoFile() {
        Task {
            guard await confirmDiscardIfNeeded() else { return }
            let bundled = Bundle.main.url(forResource: "markdown_demo", withExtension: "md")
            let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("markdown_demo.md")
            let url = bundled ?? local
            guard FileManager.default.fileExists(atPath: url.path) else {
                resumeEditing(); showError("Demo file is missing."); return
            }
            await open(url, asDemo: true)
        }
    }

    func openFirstMarkdown(from urls: [URL]) async {
        guard let url = urls.first(where: Self.looksLikeMarkdown) else {
            showError("No Markdown file found."); return
        }
        guard await confirmDiscardIfNeeded() else { return }
        await open(url)
    }

    func open(_ url: URL, asDemo: Bool = false) async {
        guard Self.looksLikeMarkdown(url) else { showError("Unsupported file type."); return }
        let request = UUID()
        openRequest = request
        isLoading = true
        defer { if openRequest == request { isLoading = false } }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                return text
            }.value
            guard openRequest == request else { return }
            fileURL = asDemo ? nil : url
            displayNameOverride = asDemo ? url.lastPathComponent : nil
            session = DocumentSession(text: loaded)
            editor?.loadDocument()
            WindowManager.shared.closeExtraEmptyWindowsSoon()
        } catch { resumeEditing(); showError("Could not open the file.", recovery: error.localizedDescription) }
    }

    /// All save/close/switch paths await the same authoritative editor snapshot.
    func captureEditorSnapshot(lock: Bool = false) async throws -> EditorSnapshot {
        let snapshot: EditorSnapshot
        if let received = try await editor?.snapshot(lock: lock) {
            snapshot = received
        } else {
            guard !session.hasPendingEdits else { throw EditorProtocolError.notReady }
            snapshot = session.snapshot
        }
        guard snapshot.documentID == documentID else { throw EditorProtocolError.staleDocument }
        // A newer dirty event may arrive while WebKit returns this snapshot.
        // Keep newer native state, but the captured snapshot is still safe to save.
        _ = accept(snapshot)
        return snapshot
    }

    func synchronizeEditor(lock: Bool = false) async -> Bool {
        do { _ = try await captureEditorSnapshot(lock: lock); return true }
        catch {
            showError("Could not read the latest editor changes.", recovery: error.localizedDescription)
            return false
        }
    }

    func save() { Task { _ = await saveDocument() } }

    @discardableResult
    func saveDocument() async -> Bool {
        // Install the queue entry before awaiting, so simultaneous callers serialize.
        let predecessor = pendingSave
        let requestedDocumentID = documentID
        let request = UUID()
        let task = Task { @MainActor in
            if let predecessor { _ = await predecessor.value }
            guard documentID == requestedDocumentID else { return false }
            return await performSave()
        }
        pendingSave = task
        saveRequest = request
        let result = await task.value
        if saveRequest == request { pendingSave = nil }
        return result
    }

    private func performSave() async -> Bool {
        guard await synchronizeEditor() else { return false }
        let target: URL
        if let fileURL { target = fileURL }
        else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.markdown]
            panel.nameFieldStringValue = "Untitled.md"
            panel.prompt = "Save"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            target = url
        }
        // A save panel can outlive an editor debounce; snapshot again afterwards.
        isSaving = true
        defer { isSaving = false }
        do {
            let snapshot = try await captureEditorSnapshot()
            editor?.setSaveState("saving", revision: snapshot.revision)
            try await Task.detached(priority: .userInitiated) {
                try snapshot.markdown.write(to: target, atomically: true, encoding: .utf8)
            }.value
            guard documentID == snapshot.documentID else { return true }
            fileURL = target
            displayNameOverride = nil
            session.didSave(snapshot)
            editor?.updateContext()
            editor?.setSaveState("saved", revision: snapshot.revision)
            return true
        } catch {
            editor?.setSaveState("failed", revision: session.revision)
            showError("Could not save the file.", recovery: error.localizedDescription)
            return false
        }
    }

    func resumeEditing() { editor?.resumeEditing() }

    func confirmDiscardIfNeeded() async -> Bool {
        var approved = false
        defer { if !approved { resumeEditing() } }
        if let pendingSave { _ = await pendingSave.value }
        while true {
            guard await synchronizeEditor(lock: true) else { return false }
            guard isDirty else { approved = true; return true }
            let alert = NSAlert()
            alert.messageText = "Save changes to \(currentFileName)?"
            alert.informativeText = "Your edits have not been saved."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard await saveDocument() else { return false }
                // An edit made during the write still needs a decision.
            case .alertSecondButtonReturn: approved = true; return true
            default: return false
            }
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in await self?.openFirstMarkdown(from: [url]) }
        }
        return true
    }

    func showError(_ message: String, recovery: String? = nil) { error = AppError(message: message, recovery: recovery) }
    static func looksLikeMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd", "txt"].contains(url.pathExtension.lowercased())
    }
}

struct AppError: Identifiable {
    let id = UUID()
    let message: String
    let recovery: String?
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    var nsAppearance: NSAppearance? { switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) } }
}

extension UTType {
    static var markdown: UTType { UTType(filenameExtension: "md") ?? .plainText }
}
