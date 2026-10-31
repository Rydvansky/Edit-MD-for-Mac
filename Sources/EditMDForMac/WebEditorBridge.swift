import AppKit
import WebKit

/// Versioned transport only. Document state and native system actions live outside it.
@MainActor
final class WebEditorBridge: NSObject, ObservableObject, DocumentEditor, WKNavigationDelegate {
    private(set) var webView: WKWebView?
    private weak var store: DocumentStore?
    private var actions: NativeDocumentActions?
    private var settings = WebEditorSettings.load()
    private var channelID = UUID()
    private var loadedDocumentID: UUID?
    private var ready = false
    private var loadTask: Task<Void, Never>?

    func makeWebView(store: DocumentStore) -> WKWebView {
        if let webView { return webView }
        self.store = store
        store.attach(editor: self)
        actions = NativeDocumentActions(store: store)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(ScriptMessageForwarder(bridge: self), name: "mdEditor")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = self
        webView = view
        loadDocument()
        return view
    }

    func loadDocument() {
        guard let webView else { return }
        ready = false
        loadedDocumentID = nil
        channelID = UUID()
        loadTask?.cancel()
        loadTask = nil
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: "window.__nativeChannelID = '\(channelID.uuidString)';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        guard let directory = Self.webviewDirectory() else {
            store?.showError("Editor resources are missing."); return
        }
        webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    static func webviewDirectory() -> URL? {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Webview") { return url.deletingLastPathComponent() }
        var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<7 {
            let candidate = directory.appendingPathComponent("Resources/Webview", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("index.html").path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private var context: [String: Any] {
        var base = store?.documentBaseURL?.absoluteString ?? ""
        if !base.isEmpty, !base.hasSuffix("/") { base += "/" }
        return ["mediaBaseUri": base, "documentPath": store?.fileURL?.path ?? store?.currentFileName ?? "", "workspaceName": NSNull()]
    }

    private func send(_ payload: [String: Any]) async throws -> [String: Any] {
        guard let webView, let store else { throw EditorProtocolError.notReady }
        let channel = channelID
        let documentID = store.documentID
        let requestID = UUID().uuidString
        var command = payload
        command["protocolVersion"] = 1
        command["channelID"] = channel.uuidString
        command["documentID"] = documentID.uuidString
        command["requestID"] = requestID
        let data = try JSONSerialization.data(withJSONObject: command)
        let json = String(decoding: data, as: UTF8.self)
        let result = try await webView.evaluateJavaScript("window.__nativeEditor.receive(\(json))")
        guard channelID == channel, store.documentID == documentID,
              let reply = result as? [String: Any], reply["protocolVersion"] as? Int == 1,
              reply["channelID"] as? String == channel.uuidString, reply["requestID"] as? String == requestID,
              reply["documentID"] as? String == documentID.uuidString else { throw EditorProtocolError.staleDocument }
        return reply
    }

    func snapshot(lock: Bool) async throws -> EditorSnapshot? {
        // Before initialization there cannot be user edits in this page.
        if !ready { return nil }
        let reply = try await send(["type": "snapshot", "lock": lock])
        guard let id = (reply["documentID"] as? String).flatMap(UUID.init(uuidString:)),
              let revision = reply["revision"] as? Int, revision >= 0,
              let markdown = reply["markdown"] as? String else { throw EditorProtocolError.invalidReply }
        return EditorSnapshot(documentID: id, revision: revision, markdown: markdown)
    }

    func replaceContent(_ markdown: String, expectedRevision: Int?) async throws -> EditorSnapshot {
        guard ready else { throw EditorProtocolError.notReady }
        var command: [String: Any] = ["type": "replace", "markdown": markdown]
        if let expectedRevision { command["expectedRevision"] = expectedRevision }
        let reply = try await send(command)
        guard let revision = reply["revision"] as? Int, let id = store?.documentID,
              let text = reply["markdown"] as? String else { throw EditorProtocolError.invalidReply }
        return EditorSnapshot(documentID: id, revision: revision, markdown: text)
    }
    func showComparison(base: String, disk: String?, token: String, issue: String?) {
        fire(["type": "comparison", "base": base, "disk": disk as Any? ?? NSNull(), "token": token, "issue": issue as Any? ?? NSNull()])
    }
    func clearComparison() { fire(["type": "clearComparison"]) }
    func setBaseline(_ markdown: String, revision: Int) { fire(["type": "baseline", "markdown": markdown, "revision": revision]) }

    func resumeEditing() { fire(["type": "unlock"]) }
    func updateContext() { fire(["type": "context", "context": context]) }
    func setSaveState(_ state: String, revision: Int) { fire(["type": "saveState", "state": state, "revision": revision]) }
    func adjustTextSize(by delta: Int) { fire(["type": "textSize", "delta": delta]) }

    private func fire(_ message: [String: Any]) {
        guard ready else { return }
        let channel = channelID
        let documentID = store?.documentID
        Task {
            guard channelID == channel, store?.documentID == documentID else { return }
            do { _ = try await send(message) }
            catch { if channelID == channel { store?.showError("Editor communication failed.", recovery: error.localizedDescription) } }
        }
    }

    fileprivate func handleMessage(_ message: [String: Any]) {
        guard message["protocolVersion"] as? Int == 1,
              message["channelID"] as? String == channelID.uuidString,
              let type = message["type"] as? String, let store else { return }
        if type == "ready" {
            guard !ready, loadTask == nil else { return }
            let channel = channelID
            loadTask = Task {
                defer { if channelID == channel { loadTask = nil } }
                do {
                    let id = store.documentID
                    _ = try await send(["type": "load", "revision": store.session.revision, "markdown": store.text,
                                        "context": context, "defaults": settings.defaultsDictionary])
                    guard !Task.isCancelled, store.documentID == id else { return }
                    loadedDocumentID = id
                    ready = true
                    store.restoreComparison()
                    store.requestDiskCheck()
                } catch { if !Task.isCancelled { store.showError("Could not initialize the editor.", recovery: error.localizedDescription) } }
            }
            return
        }
        guard ready, loadedDocumentID == store.documentID,
              message["documentID"] as? String == store.documentID.uuidString,
              let revision = message["revision"] as? Int, revision >= 0 else { return }
        switch type {
        case "dirty": _ = store.markEdited(documentID: store.documentID, revision: revision)
        case "edit":
            if let markdown = message["markdown"] as? String {
                _ = store.accept(EditorSnapshot(documentID: store.documentID, revision: revision, markdown: markdown))
            }
        case "conversionError": store.showError("Could not convert this edit safely.", recovery: message["message"] as? String)
        case "save": store.save()
        case "saveLocalAs": store.saveAs()
        case "keepLocal": if let token = message["token"] as? String { store.keepLocal(token: token) }
        case "applyExternal":
            if let token = message["token"] as? String { Task { await store.applyExternal(token: token) } }
        case "saveDefaults":
            if let defaults = message["defaults"] as? [String: Any] { settings.apply(dictionary: defaults); settings.save() }
        case "resetDefaults": WebEditorSettings.reset(); settings = WebEditorSettings()
        case "saveSourceWordWrap", "saveOutlineVisible", "saveStructureMapVisible":
            if let value = message["value"] as? Bool {
                let key = type == "saveSourceWordWrap" ? "sourceWordWrap" : type == "saveOutlineVisible" ? "outlineVisible" : "structureMapVisible"
                UserDefaults.standard.set(value, forKey: "mdplus." + key)
                settings = WebEditorSettings.load()
            }
        case "refresh": Task { await store.openFirstMarkdown(from: store.fileURL.map { [$0] } ?? []) }
        case "conflictPause": break // Native host owns disk conflicts; the vendor panel is not a file watcher.
        default: actions?.handle(message)
        }
        fire(["type": "ack", "messageID": message["messageID"] ?? 0, "revision": store.session.revision])
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Keep the native baseline and fail snapshots rather than silently saving stale text.
        store?.showError("The editor process stopped.", recovery: "Reopen the file to restart the editor. Unsaved editor changes may be unavailable.")
    }
}

private final class ScriptMessageForwarder: NSObject, WKScriptMessageHandler {
    weak var bridge: WebEditorBridge?
    init(bridge: WebEditorBridge) { self.bridge = bridge }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak bridge] in bridge?.handleMessage(body) }
    }
}

enum EditorProtocolError: LocalizedError {
    case notReady, staleDocument, invalidReply
    var errorDescription: String? {
        switch self {
        case .notReady: "The editor is not ready."
        case .staleDocument: "The editor replied for an outdated document or revision."
        case .invalidReply: "The editor returned an invalid acknowledgment."
        }
    }
}
