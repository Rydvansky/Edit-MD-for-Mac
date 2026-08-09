import AppKit
import Foundation
import WebKit

/// Full-width editing surface shown in the main pane.
enum EditorMode: String, CaseIterable, Identifiable {
    case code
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .code: "Code"
        case .preview: "Preview"
        }
    }
}

/// Display settings of the embedded md-editor-plus web editor.
/// Persisted in UserDefaults (prefix `mdplus.`) and sent to the webview in the
/// `init` message, mirroring the `mdEditorPlus.*` VS Code settings.
struct WebEditorSettings: Equatable {
    var theme = "light"            // light | sepia | claude | dark | sync-os (sync-ide falls back to light outside VS Code)
    var font = "sans"              // sans | serif | mono
    var textSize = "m"             // s | m | l | xl  (14/16/18/20 px)
    var pageWidth = 800
    var fullWidth = true
    var alwaysDarkCode = false
    var alwaysDarkDiagram = false
    var alwaysDarkSource = false
    var sourceFullWidth = true
    var shortenCodeSnippets = false
    var smartTypography = true
    var outlineVisible = false
    var structureMapVisible = false
    var sourceWordWrap = false

    private static let prefix = "mdplus."
    private static let keys = [
        "theme", "font", "textSize", "pageWidth", "fullWidth",
        "alwaysDarkCode", "alwaysDarkDiagram", "alwaysDarkSource", "sourceFullWidth",
        "shortenCodeSnippets", "smartTypography", "outlineVisible", "structureMapVisible", "sourceWordWrap",
    ]

    /// Shape expected by the webview's `init`/`saveDefaults` messages.
    var defaultsDictionary: [String: Any] {
        [
            "theme": theme,
            "font": font,
            "textSize": textSize,
            "pageWidth": pageWidth,
            "fullWidth": fullWidth,
            "alwaysDarkCode": alwaysDarkCode,
            "alwaysDarkDiagram": alwaysDarkDiagram,
            "alwaysDarkSource": alwaysDarkSource,
            "sourceFullWidth": sourceFullWidth,
            "shortenCodeSnippets": shortenCodeSnippets,
            "smartTypography": smartTypography,
            "outlineVisible": outlineVisible,
            "structureMapVisible": structureMapVisible,
            "sourceWordWrap": sourceWordWrap,
        ]
    }

    static func load(from defaults: UserDefaults = .standard) -> WebEditorSettings {
        var settings = WebEditorSettings()
        let d = defaults.dictionaryRepresentation()
        if let v = d[prefix + "theme"] as? String { settings.theme = v }
        if let v = d[prefix + "font"] as? String { settings.font = v }
        if let v = d[prefix + "textSize"] as? String { settings.textSize = v }
        if let v = d[prefix + "pageWidth"] as? Int { settings.pageWidth = v }
        if let v = d[prefix + "fullWidth"] as? Bool { settings.fullWidth = v }
        if let v = d[prefix + "alwaysDarkCode"] as? Bool { settings.alwaysDarkCode = v }
        if let v = d[prefix + "alwaysDarkDiagram"] as? Bool { settings.alwaysDarkDiagram = v }
        if let v = d[prefix + "alwaysDarkSource"] as? Bool { settings.alwaysDarkSource = v }
        if let v = d[prefix + "sourceFullWidth"] as? Bool { settings.sourceFullWidth = v }
        if let v = d[prefix + "shortenCodeSnippets"] as? Bool { settings.shortenCodeSnippets = v }
        if let v = d[prefix + "smartTypography"] as? Bool { settings.smartTypography = v }
        if let v = d[prefix + "outlineVisible"] as? Bool { settings.outlineVisible = v }
        if let v = d[prefix + "structureMapVisible"] as? Bool { settings.structureMapVisible = v }
        if let v = d[prefix + "sourceWordWrap"] as? Bool { settings.sourceWordWrap = v }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        for (key, value) in defaultsDictionary {
            defaults.set(value, forKey: Self.prefix + key)
        }
    }

    static func reset(from defaults: UserDefaults = .standard) {
        for key in keys {
            defaults.removeObject(forKey: prefix + key)
        }
    }

    /// Merge a `defaults` payload sent by the webview (`saveDefaults`).
    mutating func apply(dictionary d: [String: Any]) {
        if let v = d["theme"] as? String { theme = v }
        if let v = d["font"] as? String { font = v }
        if let v = d["textSize"] as? String { textSize = v }
        if let v = d["pageWidth"] as? Int { pageWidth = v }
        if let v = d["fullWidth"] as? Bool { fullWidth = v }
        if let v = d["alwaysDarkCode"] as? Bool { alwaysDarkCode = v }
        if let v = d["alwaysDarkDiagram"] as? Bool { alwaysDarkDiagram = v }
        if let v = d["alwaysDarkSource"] as? Bool { alwaysDarkSource = v }
        if let v = d["sourceFullWidth"] as? Bool { sourceFullWidth = v }
        if let v = d["shortenCodeSnippets"] as? Bool { shortenCodeSnippets = v }
        if let v = d["smartTypography"] as? Bool { smartTypography = v }
    }
}

