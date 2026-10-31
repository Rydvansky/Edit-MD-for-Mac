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
            if type == "ready" { NSLog("[source] editor ready") }
            if type == "ready" { ready = true }
            if type == "inputProgress" { NSLog("[input] %@", String(describing:body["detail"] ?? "")) }
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
    let dl = Date().addingTimeInterval(300)
    while !done, Date() < dl { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    return out
}


func js(_ code: String) -> Any? { evalJS(code, "toggle") }

let fixtures = try ["markdown_demo.md", "markdown_demo test.md"].map { try String(contentsOfFile: root + "/" + $0, encoding: .utf8) }
let quick=CommandLine.arguments.contains("--quick")
let input = String(decoding: try JSONEncoder().encode(fixtures), as: UTF8.self)
let result = js(#"""
(() => {

 const fixtures=\#(input),api=window.__mdEditorBridge;
 window.__nativeEditor.receive({protocolVersion:1,channelID:'standalone',documentID:'input-check',requestID:'load',type:'load',revision:0,markdown:fixtures[0],context:{documentPath:'fixture.md'},defaults:{theme:'light'}});
 const ed=api.getEditor(),failures=[],types=new Set();let checked=0;
 const short=[
  'Plain text.\n',
  '<details>\n<summary>Toggle</summary>\n\nBody.\n\n<details>\n<summary>Nested</summary>\n\nNested text.\n\n</details>\n\n</details>\n',
  '- One\n- Two\n','1. One\n2. Two\n','- [ ] Task\n- [x] Done\n',
  '> A quote.\n','| Head |\n| --- |\n| Cell |\n','```swift\nlet value = 1\n```\n',
  '# Heading\n\n**Bold** and *italic* and `code`.\n',
  '> [!NOTE]\n> Callout text.\n',
  '### Code example\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n',
  '```mermaid\ngraph TD\n  A --> B\n```\n'
 ];
 const type=text=>()=>ed.view.dispatch(ed.state.tr.insertText(text));
 const actions={text:type('Input'),space:type(' '),doubleSpace:type('  '),enter:()=>ed.commands.keyboardShortcut('Enter'),softBreak:()=>ed.commands.setHardBreak(),backspace:()=>ed.commands.keyboardShortcut('Backspace')};
 for(const [f,source] of [...short,...(\#(quick)?[]:fixtures)].entries()){
   api.applyContent(source);
   const original=ed.state.doc,positions=[],validated=new Set();
   original.descendants((n,pos)=>{if(n.isTextblock){types.add(n.type.name);positions.push({pos:pos+1,kind:n.type.name,edge:'start'});positions.push({pos:pos+n.nodeSize-1,kind:n.type.name,edge:'end'})}});
   // Fixture restore should not build thousands of undo mappings. Undo/Redo
   // is covered separately by the toggle and native bridge checks.
   ed.unregisterPlugin('history$');
   const reset=()=>ed.view.dispatch(ed.state.tr.replaceWith(0,ed.state.doc.content.size,original.content).setMeta('addToHistory',false));
   for(const {pos,kind,edge} of positions)for(const [name,act] of Object.entries(actions)){
     reset();ed.commands.setTextSelection(pos);act();
     const expected=window.SourceDocument.key(ed.state.doc);
     try {
       const out=api.getMarkdown(),validationKey=kind+':'+edge+':'+name;
       if(f<short.length||!validated.has(validationKey)){
         const parsed=ed.sourceDocument.parse(out,ed.sourceDocument.env);
         if(window.SourceDocument.key(parsed)!==expected)throw Error('Reload changed the model');
         validated.add(validationKey);
       }
       if(window.SourceDocument.key(ed.state.doc)!==expected)throw Error('Save mutated the editor');
       checked++;
     } catch(error){failures.push({f,pos,kind,edge,name,message:error.message})}
   }
   window.webkit.messageHandlers.mdEditor.postMessage({type:'inputProgress',detail:'fixture '+f+', '+checked+' checks, '+failures.length+' failures'});
   // Exercise inline formats through actual text transactions, not HTML input
   // parsing, which used to trim boundary spaces and hide the failing cases.
   for(const format of ['toggleBold','toggleItalic','toggleUnderline','toggleStrike','toggleCode','toggleHighlight','setHighlight','setColor','setLink']){
     reset();ed.commands.setTextSelection(positions[0].pos);ed.commands[format](format==='setColor'?'#e55757':format==='setLink'?{href:'https://example.com/page'}:format==='setHighlight'?{color:'#ffd700aa'}:undefined);type(' styled ')();
     try {const out=api.getMarkdown();if(!ed.sourceDocument.same(out,Array.from({length:ed.state.doc.childCount},(_,i)=>ed.state.doc.child(i))))throw Error('Formatting changed on reload');checked++}
     catch(error){failures.push({f,format,message:error.message})}
   }
 }

 const board='<!-- board:start id="input-check" name="Board" columns="Todo|Done" column-colors="gray|green" field-types="Title=text,Status=status,id=text" hidden-fields="id" -->\n\n| Title | Status | id |\n| --- | --- | --- |\n| Card | Todo | C1 |\n\n<!-- board:end -->\n';
 const attributes=[
   ['image','![Alt](asset.png "Keep title")\n',{width:240,alt:'Changed image'}],
   ['toggle',short[1],{summary:'Changed <title> & text'}],
   ['callout',short[9],{type:'warning',emoji:'⚠️'}],
   ['orderedList',short[3],{start:7}],
   ['taskItem',short[4],{checked:true}],
   ['codeBlock',short[7],{language:'javascript'}],
   ['board',board,{source:board.trimEnd().replace('Card','Changed card')}]
 ];
 for(const [kind,source,attrs] of attributes){
   api.applyContent(source);let at=-1;
   ed.state.doc.descendants((n,p)=>{if(at<0&&n.type.name===kind)at=p});
   if(at<0){failures.push({kind,message:'Missing attribute fixture'});continue}
   ed.view.dispatch(ed.state.tr.setNodeMarkup(at,undefined,{...ed.state.doc.nodeAt(at).attrs,...attrs}));
   try {const out=api.getMarkdown();if(!ed.sourceDocument.same(out,Array.from({length:ed.state.doc.childCount},(_,i)=>ed.state.doc.child(i))))throw Error('Attribute edit changed on reload');checked++}
   catch(error){failures.push({kind,message:error.message})}
 }
 api.applyContent('Text.\n');
 ed.view.dispatch(ed.state.tr.insert(ed.state.doc.content.size,ed.schema.nodes.horizontalRule.create()));
 try{const out=api.getMarkdown();if(!ed.sourceDocument.same(out,Array.from({length:ed.state.doc.childCount},(_,i)=>ed.state.doc.child(i))))throw Error('Divider changed on reload');checked++}catch(error){failures.push({kind:'horizontalRule',message:error.message})}
 return {pass:failures.length===0,checked,types:[...types],failures};

})()
"""#) as? [String:Any]
if let result {try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"/tmp/md-input-regression.json"))}
guard result?["pass"] as? Bool == true else { fputs("FAIL: input regression; details in /tmp/md-input-regression.json\n",stderr);exit(1) }
print("PASS: rich input, spaces, Enter, hard breaks, deletion and formatting across all demo text blocks:",result?["checked"] ?? 0)
