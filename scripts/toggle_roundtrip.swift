import Foundation
import WebKit
let root = FileManager.default.currentDirectoryPath
let indexURL = URL(fileURLWithPath: root).appendingPathComponent("Resources/Webview/index.html")
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
        NSLog("[smoke] navigation failed: %@", String(describing: (error as NSError).userInfo))
        navDone = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[smoke] provisional navigation failed: %@", String(describing: (error as NSError).userInfo))
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
func evalJS(_ js: String, _ label: String) -> Any? {
    var out: Any?
    var done = false
    webView.evaluateJavaScript(js) { result, error in
        if let error { NSLog("[smoke] %@ error: %@", label, String(describing: (error as NSError).userInfo)) }
        out = result
        done = true
    }
    let dl = Date().addingTimeInterval(10)
    while !done, Date() < dl { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    return out
}


func js(_ code: String) -> Any? { evalJS(code, "toggle") }
let initial: [String: Any] = ["protocolVersion":1,"channelID":"standalone","documentID":"toggle-check","requestID":"load","type":"load","revision":0,"markdown":"# Toggle regression\n","context":["documentPath":"test.md"],"defaults":["theme":"light"]]
let json = String(decoding: try! JSONSerialization.data(withJSONObject: initial), as: UTF8.self)
_ = js("window.__nativeEditor.receive(\(json))")
let result = js(#"""
(() => {
 const ed = window.__mdEditorBridge.getEditor();
 const t = text => ({type:'text',text});
 const p = text => ({type:'paragraph',content:[t(text)]});
 const toggle = (summary,content) => ({type:'toggle',attrs:{summary},content});
 const content = [
   p('sdfsdfasdlk dsldkflaskdjf sdfsadflk sdfkasdfasdf sdfasdfasdfasdf##sdfsdf'),
   {type:'heading',attrs:{level:2},content:[t('Heading token')]},
   {type:'paragraph',content:[{...t('Bold token'),marks:[{type:'bold'}]},t(' '),{...t('Italic token'),marks:[{type:'italic'}]},t(' '),{...t('Code token'),marks:[{type:'code'}]},{...t('Link token'),marks:[{type:'link',attrs:{href:'https://example.com/toggle'}}]}]},
   {type:'bulletList',content:[{type:'listItem',content:[p('List token'),{type:'orderedList',content:[{type:'listItem',content:[p('Nested list token')]}]}]}]},
   {type:'taskList',content:[{type:'taskItem',attrs:{checked:true},content:[p('Task token')]}]},
   {type:'blockquote',content:[p('Quote token')]},
   {type:'codeBlock',attrs:{language:'swift'},content:[t('let codeToken = "<details>literal</details>"')]},
   {type:'table',content:[{type:'tableRow',content:[{type:'tableHeader',content:[p('Column token')]}]},{type:'tableRow',content:[{type:'tableCell',content:[p('Cell token')]}]}]},
   {type:'image',attrs:{src:'https://example.com/image.png',alt:'Image token'}},
   {type:'horizontalRule'},
   toggle('Nested <title> & token',[p('Nested toggle token')])
 ];
 ed.commands.setContent({type:'doc',content:[toggle('test toggle',content)]});
 const signature = () => { const nodes=[],marks=[]; ed.state.doc.descendants(n=>{nodes.push([n.type.name,n.attrs.summary??null,n.attrs.checked??null,n.attrs.level??null,n.attrs.language??null,n.attrs.src??null]);for(const m of n.marks)marks.push([m.type.name,m.attrs.href??null])});return JSON.stringify({nodes,marks,text:ed.state.doc.textContent}); };
 const expected = signature();
 let serialized;
 for (let pass=0;pass<3;pass++) {
   serialized = window.__mdEditorBridge.getMarkdown();
   if (!serialized.includes('https://example.com/image.png')) throw Error('Lost image');
   document.querySelector('[data-view=source]').click();
   document.querySelector('[data-view=preview]').click();
   if (signature()!==expected) throw Error('Mode switch lost nodes/marks, pass '+pass+'\n'+serialized+'\n'+signature());
   window.__mdEditorBridge.applyContent(serialized);
   if (signature()!==expected) throw Error('Reopen lost nodes/marks, pass '+pass+'\n'+serialized+'\n'+signature());
 }
 return {pass:true,markdown:serialized};
})()
"""#) as? [String: Any]
guard result?["pass"] as? Bool == true else { fputs("FAIL: toggle regression\n", stderr); exit(1) }
print("PASS: toggle paragraphs, headings, marks, links, nested lists, tasks, quotes, fenced code, table, image, divider, nested toggles; 3 mode switches and reparses")
exit(0)
