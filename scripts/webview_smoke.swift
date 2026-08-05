import Foundation
import WebKit

// Headless smoke test for the bundled md-editor-plus webview:
// 1. Loads Resources/Webview/index.html in an offscreen WKWebView.
// 2. Answers the webview's 'ready' handshake with an 'init' message carrying
//    markdown (the same shape DocumentStore/WebEditorBridge sends).
// 3. Verifies the TipTap editor mounted, round-trips markdown through
//    window.__mdEditorBridge.getMarkdown(), and takes a snapshot PNG.

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let webviewDir = URL(fileURLWithPath: root).appendingPathComponent("Resources/Webview")
let indexURL = webviewDir.appendingPathComponent("index.html")
let demoURL = URL(fileURLWithPath: root).appendingPathComponent("markdown_demo.md")
let demoMarkdown = (try? String(contentsOf: demoURL, encoding: .utf8)) ?? "# Hello\n\n- [ ] task\n"
// Fixture exercising v2.0.3 features: a toggle (editable title NodeView) and a
// table (TableWithRail NodeView with the "+" append bands). v2.0.4 adds two
// column-width tables: one uniform-dash (must stay attr-free) and one with
// proportional dash counts (must restore colwidth 80/200).
let fixture = """


<details>
<summary>Smoke toggle</summary>

Toggle body text

</details>

| SmkA | SmkB |
|------|------|
| 1    | 2    |

| Wide | Wider |
| ---- | ---------- |
| a    | b      |
"""
let markdown = demoMarkdown + fixture

final class Delegate: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var ready = false
    var navDone = false
    var consoleErrors: [String] = []

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "mdEditor", let body = message.body as? [String: Any], let type = body["type"] as? String {
            NSLog("[smoke] webview -> host: %@ %@", type, type == "edit" ? "(\((body["markdown"] as? String ?? "").count) chars)" : "")
            if type == "ready" { ready = true }
        }
        if message.name == "mdConsole", let body = message.body as? String {
            consoleErrors.append(body)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navDone = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[smoke] navigation failed: %@", error.localizedDescription)
        navDone = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[smoke] provisional navigation failed: %@", error.localizedDescription)
        navDone = true
    }
}

let delegate = Delegate()
let config = WKWebViewConfiguration()
let controller = WKUserContentController()
controller.add(delegate, name: "mdEditor")
config.userContentController = controller

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: config)
webView.navigationDelegate = delegate
webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))

let deadline = Date().addingTimeInterval(20)
while !delegate.navDone, Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
guard delegate.navDone else {
    NSLog("[smoke] FAIL: page never finished loading")
    exit(1)
}

// Wait for the webview's 'ready' handshake.
let readyDeadline = Date().addingTimeInterval(20)
while !delegate.ready, Date() < readyDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
guard delegate.ready else {
    NSLog("[smoke] FAIL: webview never posted 'ready'")
    exit(1)
}
NSLog("[smoke] got 'ready', sending init")

// Send init exactly like WebEditorBridge does.
let defaults: [String: Any] = [
    "theme": "light", "font": "sans", "textSize": "m", "pageWidth": 800,
    "fullWidth": false, "alwaysDarkCode": false, "alwaysDarkDiagram": false,
    "alwaysDarkSource": false, "sourceFullWidth": false, "shortenCodeSnippets": false,
    "smartTypography": true, "outlineVisible": false, "structureMapVisible": false,
    "sourceWordWrap": false,
]
let initMsg: [String: Any] = [
    "type": "init",
    "markdown": markdown,
    "mediaBaseUri": "",
    "documentPath": "markdown_demo.md",
    "workspaceName": NSNull(),
    "defaults": defaults,
]
let json = String(data: try! JSONSerialization.data(withJSONObject: initMsg), encoding: .utf8)!

var initError: String?
var semaphore = false
webView.evaluateJavaScript("window.__mdEditorFromHost && window.__mdEditorFromHost(\(json)); 'ok'") { result, error in
    if let error { initError = error.localizedDescription }
    semaphore = true
}
let jsDeadline = Date().addingTimeInterval(10)
while !semaphore, Date() < jsDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
if let initError {
    NSLog("[smoke] FAIL: init injection error: %@", initError)
    exit(1)
}

