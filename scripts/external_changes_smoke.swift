import AppKit
import WebKit

@main
struct ExternalChangesSmoke {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); print("PASS: external watcher, clean refresh, mode switches, two panes, apply/Undo, missed-event save guard, deletion"); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }
    struct Failure: Error { let message: String; init(_ message: String) { self.message=message } }
    @MainActor static func wait(_ predicate: () async throws -> Bool) async throws {
        let deadline=Date().addingTimeInterval(12)
        while Date()<deadline { if try await predicate(){return};try await Task.sleep(nanoseconds:50_000_000) }
        throw Failure("Timed out waiting for expected state")
    }
    @MainActor static func run() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("external-check-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let url=directory.appendingPathComponent("note.md")
        let original="# Title\n\nOriginal **bold** text.\n\nLast line.\n"
        try original.write(to:url,atomically:true,encoding:.utf8)
        let store=DocumentStore();await store.open(url)
        let bridge=WebEditorBridge(),web=bridge.makeWebView(store:store)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:800),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=web;window.orderFront(nil)
        try await wait { try await bridge.snapshot(lock:false) != nil }
        for _ in 0..<3 {
            _=try await web.evaluateJavaScript("document.querySelector('[data-view=source]').click();document.querySelector('[data-view=preview]').click();true")
            guard await store.synchronizeEditor(),!store.isDirty,store.text==original else{throw Failure("Mode switching marked the document dirty")}
        }
        let disk="# Title\n\nExternal first update.\n\nLast line.\n"
        try disk.write(to:url,atomically:true,encoding:.utf8)
        try await wait {store.text==disk && !store.isDirty}
        guard store.externalChange==nil else{throw Failure("Clean reader got a conflict panel")}
        _=try await web.evaluateJavaScript("window.__mdEditorBridge.getEditor().commands.insertContent('LOCAL TOKEN ')")
        guard await store.synchronizeEditor(),store.isDirty else{throw Failure("Local editing not tracked")}
        let external="# Title\n\nExternal second update.\n\nNew disk line.\n"
        try external.write(to:url,atomically:true,encoding:.utf8)
        await store.checkDisk()
        try await wait {store.externalChange != nil}
        guard store.text.contains("LOCAL TOKEN"),try String(contentsOf:url,encoding:.utf8)==external else{throw Failure("External change overwrote a buffer or disk")}
        try await wait {
            (try? await web.evaluateJavaScript("!document.getElementById('native-disk-pane').hidden && document.querySelector('#native-disk-diff .ProseMirror h1')!==null && document.querySelector('#native-disk-diff .native-diff-add')!==null && document.querySelector('#native-disk-diff .native-diff-delete')!==null && !document.querySelector('#native-disk-pane button').disabled") as? Bool)==true
        }
        guard try await web.evaluateJavaScript("document.querySelector('#native-disk-diff .ProseMirror').getAttribute('contenteditable')==='false'") as? Bool==true else {throw Failure("Disk preview is editable")}
        try await wait { (try? await web.evaluateJavaScript("!!document.querySelector('.native-added')") as? Bool)==true }
        // Capture a real test window to inspect both banners and the strictly
        // local left editor without interacting with the user's open windows.
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with:nil) { image,error in
                if let image { continuation.resume(returning:image) }
                else { continuation.resume(throwing:error ?? Failure("Snapshot failed")) }
            }
        }
        if let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]) {
            try png.write(to:URL(fileURLWithPath:"/tmp/md-source-comparison.png"))
        }
        let keepToken=store.externalChange!.token
        store.keepLocal(token:keepToken)
        try await wait { (try? await web.evaluateJavaScript("document.getElementById('native-disk-pane').hidden") as? Bool)==true }
        await store.checkDisk()
        guard store.text.contains("LOCAL TOKEN") else { throw Failure("Keep mine changed the local text") }
        guard (try? await web.evaluateJavaScript("document.getElementById('native-disk-pane').hidden") as? Bool)==true else { throw Failure("Keep mine reopened for the same disk version") }
        guard await store.saveDocument()==false else { throw Failure("Keep mine disabled the save guard") }
        try await wait { (try? await web.evaluateJavaScript("!document.getElementById('native-disk-pane').hidden") as? Bool)==true }
        let before=store.text
        guard await store.synchronizeEditor(),store.text==before else { throw Failure("Decorations changed the serialized document") }
        _=try await web.evaluateJavaScript("document.querySelector('[data-view=source]').click();document.querySelector('[data-view=preview]').click();true")
        guard await store.synchronizeEditor(),store.text.contains("LOCAL TOKEN") else{throw Failure("Comparison or mode switching lost local edits")}
        let newer=external+"Latest external token.\n"
        let oldToken=store.externalChange!.token
        try newer.write(to:url,atomically:true,encoding:.utf8)
        await store.checkDisk()
        guard store.externalChange?.token != oldToken else{throw Failure("Panel did not advance to new disk version")}
        await store.applyExternal(token:oldToken)
        guard store.text.contains("LOCAL TOKEN") else{throw Failure("A stale Apply button replaced the document")}
        await store.applyExternal(token:store.externalChange!.token)
        guard store.text==newer,!store.isDirty,store.externalChange==nil else{throw Failure("Apply did not adopt the displayed disk version")}
        _=try await web.evaluateJavaScript("window.__mdEditorBridge.getEditor().commands.undo()")
        guard await store.synchronizeEditor(),store.isDirty,store.text.contains("LOCAL TOKEN") else{throw Failure("One Undo did not restore the local version")}
        // Change disk and save immediately, without waiting for any watcher event.
        let missed="# Disk update immediately before Save\n"
        try missed.write(to:url,atomically:true,encoding:.utf8)
        guard await store.saveDocument()==false,try String(contentsOf:url,encoding:.utf8)==missed,store.externalChange != nil else{throw Failure("Save bypassed the disk guard")}
        // Changing only a toggle summary is a real edit, even with identical body text.
        await store.applyExternal(token:store.externalChange!.token)
        _=try await web.evaluateJavaScript("window.__mdEditorBridge.getEditor().commands.setContent({type:'doc',content:[{type:'toggle',attrs:{summary:'Changed summary'},content:[{type:'paragraph',content:[{type:'text',text:'Body'}]}]}]},true);true")
        guard await store.synchronizeEditor(),store.isDirty,store.text.contains("Changed summary") else{throw Failure("Toggle attributes were not tracked")}
        try FileManager.default.removeItem(at:url)
        await store.checkDisk()
        guard store.externalChange?.disk==nil,store.externalChange?.issue != nil,store.text.contains("Changed summary") else{throw Failure("File deletion lost the buffer")}
        guard await store.saveDocument()==false,!FileManager.default.fileExists(atPath:url.path) else{throw Failure("Save silently recreated a deleted file")}
        // A local conversion failure must never hide successfully read disk
        // data. Inject an unavailable source range, not a file-read failure.
        let recovery=directory.appendingPathComponent("recovery.md")
        try "# Original heading\n\nBody.\n".write(to:recovery,atomically:true,encoding:.utf8)
        await store.open(recovery)
        try await wait { try await bridge.snapshot(lock:false) != nil }
        _=try await web.evaluateJavaScript("(() => { const ed=window.__mdEditorBridge.getEditor();ed.sourceDocument.ranges[0]=undefined;return ed.commands.insertContentAt(1,'LOCAL ') })()")
        let readable="# New disk heading\n\nReadable external data.\n"
        try readable.write(to:recovery,atomically:true,encoding:.utf8)
        await store.checkDisk()
        guard store.externalChange?.disk?.text==readable else { throw Failure("Local conversion failure hid a readable disk version") }
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('#native-disk-diff').textContent.includes('Readable external data')") as? Bool)==true }
        guard try await web.evaluateJavaScript("window.__mdEditorBridge.getEditor().state.doc.textContent.includes('LOCAL')") as? Bool==true else { throw Failure("Local conversion failure replaced the editor") }
        let rejected=store.externalChange!.token
        store.keepLocal(token:rejected)
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('#native-disk-pane').hidden") as? Bool)==true }
        await store.checkDisk()
        guard try await web.evaluateJavaScript("document.querySelector('#native-disk-pane').hidden") as? Bool==true else { throw Failure("Repeated editor failure ignored Keep mine") }
        let latest=readable+"Another disk update.\n"
        try latest.write(to:recovery,atomically:true,encoding:.utf8)
        await store.checkDisk()
        let applyToken=store.externalChange!.token
        await store.applyExternal(token:applyToken)
        guard store.text==latest,!store.isDirty else { throw Failure("Apply depended on serializing the discarded local document") }
        _=try await web.evaluateJavaScript("window.__mdEditorBridge.getEditor().commands.undo()")
        guard await store.synchronizeEditor(),store.text.contains("LOCAL"),store.isDirty else { throw Failure("Apply after failed conversion lost the Undo version") }
        // Also exercise an editor-check failure before the native dirty flag
        // is known. Successfully read disk data still has to be shown.
        let cleanFailure=directory.appendingPathComponent("clean-failure.md")
        try "# Clean buffer\n".write(to:cleanFailure,atomically:true,encoding:.utf8)
        await store.open(cleanFailure)
        try await wait { try await bridge.snapshot(lock:false) != nil }
        _=try await web.evaluateJavaScript("window.__savedGetMarkdown=window.__mdEditorBridge.getMarkdown;window.__mdEditorBridge.getMarkdown=()=>{throw new Error('simulated editor conversion failure')};true")
        try "# Readable disk after editor error\n".write(to:cleanFailure,atomically:true,encoding:.utf8)
        await store.checkDisk()
        guard store.externalChange?.disk?.text.contains("Readable disk") == true else { throw Failure("Clean editor failure hid readable disk data") }
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('#native-disk-diff').textContent.includes('Readable disk after editor error')") as? Bool)==true }
        guard try await web.evaluateJavaScript("window.__mdEditorBridge.getEditor().state.doc.textContent==='Clean buffer'") as? Bool==true else { throw Failure("A failed clean check replaced local content") }
        let recoveryImage: NSImage = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with:nil) { image,error in
                if let image { continuation.resume(returning:image) }
                else { continuation.resume(throwing:error ?? Failure("Recovery snapshot failed")) }
            }
        }
        if let tiff=recoveryImage.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]) {
            try png.write(to:URL(fileURLWithPath:"/tmp/md-disk-preview-recovery.png"))
        }
        _=try await web.evaluateJavaScript("window.__mdEditorBridge.getMarkdown=window.__savedGetMarkdown;true")
        await store.checkDisk()
        guard store.text.contains("Readable disk"),!store.isDirty else { throw Failure("Editor recovery did not refresh the clean document") }
        // The disk pane stays rich when the left is Code, renders nested
        // formatting, and cannot change either document through its controls.
        let previewBase="---\nkind: old\n---\n\n# Disk preview\n\n<details>\n<summary>Section</summary>\n\nOld **bold** text.\n\n</details>\n\n| Head |\n| --- |\n| Old cell |\n"
        let previewDisk=previewBase.replacingOccurrences(of:"kind: old",with:"kind: new").replacingOccurrences(of:"Old **bold**",with:"New **bold**").replacingOccurrences(of:"Old cell",with:"New cell")
        try previewBase.write(to:url,atomically:true,encoding:.utf8)
        await store.open(url)
        try await wait {try await bridge.snapshot(lock:false) != nil}
        _=try await web.evaluateJavaScript("window.__mdEditorBridge.getEditor().commands.insertContentAt(1,'LOCAL ')")
        guard await store.synchronizeEditor() else {throw Failure("Cannot capture local preview edits")}
        let localPreview=store.text
        try previewDisk.write(to:url,atomically:true,encoding:.utf8)
        await store.checkDisk()
        try await wait {(try? await web.evaluateJavaScript("!!document.querySelector('#native-disk-diff details strong') && !!document.querySelector('#native-disk-diff table') && !!document.querySelector('#native-disk-diff .native-diff-delete')") as? Bool)==true}
        _=try await web.evaluateJavaScript("document.querySelector('[data-view=source]').click();true")
        let richCheck=try await web.evaluateJavaScript(#"""
        (()=>{
          const root=document.querySelector('#native-disk-diff'),ed=root.querySelector('.ProseMirror').editor;
          const before=JSON.stringify(ed.getJSON());
          ed.commands.insertContentAt(1,'MUST NOT CHANGE');
          root.querySelector('.toggle-title').click();
          if(root.querySelector('.toggle-title').isContentEditable)return false;
          if(JSON.stringify(ed.getJSON())!==before)return false;
          return root.querySelector('details').open && !!root.querySelector('h1') && ed.state.doc.textContent.includes('kind: new');
        })()
        """#) as? Bool
        guard richCheck==true,await store.synchronizeEditor(),store.text==localPreview else {throw Failure("Disk preview controls changed a buffer or followed the left Code mode")}
        _=try await web.evaluateJavaScript("document.querySelector('[data-view=preview]').click();true")
        let richImage:NSImage=try await withCheckedThrowingContinuation {continuation in
            web.takeSnapshot(with:nil){image,error in
                if let image {continuation.resume(returning:image)}
                else {continuation.resume(throwing:error ?? Failure("Rich preview snapshot failed"))}
            }
        }
        if let tiff=richImage.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]) {
            try png.write(to:URL(fileURLWithPath:"/tmp/md-rich-disk-preview.png"))
        }
        await store.applyExternal(token:store.externalChange!.token)
        guard store.text==previewDisk,!store.isDirty else {throw Failure("Rich preview changed the bytes adopted by Apply")}
        window.orderOut(nil)
    }
}
