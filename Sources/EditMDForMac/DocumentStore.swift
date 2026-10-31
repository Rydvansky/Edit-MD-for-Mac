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
    private var observation: FileObservation?
    private var diskBaseline: DiskVersion?
    private var checkTask: Task<Void, Never>?
    private var checkAgain = false
    private var dismissedExternalToken: String?
    @Published private(set) var externalChange: ExternalChange?

    struct ExternalChange {
        let token = UUID().uuidString
        let disk: DiskVersion?
        let issue: String?
    }

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
                try DiskAccess.read(url)
            }.value
            guard openRequest == request else { return }
            fileURL = asDemo ? nil : url
            displayNameOverride = asDemo ? url.lastPathComponent : nil
            session = DocumentSession(text: loaded.text)
            diskBaseline = asDemo ? nil : loaded
            externalChange = nil
            startObservation()
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
            showError("Could not read the latest editor changes.", recovery: Self.editorErrorDetail(error))
            return false
        }
    }

    func save() { Task { _ = await saveDocument() } }

    // The File menu and the conflict banner share the same snapshot and write
    // safeguards, so Save As always includes the latest editor input.
    func saveAs() { Task { _ = await saveDocument(asNewFile: true) } }

    @discardableResult
    func saveDocument(asNewFile: Bool = false) async -> Bool {
        // Install the queue entry before awaiting, so simultaneous callers serialize.
        let predecessor = pendingSave
        let requestedDocumentID = documentID
        let request = UUID()
        let task = Task { @MainActor in
            if let predecessor { _ = await predecessor.value }
            guard documentID == requestedDocumentID else { return false }
            return await performSave(asNewFile: asNewFile)
        }
        pendingSave = task
        saveRequest = request
        let result = await task.value
        if saveRequest == request { pendingSave = nil }
        return result
    }

    private func performSave(asNewFile: Bool) async -> Bool {
        guard await synchronizeEditor() else { return false }
        let target: URL
        if let fileURL, !asNewFile { target = fileURL }
        else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.markdown]
            panel.directoryURL = fileURL?.deletingLastPathComponent()
            panel.nameFieldStringValue = asNewFile ? ((currentFileName as NSString).deletingPathExtension + " copy.md") : "Untitled.md"
            panel.prompt = "Save"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            target = url
        }
        let sameFile = fileURL.map { Self.sameFile($0, target) } ?? false
        if asNewFile && sameFile {
            showError("Choose a different file.", recovery: "Save your version to a new path to preserve the external version.")
            return false
        }
        // A save panel can outlive an editor debounce; snapshot again afterwards.
        isSaving = true
        defer { isSaving = false }
        let snapshot: EditorSnapshot
        do { snapshot = try await captureEditorSnapshot() }
        catch {
            showError("Could not prepare the local version for saving.", recovery: Self.editorErrorDetail(error))
            resumeEditing()
            return false
        }
        do {
            editor?.setSaveState("saving", revision: snapshot.revision)
            let expected = sameFile ? diskBaseline : try? DiskAccess.read(target)
            let result = try await Task.detached(priority: .userInitiated) {
                try DiskAccess.write(snapshot.markdown, to: target, expecting: expected)
            }.value
            guard documentID == snapshot.documentID else { return false }
            guard case .written(let written) = result else {
                editor?.setSaveState("failed", revision: session.revision)
                if sameFile {
                    if !isDirty { dismissedExternalToken = nil; isSaving = false; await checkDisk() }
                    else if case .changed(let current) = result { presentExternal(current, issue: current == nil ? "The file was removed from disk." : nil, force: true) }
                } else { showError("The destination changed.", recovery: "Choose another path to save your version safely.") }
                resumeEditing()
                return false
            }
            diskBaseline = written
            externalChange = nil
            editor?.clearComparison()
            guard documentID == snapshot.documentID else { return true }
            fileURL = target
            displayNameOverride = nil
            session.didSave(snapshot)
            startObservation()
            editor?.setBaseline(snapshot.markdown, revision: snapshot.revision)
            editor?.updateContext()
            editor?.setSaveState("saved", revision: snapshot.revision)
            return true
        } catch {
            editor?.setSaveState("failed", revision: session.revision)
            if sameFile {
                presentExternal(nil, issue: "The file could not be checked or saved. Save your version as a new file.", force: true)
                resumeEditing()
            } else { showError("Could not save the file.", recovery: error.localizedDescription) }
            return false
        }
    }

    static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath() == rhs.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func startObservation() {
        observation = nil
        guard let url = fileURL else { return }
        observation = FileObservation(url: url) { [weak self] in
            Task { @MainActor [weak self] in self?.requestDiskCheck() }
        }
    }

    func requestDiskCheck() {
        if checkTask != nil { checkAgain = true; return }
        checkTask = Task {
            repeat {
                checkAgain = false
                await checkDisk()
            } while checkAgain && !Task.isCancelled
            checkTask = nil
        }
    }

    /// Disk data and editor conversion have independent failure paths. A
    /// readable external version must remain available even when local edits
    /// cannot currently be serialized for Save.
    func checkDisk() async {
        guard let url = fileURL, !isSaving, !isLoading else { return }
        let id = documentID
        let baselineAtStart = diskBaseline
        let version: DiskVersion
        do {
            version = try await Task.detached(priority: .utility) { try DiskAccess.read(url) }.value
        } catch {
            guard documentID == id, fileURL == url, !isSaving, diskBaseline == baselineAtStart else { return }
            presentExternal(nil, issue: FileManager.default.fileExists(atPath: url.path)
                ? "The file could not be read. Your local text is preserved."
                : "The file was removed from disk. Your local text is preserved.")
            return
        }
        guard documentID == id, fileURL == url, !isSaving, diskBaseline == baselineAtStart else { return }
        guard version != diskBaseline else {
            if externalChange != nil { externalChange = nil; editor?.clearComparison() }
            return
        }
        if let pending = externalChange, pending.disk == version, pending.token == dismissedExternalToken { return }
        // A known dirty buffer needs no conversion to display the independent
        // disk pane. Avoid making the preview wait for local serialization.
        if isDirty { presentExternal(version, issue: nil); return }
        let current: EditorSnapshot
        do {
            current = try await captureEditorSnapshot()
        } catch {
            guard documentID == id, fileURL == url, !isSaving, diskBaseline == baselineAtStart else { return }
            NSLog("[FileCheck] Local editor snapshot failed: %@", Self.editorErrorDetail(error))
            presentExternal(version, issue: "The local editor could not be checked. The disk version is shown below.")
            return
        }
        guard documentID == id, !isSaving, diskBaseline == baselineAtStart else { return }
        if !isDirty {
            do {
                let applied = try await editor?.replaceContent(version.text, expectedRevision: current.revision)
                    ?? EditorSnapshot(documentID: id, revision: session.revision + 1, markdown: version.text)
                guard documentID == id else { return }
                _ = accept(applied)
                session.didSave(applied)
                diskBaseline = version
                externalChange = nil
                editor?.setBaseline(version.text, revision: applied.revision)
                editor?.clearComparison()
            } catch { presentExternal(version, issue: nil) }
        } else { presentExternal(version, issue: nil) }
    }

    private static func editorErrorDetail(_ error: Error) -> String {
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }

    private func presentExternal(_ disk: DiskVersion?, issue: String?, force: Bool = false) {
        if externalChange?.disk == disk, externalChange?.issue == issue, let change = externalChange {
            if force { dismissedExternalToken = nil; editor?.showComparison(base: diskBaseline?.text ?? session.savedText, disk: disk?.text, token: change.token, issue: issue) }
            return
        }
        let keepDismissed = !force && externalChange?.disk == disk && externalChange?.token == dismissedExternalToken && externalChange != nil
        dismissedExternalToken = nil
        let change = ExternalChange(disk: disk, issue: issue)
        externalChange = change
        if keepDismissed { dismissedExternalToken = change.token; return }
        editor?.showComparison(base: diskBaseline?.text ?? session.savedText, disk: disk?.text, token: change.token, issue: issue)
    }

    func keepLocal(token: String) {
        guard externalChange?.token == token else { return }
        dismissedExternalToken = token
        editor?.clearComparison()
    }

    func restoreComparison() {
        if let change = externalChange, change.token != dismissedExternalToken {
            if !isDirty && change.disk != nil { requestDiskCheck(); return }
            editor?.showComparison(base: diskBaseline?.text ?? session.savedText, disk: change.disk?.text, token: change.token, issue: change.issue)
        }
    }

    func applyExternal(token: String) async {
        guard let change = externalChange, change.token == token, let shown = change.disk, let url = fileURL else { return }
        let id = documentID
        let latest: DiskVersion
        do {
            latest = try await Task.detached(priority: .utility) { try DiskAccess.read(url) }.value
        } catch {
            guard documentID == id, externalChange?.token == token else { return }
            presentExternal(nil, issue: "The file could not be read. Your local text is preserved.")
            return
        }
        guard documentID == id, externalChange?.token == token else { return }
        guard latest == shown else { presentExternal(latest, issue: nil); return }
        do {
            let applied = try await editor?.replaceContent(shown.text, expectedRevision: nil)
                ?? EditorSnapshot(documentID: id, revision: session.revision + 1, markdown: shown.text)
            guard documentID == id else { return }
            _ = accept(applied)
            session.didSave(applied)
            diskBaseline = shown
            externalChange = nil
            editor?.setBaseline(shown.text, revision: applied.revision)
            editor?.clearComparison()
        } catch {
            guard documentID == id else { return }
            NSLog("[FileCheck] Applying disk version failed: %@", Self.editorErrorDetail(error))
            presentExternal(shown, issue: "The editor could not apply this version. Both versions are preserved.", force: true)
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