// Give TipTap a moment to mount, then verify the editor exists.
Thread.sleep(forTimeInterval: 2.5)

var mounted: Any?
semaphore = false
webView.evaluateJavaScript("({prosemirror: !!document.querySelector('#editor .ProseMirror'), bridge: !!window.__mdEditorBridge, bodyChars: document.body.innerText.length, logo: !!document.querySelector('.toolbar-logo'), aiPanel: !!document.getElementById('bm-ai'), aiMenuEntry: !!Array.from(document.querySelectorAll('[data-menu]')).find(b => b.dataset.menu === 'turn-into-ai'), usingAiText: document.body.innerHTML.includes('Using AI'), toggleTitle: !!document.querySelector('.ProseMirror details summary .toggle-title'), smokeToggle: !!Array.from(document.querySelectorAll('.ProseMirror details summary .toggle-title')).find(el => el.textContent === 'Smoke toggle'), tableWrap: !!document.querySelector('.ProseMirror .mp-table'), tableAddRow: !!document.querySelector('.ProseMirror .mp-table .mp-table-add-row'), tableAddCol: !!document.querySelector('.ProseMirror .mp-table .mp-table-add-col'), flyoutGone: !document.querySelector('.block-picker-flyout')})") { result, error in
    if let error { NSLog("[smoke] mount check error: %@", error.localizedDescription) }
    mounted = result
    semaphore = true
}
let mountDeadline = Date().addingTimeInterval(10)
while !semaphore, Date() < mountDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
NSLog("[smoke] mount check: %@", String(describing: mounted))
guard let info = mounted as? [String: Any], (info["prosemirror"] as? Int ?? (info["prosemirror"] as? Bool == true ? 1 : 0)) == 1 || (info["prosemirror"] as? Bool) == true else {
    NSLog("[smoke] FAIL: TipTap editor did not mount")
    exit(1)
}
guard (info["bridge"] as? Bool) == true || (info["bridge"] as? Int) == 1 else {
    NSLog("[smoke] FAIL: __mdEditorBridge hook missing")
    exit(1)
}

// Removals check: logo span and the "✨ Using AI" menu/panel must be gone.
func isTrue(_ v: Any?) -> Bool { (v as? Bool) == true || (v as? Int) == 1 }
if isTrue(info["logo"]) { NSLog("[smoke] FAIL: .toolbar-logo still present"); exit(1) }
if isTrue(info["aiPanel"]) { NSLog("[smoke] FAIL: #bm-ai panel still present"); exit(1) }
if isTrue(info["aiMenuEntry"]) { NSLog("[smoke] FAIL: turn-into-ai menu entry still present"); exit(1) }
if isTrue(info["usingAiText"]) { NSLog("[smoke] FAIL: 'Using AI' text still present in DOM"); exit(1) }
NSLog("[smoke] removals verified: no logo, no AI menu/panel")

// v2.0.3 feature checks (DOM presence):
// - toggle title is wrapped in the editable .toggle-title span
// - tables render through TableWithRail with the "+" append bands in the DOM
// - the old Turn-into flyout element is gone (full picker list replaces it)
if !isTrue(info["toggleTitle"]) { NSLog("[smoke] FAIL: .toggle-title span missing from toggle summary"); exit(1) }
if !isTrue(info["smokeToggle"]) { NSLog("[smoke] FAIL: fixture toggle 'Smoke toggle' not rendered as .toggle-title"); exit(1) }
if !isTrue(info["tableWrap"]) { NSLog("[smoke] FAIL: .mp-table wrapper missing"); exit(1) }
if !isTrue(info["tableAddRow"]) { NSLog("[smoke] FAIL: .mp-table-add-row band missing"); exit(1) }
if !isTrue(info["tableAddCol"]) { NSLog("[smoke] FAIL: .mp-table-add-col band missing"); exit(1) }
if !isTrue(info["flyoutGone"]) { NSLog("[smoke] FAIL: .block-picker-flyout still present"); exit(1) }
NSLog("[smoke] v2.0.3 verified: toggle title span, table add bands, no flyout")

