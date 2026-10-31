import AppKit
import WebKit

/// Compile with -DARCHITECTURE_SMOKE and the app sources to exercise the real
/// native transport, DocumentStore, WebKit, and disk operations together.
@main
struct NativeBridgeSmoke {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); print("PASS: native bridge, disk save, document switch, stale messages, close/cancel"); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        app.run()
    }

    @MainActor
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("edit-md-native-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.md")
        let second = directory.appendingPathComponent("second.md")
        let original = "# Original\r\n\r\nUnchanged  \r\ncontent\r\n"
        try original.write(to: first, atomically: true, encoding: .utf8)
        try "# Second\n".write(to: second, atomically: true, encoding: .utf8)
        let store = DocumentStore()
        await store.open(first)
        let bridge = WebEditorBridge()
        let webView = bridge.makeWebView(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFront(nil)
        try await waitForEditor(bridge)
        guard await store.synchronizeEditor(), store.text == original, !store.isDirty else { throw Failure("Opening changed the original text") }
        let oldID = store.documentID
        let oldChannel = try await webView.evaluateJavaScript("window.__nativeChannelID") as! String
        _ = try await webView.evaluateJavaScript("window.__mdEditorBridge.getEditor().commands.insertContent('Native saved token ')")
        guard await store.saveDocument(), try String(contentsOf: first, encoding: .utf8).contains("Native saved token"), !store.isDirty else { throw Failure("Save lost the pending editor change") }
        let firstSave = Task { @MainActor in await store.saveDocument() }
        _ = try await webView.evaluateJavaScript("window.__mdEditorBridge.getEditor().commands.insertContent('Concurrent edit token ')")
        let secondSave = Task { @MainActor in await store.saveDocument() }
        guard await firstSave.value, await secondSave.value,
              try String(contentsOf: first, encoding: .utf8).contains("Concurrent edit token"), !store.isDirty else {
            throw Failure("Overlapping saves lost a newer edit")
        }
        await store.open(second)
        try await waitForEditor(bridge)
        let payload: [String: Any] = ["protocolVersion": 1, "channelID": oldChannel, "documentID": oldID.uuidString, "revision": 1000, "messageID": 1000, "type": "edit", "markdown": "wrong document"]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        _ = try await webView.evaluateJavaScript("window.webkit.messageHandlers.mdEditor.postMessage(\(json)); true")
        try await Task.sleep(nanoseconds: 100_000_000)
        guard await store.synchronizeEditor(), store.text == "# Second\n", store.documentID != oldID else { throw Failure("Stale message changed the current document") }
        guard await store.confirmDiscardIfNeeded() else { throw Failure("An unchanged document asked to save") }
        guard try await webView.evaluateJavaScript("document.body.inert") as? Bool == true else { throw Failure("Close did not lock edits") }
        store.resumeEditing()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard try await webView.evaluateJavaScript("document.body.inert") as? Bool == false else { throw Failure("Cancel did not restore editing") }
        window.orderOut(nil)
    }

    @MainActor
    static func waitForEditor(_ bridge: WebEditorBridge) async throws {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let _ = try await bridge.snapshot(lock: false) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw Failure("Editor did not initialize")
    }
    struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
}
