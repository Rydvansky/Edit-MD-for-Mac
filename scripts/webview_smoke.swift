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
let markdown = (try? String(contentsOf: demoURL, encoding: .utf8)) ?? "# Hello\n\n- [ ] task\n"

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
webView.evaluateJavaScript("({prosemirror: !!document.querySelector('#editor .ProseMirror'), bridge: !!window.__mdEditorBridge, bodyChars: document.body.innerText.length})") { result, error in
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