// Round-trip: ask the webview for its authoritative markdown.
var roundTrip: Any?
semaphore = false
webView.evaluateJavaScript("window.__mdEditorBridge.getMarkdown()") { result, error in
    if let error { NSLog("[smoke] getMarkdown error: %@", error.localizedDescription) }
    roundTrip = result
    semaphore = true
}
let rtDeadline = Date().addingTimeInterval(10)
while !semaphore, Date() < rtDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
guard let serialized = roundTrip as? String else {
    NSLog("[smoke] FAIL: getMarkdown returned nothing")
    exit(1)
}
if !serialized.contains("<summary>Smoke toggle</summary>") {
    NSLog("[smoke] FAIL: serialized markdown lost the toggle summary")
    exit(1)
}
NSLog("[smoke] toggle summary round-trips through markdown serialize")
// v2.0.4 byte-stability: an unedited proportional-dash table must serialize
// back with the identical delimiter row (parse stamps colwidth at parse time,
// serialize re-derives the same dash counts).
if !serialized.contains("| ---- | ---------- |") {
    NSLog("[smoke] FAIL: proportional-dash delimiter did not round-trip; serialized table region missing '| ---- | ---------- |'")
    exit(1)
}
NSLog("[smoke] dash-count delimiter round-trips byte-identical when unedited")