/// Owns the WKWebView running the md-editor-plus bundle and speaks its
/// VS Code-style message protocol with DocumentStore.
///
/// Echo suppression mirrors md-editor-plus in simplified form:
/// - `lastReceivedMarkdown` — markdown that came FROM the webview; store text
///   changes matching it are not sent back.
/// - `lastSentMarkdown` — markdown most recently pushed TO the webview.
@MainActor
final class WebEditorBridge: NSObject, ObservableObject {
    private(set) var webView: WKWebView?
    private weak var store: DocumentStore?

    private var settings = WebEditorSettings.load()
    private var didInitWebview = false
    private var lastReceivedMarkdown: String?
    private var lastSentMarkdown: String?
    private var pendingUpdateTask: Task<Void, Never>?
    private var isReady = false

    func attach(store: DocumentStore) {
        self.store = store
        store.markdownFlushProvider = { [weak self] in await self?.flushIntoStore() }
        store.pendingFlushRequest = { [weak self] in self?.requestPendingFlush() }
        store.saveStateSink = { [weak self] state, flash in self?.postSaveState(state, flash: flash) }
    }

    // MARK: - WebView setup

    func makeWebView() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(ScriptMessageForwarder(bridge: self), name: "mdEditor")
        configuration.userContentController = controller
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")

        if let directory = Self.webviewDirectory() {
            let indexURL = directory.appendingPathComponent("index.html")
            // The document's images resolve to file:// URLs relative to the
            // document directory, which can live anywhere — grant read access
            // from the filesystem root so relative images keep working.
            view.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } else {
            view.loadHTMLString("<pre style='padding:24px'>Webview resources not found (Resources/Webview).</pre>", baseURL: nil)
        }

