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
        // An H1-only edit must be the only byte change on disk, including
        // documents with nested quotes, reference links, tables and raw HTML.
        for name in ["markdown_demo.md", "markdown_demo test.md"] {
            let source=try String(contentsOfFile:FileManager.default.currentDirectoryPath+"/"+name,encoding:.utf8)
            let copy=directory.appendingPathComponent(name)
            try source.write(to:copy,atomically:true,encoding:.utf8)
            await store.open(copy)
            try await waitForEditor(bridge)
            _=try await webView.evaluateJavaScript("(() => { const ed=window.__mdEditorBridge.getEditor();return ed.commands.insertContentAt({from:1,to:ed.state.doc.firstChild.nodeSize-1},'Native H1 edit')})()")
            let end=source.firstIndex(of:"\n")!
            let firstLine=String(source[..<end])
            let trailing=firstLine.range(of:"[ \t\r]*$",options:.regularExpression).map { String(firstLine[$0]) } ?? ""
            let expected="# Native H1 edit"+trailing+source[end...]
            let didSave=await store.saveDocument()
            let actual=try String(contentsOf:copy,encoding:.utf8)
            guard didSave,actual==expected else {
                let detail: [String:Any] = ["file":name,"saved":didSave,"expected":expected,"actual":actual,"error":store.error?.recovery ?? ""]
                try JSONSerialization.data(withJSONObject:detail).write(to:URL(fileURLWithPath:"/tmp/md-h1-save-diagnostic.json"))
                throw Failure("H1 Save changed unrelated Markdown: \(name), saved=\(didSave), error=\(store.error?.recovery ?? "none")")
            }
            _=try await webView.evaluateJavaScript("document.querySelector('[data-view=source]').click();document.querySelector('[data-view=preview]').click();true")
            guard await store.synchronizeEditor(),!store.isDirty,store.text==expected else { throw Failure("Mode switch after Save changed Markdown") }
        }
        // Exact user workflow on both full demo files: edit Preview without
        // saving, then another editor replaces the same file on disk.
        for name in ["markdown_demo.md", "markdown_demo test.md"] {
            let source=try String(contentsOfFile:FileManager.default.currentDirectoryPath+"/"+name,encoding:.utf8)
            let copy=directory.appendingPathComponent("preview-"+name)
            try source.write(to:copy,atomically:true,encoding:.utf8)
            await store.open(copy)
            try await waitForEditor(bridge)
            _=try await webView.evaluateJavaScript("(() => { const ed=window.__mdEditorBridge.getEditor(); ed.commands.insertContentAt({from:1,to:ed.state.doc.firstChild.nodeSize-1},'Локальний незбережений H1');ed.commands.setTextSelection(ed.state.doc.firstChild.nodeSize-1);ed.commands.splitBlock();ed.commands.insertContent('Локальний новий абзац');return true})()")
            let localModel=try await webView.evaluateJavaScript("JSON.stringify(window.__mdEditorBridge.getEditor().getJSON())") as! String
            let end=source.firstIndex(of:"\n")!
            let disk="# Зовнішній H1"+source[end...]+"\nЗовнішній новий абзац.\n"
            try disk.write(to:copy,atomically:true,encoding:.utf8)
            await store.checkDisk()
            guard store.externalChange?.disk?.text==disk else { throw Failure("Unsaved Preview edits hid the full disk version") }
            let deadline=Date().addingTimeInterval(10)
            var visible=false
            while Date()<deadline {
                visible=(try? await webView.evaluateJavaScript("document.querySelector('#native-disk-diff').textContent.includes('Зовнішній новий абзац')") as? Bool)==true
                if visible {break};try await Task.sleep(nanoseconds:50_000_000)
            }
            guard visible,try await webView.evaluateJavaScript("JSON.stringify(window.__mdEditorBridge.getEditor().getJSON())") as? String==localModel else { throw Failure("Disk preview changed the unsaved left document") }
            guard await store.synchronizeEditor(),store.text.contains("Локальний новий абзац"),!store.text.contains("Зовнішній новий абзац") else { throw Failure("Preview edit could not be preserved as local Markdown") }
        }
        // Both H1s change concurrently: the left Code pane must remain local.
        await store.open(first)
        try await waitForEditor(bridge)
        _=try await webView.evaluateJavaScript("(() => { const ed=window.__mdEditorBridge.getEditor();return ed.commands.insertContentAt(1,'LOCAL ')})()")
        guard await store.synchronizeEditor() else { throw Failure("Local snapshot failed") }
        let local=store.text
        try "# EXTERNAL H1\n\nDisk-only text.\n".write(to:first,atomically:true,encoding:.utf8)
        await store.checkDisk()
        guard store.externalChange != nil,store.text==local else { throw Failure("External heading replaced local text") }
        _=try await webView.evaluateJavaScript("document.querySelector('[data-view=source]').click();true")
        guard await store.synchronizeEditor(),store.text==local,!store.text.contains("EXTERNAL H1") else { throw Failure("Left Code shows the disk version") }
        try await Task.sleep(nanoseconds:900_000_000)
        guard try await webView.evaluateJavaScript("document.querySelector('#source-editor').textContent.includes('EXTERNAL H1')") as? Bool==false else { throw Failure("Disk text leaked into the left Code pane") }
        guard try await webView.evaluateJavaScript("document.querySelector('#native-disk-diff').textContent.includes('EXTERNAL H1')") as? Bool==true else { throw Failure("Disk pane did not show external heading") }
        guard try await webView.evaluateJavaScript("document.querySelector('#source-editor .native-deleted')===null") as? Bool==true else { throw Failure("Deleted baseline text is visible in the left Code pane") }
        _=try await webView.evaluateJavaScript("document.querySelector('[data-view=preview]').click();true")
        guard await store.synchronizeEditor(),store.text==local else { throw Failure("Preview replaced the local buffer") }
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