// v2.0.4 — column widths in the parsed doc: uniform table attr-free,
// proportional table gets colwidth [80, 200] (4/10 dashes × 20px).
func evalJS(_ js: String, _ label: String) -> Any? {
    var out: Any?
    var done = false
    webView.evaluateJavaScript(js) { result, error in
        if let error { NSLog("[smoke] %@ error: %@", label, error.localizedDescription) }
        out = result
        done = true
    }
    let dl = Date().addingTimeInterval(10)
    while !done, Date() < dl { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    return out
}

let colwidths = evalJS("""
(() => {
  const ed = window.__mdEditorBridge.getEditor();
  if (!ed) return { err: 'no editor' };
  const out = {};
  ed.state.doc.descendants((node) => {
    if (node.type.name !== 'table') return true;
    const head = node.firstChild ? node.firstChild.textContent : '';
    const cw = [];
    if (node.firstChild) node.firstChild.forEach(c => cw.push(c.attrs.colwidth ? c.attrs.colwidth[0] : 0));
    if (head.includes('SmkA')) out.uniform = cw;
    if (head.includes('Wide')) out.weighted = cw;
    return true;
  });
  return out;
})()
""", "colwidth check") as? [String: Any]
NSLog("[smoke] colwidth after parse: %@", String(describing: colwidths))
func asInts(_ v: Any?) -> [Int] { (v as? [Any])?.map { ($0 as? Int) ?? Int(($0 as? Double) ?? -1) } ?? [] }
guard asInts(colwidths?["uniform"]) == [0, 0] else {
    NSLog("[smoke] FAIL: uniform-dash table gained colwidth attrs: %@", String(describing: colwidths?["uniform"]))
    exit(1)
}
guard asInts(colwidths?["weighted"]) == [80, 200] else {
    NSLog("[smoke] FAIL: proportional-dash table colwidth mismatch (want [80, 200]): %@", String(describing: colwidths?["weighted"]))
    exit(1)
}
NSLog("[smoke] parse: uniform table attr-free, proportional table restored [80, 200]")

// Simulate a resize: set colwidth [240, 480] on the proportional table via a
// PM transaction (what the columnResizing plugin does on drag end).
let resized = evalJS("""
(() => {
  const ed = window.__mdEditorBridge.getEditor();
  let tablePos = -1, tableNode = null;
  ed.state.doc.descendants((node, pos) => {
    if (node.type.name === 'table' && node.firstChild && node.firstChild.textContent.includes('Wide')) {
      tablePos = pos; tableNode = node; return false;
    }
    return true;
  });
  if (!tableNode) return 'not found';
  const widths = [240, 480];
  const tr = ed.state.tr;
  let rowPos = tablePos + 1;
  tableNode.forEach((row) => {
    let cellPos = rowPos + 1;
    row.forEach((cell, _o, ci) => {
      tr.setNodeMarkup(cellPos, null, { ...cell.attrs, colwidth: [widths[ci]] });
      cellPos += cell.nodeSize;
    });
    rowPos += row.nodeSize;
  });
  ed.view.dispatch(tr);
  return 'ok';
})()
""", "resize tx") as? String
guard resized == "ok" else { NSLog("[smoke] FAIL: resize transaction: %@", String(describing: resized)); exit(1) }

let afterResize = evalJS("window.__mdEditorBridge.getMarkdown()", "getMarkdown after resize") as? String ?? ""
// 240px → 12 dashes, 480px → 24 dashes (1 dash ≈ 20px).
let wantDelim = "| ------------ | ------------------------ |"
if !afterResize.contains(wantDelim) {
    NSLog("[smoke] FAIL: resized table did not serialize proportional dashes; want %@ in output", wantDelim)
    exit(1)
}
if afterResize.contains("| ------ | ------ |") {
    NSLog("[smoke] FAIL: uniform table unexpectedly kept non-baseline dashes")
    exit(1)
}
NSLog("[smoke] serialize: resized [240, 480] → 12/24 dashes; uniform table stays '---'")

// Feed the resized markdown back through the real parse path (host sync path).
_ = evalJS("window.__mdEditorBridge.applyContent(\(String(data: try! JSONEncoder().encode(afterResize), encoding: .utf8)!)); 'ok'", "applyContent")
Thread.sleep(forTimeInterval: 1.0)
let restored = evalJS("""
(() => {
  const ed = window.__mdEditorBridge.getEditor();
  const out = {};
  ed.state.doc.descendants((node) => {
    if (node.type.name !== 'table') return true;
    const head = node.firstChild ? node.firstChild.textContent : '';
    const cw = [];
    if (node.firstChild) node.firstChild.forEach(c => cw.push(c.attrs.colwidth ? c.attrs.colwidth[0] : 0));
    if (head.includes('SmkA')) out.uniform = cw;
    if (head.includes('Wide')) out.weighted = cw;
    return true;
  });
  return out;
})()
""", "restored colwidth") as? [String: Any]
guard asInts(restored?["weighted"]) == [240, 480] else {
    NSLog("[smoke] FAIL: colwidth not restored after re-parse (want [240, 480]): %@", String(describing: restored?["weighted"]))
    exit(1)
}
guard asInts(restored?["uniform"]) == [0, 0] else {
    NSLog("[smoke] FAIL: uniform table gained colwidth after re-parse: %@", String(describing: restored?["uniform"]))
    exit(1)
}
NSLog("[smoke] re-parse: widths [240, 480] restored; uniform table still attr-free")


func normalize(_ s: String) -> String {
    s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\\n+$", with: "", options: .regularExpression)
}
let identical = normalize(serialized) == normalize(markdown)
NSLog("[smoke] round-trip: input=%d chars, serialized=%d chars, identical=%@", markdown.count, serialized.count, identical ? "YES" : "NO")
if !identical {
    // Show the first differing region for diagnosis.
    let a = Array(normalize(markdown)), b = Array(normalize(serialized))
    var i = 0
    while i < min(a.count, b.count), a[i] == b[i] { i += 1 }
    let start = max(0, i - 40), endA = min(a.count, i + 40), endB = min(b.count, i + 40)
    NSLog("[smoke] first diff at char %d\n  original : %@\n  roundtrip: %@", i, String(a[start..<endA]).replacingOccurrences(of: "\n", with: "\\n"), String(b[start..<endB]).replacingOccurrences(of: "\n", with: "\\n"))
}

// Snapshot for visual verification.
semaphore = false
let snapConfig = WKSnapshotConfiguration()
snapConfig.rect = webView.bounds
webView.takeSnapshot(with: snapConfig) { image, error in
    if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/mdwebview_smoke.png"))
        NSLog("[smoke] snapshot saved to /tmp/mdwebview_smoke.png")
    } else if let error {
        NSLog("[smoke] snapshot error: %@", error.localizedDescription)
    }
    semaphore = true
}
let snapDeadline = Date().addingTimeInterval(15)
while !semaphore, Date() < snapDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}

NSLog("[smoke] console errors captured: %d", delegate.consoleErrors.count)
NSLog(identical ? "[smoke] PASS" : "[smoke] PASS WITH ROUND-TRIP DELTA")
exit(0)