        webView = view
        return view
    }

    static func webviewDirectory() -> URL? {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Webview") {
            return url.deletingLastPathComponent()
        }
        // Dev fallback: the release/debug binary lives in .build/<config>; walk
        // up from the executable looking for the repo's Resources/Webview.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/Webview", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("index.html").path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    // MARK: - Store -> webview

    /// Called when DocumentStore.text changed from the host side (code editor,
    /// file open, reload). Webview-originated changes are filtered out by the
    /// last-received/last-sent dedup.
    func storeTextDidChange(_ text: String, reload: Bool) {
        guard didInitWebview else { return }
        if !reload, text == lastReceivedMarkdown || text == lastSentMarkdown { return }

        pendingUpdateTask?.cancel()
        pendingUpdateTask = Task { @MainActor [weak self] in
            if !reload {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.sendUpdateNow(text, refresh: reload)
        }
    }

    /// Push the current store text immediately (used when switching back to
    /// preview mode so the webview reflects the latest code-mode edits).
    func pushStoreTextNow() {
        guard didInitWebview, let store else { return }
        pendingUpdateTask?.cancel()
        sendUpdateNow(store.text, refresh: false)
    }

    private func sendUpdateNow(_ markdown: String, refresh: Bool) {
        if !refresh, markdown == lastReceivedMarkdown || markdown == lastSentMarkdown { return }
        lastSentMarkdown = markdown
        var message: [String: Any] = ["type": "update", "markdown": markdown]
        if refresh { message["source"] = "refresh" }
        post(message)
    }

    // MARK: - Webview -> store

    /// Flush the webview's pending debounced edit and return its authoritative
    /// markdown. Returns nil when the webview is not ready.
    @discardableResult
    func flushIntoStore() async -> String? {
        guard let webView else { return nil }
        let js = "(function(){ return window.__mdEditorBridge ? window.__mdEditorBridge.getMarkdown() : null; })()"
        guard let markdown = try? await webView.evaluateJavaScript(js) as? String else { return nil }
        lastReceivedMarkdown = markdown
        if let store, markdown != store.text {
            store.applyWebviewEdit(markdown)
        }
        return markdown
    }

    /// Best-effort flush trigger for synchronous call sites (close prompt):
    /// fires the webview's blur listener, which posts any pending edit.
    func requestPendingFlush() {
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('blur'));", completionHandler: nil)
    }

    // MARK: - Message plumbing

    private func post(_ message: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: message),
            let json = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.__mdEditorFromHost && window.__mdEditorFromHost(\(json));", completionHandler: nil)
    }

    private func postSaveState(_ state: String, flash: Bool) {
        guard isReady else { return }
        post(["type": "saveState", "state": state, "flash": flash])
    }

    fileprivate func handleMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            isReady = true
            sendInit()

        case "edit":
            guard let markdown = body["markdown"] as? String else { return }
            lastReceivedMarkdown = markdown
            store?.applyWebviewEdit(markdown)

        case "save":
            if let markdown = body["markdown"] as? String {
                lastReceivedMarkdown = markdown
                store?.applyWebviewEdit(markdown)
            }
            store?.save()

        case "saveDefaults":
            if let defaults = body["defaults"] as? [String: Any] {
                settings.apply(dictionary: defaults)
                settings.save()
            }

        case "resetDefaults":
            WebEditorSettings.reset()
            settings = WebEditorSettings()

        case "saveSourceWordWrap":
            if let value = body["value"] as? Bool {
                settings.sourceWordWrap = value
                UserDefaults.standard.set(value, forKey: "mdplus.sourceWordWrap")
            }

        case "saveOutlineVisible":
            if let value = body["value"] as? Bool {
                settings.outlineVisible = value
                UserDefaults.standard.set(value, forKey: "mdplus.outlineVisible")
            }

        case "saveStructureMapVisible":
            if let value = body["value"] as? Bool {
                settings.structureMapVisible = value
                UserDefaults.standard.set(value, forKey: "mdplus.structureMapVisible")
            }

        case "copyContent":
            copyToPasteboard(store?.text ?? "")

        case "copyFilePath":
            if let path = store?.fileURL?.path {
                copyToPasteboard(path)
            }

        case "openInFinder":
            if let url = store?.fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

        case "duplicate":
            duplicateCurrentFile()

        case "exportHtml":
            if let html = body["html"] as? String {
                exportHTML(html)
            }

        case "exportPdf":
            if let html = body["html"] as? String {
                exportPDF(html, filename: body["filename"] as? String)
            }

        case "openFromClipboard":
            openFromClipboardPath()

        case "browseMarkdown":
            if let store {
                WindowManager.shared.openPanel(from: store)
            }

        case "conflictPause":
            // No external file watcher in this host — nothing to pause.
            break

        default:
            // Diff viewer, image upload/save, AI tools etc. are VS Code-specific
            // and intentionally unsupported in this host.
            NSLog("[WebEditorBridge] unsupported webview message type: %@", type)
        }
    }

    private func sendInit() {
        guard let store else { return }
        didInitWebview = true
        lastSentMarkdown = store.text
        lastReceivedMarkdown = nil

        var mediaBase = store.documentBaseURL?.absoluteString ?? ""
        if !mediaBase.isEmpty, !mediaBase.hasSuffix("/") { mediaBase += "/" }

        post([
            "type": "init",
            "markdown": store.text,
            "mediaBaseUri": mediaBase,
            "documentPath": store.fileURL?.path ?? store.currentFileName,
            "workspaceName": NSNull(),
            "defaults": settings.defaultsDictionary,
        ])
    }

    // MARK: - Message actions

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func duplicateCurrentFile() {
        guard let store, let url = store.fileURL else { return }
        let copyName = url.deletingPathExtension().lastPathComponent + " copy"
        let copyURL = url.deletingLastPathComponent()
            .appendingPathComponent(copyName)
            .appendingPathExtension(url.pathExtension)
        do {
            try store.text.write(to: copyURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([copyURL])
        } catch {
            store.showError("Could not duplicate the file.", recovery: error.localizedDescription)
        }
    }

    private func exportHTML(_ html: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (store?.fileURL?.deletingPathExtension().lastPathComponent ?? "document") + ".html"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            store?.showError("Could not export HTML.", recovery: error.localizedDescription)
        }
    }

    private func exportPDF(_ html: String, filename: String?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let base = (filename as NSString?)?.deletingPathExtension
            ?? store?.fileURL?.deletingPathExtension().lastPathComponent
            ?? "document"
        panel.nameFieldStringValue = base + ".pdf"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Render the standalone export HTML in an offscreen webview and print to PDF.
        let renderer = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200))
        let delegate = PDFRenderDelegate { [weak self] in
            renderer.createPDF { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url)
                        } catch {
                            self?.store?.showError("Could not write the PDF.", recovery: error.localizedDescription)
                        }
                    case .failure(let error):
                        self?.store?.showError("Could not render the PDF.", recovery: error.localizedDescription)
                    }
                }
            }
        }
        // Retain renderer + delegate until the PDF is written.
        pdfRetained.append((renderer, delegate))
        renderer.navigationDelegate = delegate
        renderer.loadHTMLString(html, baseURL: store?.documentBaseURL)
    }

    private var pdfRetained: [(WKWebView, PDFRenderDelegate)] = []

    private func openFromClipboardPath() {
        guard
            let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty
        else { return }
        let url = URL(fileURLWithPath: string)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        WindowManager.shared.open(urls: [url], useActiveEmptyWindow: true, preferredStore: store)
    }
}

/// WKScriptMessageHandler is nonisolated; forward to the MainActor bridge.
private final class ScriptMessageForwarder: NSObject, WKScriptMessageHandler {
    weak var bridge: WebEditorBridge?

    init(bridge: WebEditorBridge) {
        self.bridge = bridge
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak bridge] in
            bridge?.handleMessage(body)
        }
    }
}

private final class PDFRenderDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give the page a beat for fonts/layout before rasterizing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [onFinish] in
            onFinish()
        }
    }
}
