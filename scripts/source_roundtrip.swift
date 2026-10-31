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
    let dl = Date().addingTimeInterval(60)
    while !done, Date() < dl { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    return out
}


func js(_ code: String) -> Any? { evalJS(code, "toggle") }

let fixtures = try ["markdown_demo.md", "markdown_demo test.md"].map { try String(contentsOfFile: root + "/" + $0, encoding: .utf8) }
let quick=CommandLine.arguments.contains("--quick")
let input = String(decoding: try JSONEncoder().encode(fixtures), as: UTF8.self)
let result = js(#"""
(() => {
 const fixtures=\#(input), md=fixtures[0];
 window.__nativeEditor.receive({protocolVersion:1,channelID:'standalone',documentID:'source-check',requestID:'load',type:'load',revision:0,markdown:md,context:{documentPath:'fixture.md'},defaults:{theme:'light'}});
 const api=window.__mdEditorBridge, ed=api.getEditor();
 const errors=[],reports=[];
 const assert=(ok,message)=>{if(!ok)throw Error(message)};
 const reload=md=>{api.applyContent(md)};
 for (const fixture of fixtures) {
   reload(fixture);
   assert(api.getMarkdown()===fixture,'Untouched source differs');
   ed.commands.insertContentAt({from:1,to:ed.state.doc.firstChild.nodeSize-1},'Only heading edited');
   const expected=fixture.replace(/^([^\r\n]*?)([ \t]*)(?=\r?\n)/,'# Only heading edited$2');
   assert(api.getMarkdown()===expected,'H1 edit rewrites unrelated source');
   for(let i=0;i<5;i++) {
     document.querySelector('[data-view=source]').click();
     assert(api.getMarkdown()===expected,'Code changes source');
     document.querySelector('[data-view=preview]').click();
     assert(api.getMarkdown()===expected,'Preview changes source');
     reload(api.getMarkdown());
     assert(api.getMarkdown()===expected,'Reload changes source');
   }
   reports.push('Exact H1 edit and five mode/reload cycles');
 }
 // Exercise every editable block in the full demo, rather than just the H1.
 reload(md);
 const count=ed.state.doc.childCount;
 let checked=0;
 for(let index=0;index<count && !\#(quick);index++) {
   reload(md);
   const node=ed.state.doc.child(index), range=ed.sourceDocument.ranges[index];
   let at=0,text=null;node.descendants((child,pos)=>{if(!text&&child.isText){text=child;at=pos+1}return !text});
   if(!text)continue;
   if(!range){errors.push('Unmapped '+index+' '+node.type.name);continue}
   let pos=0;for(let j=0;j<index;j++)pos+=ed.state.doc.child(j).nodeSize;
   // Child descendant positions are relative to the parent content.
   const insertion=pos+at;
   ed.commands.insertContentAt(insertion,'EDIT_TOKEN ');
   try {
     const output=api.getMarkdown();
     assert(output.startsWith(md.slice(0,range.start)),'Changed preceding source for '+node.type.name);
     assert(output.endsWith(md.slice(range.end)),'Changed following source for '+node.type.name);
     const signature=window.SourceDocument.key(ed.state.doc);
     reload(output);
     assert(window.SourceDocument.key(ed.state.doc)===signature,'Lost structure for '+node.type.name);
     checked++;
   } catch(e){errors.push(index+' '+node.type.name+': '+e.message)}
 }

 for(const action of ['insert','delete','move']) {
   reload('# One\n\nParagraph.\n\n# Two\n\nAnother.\n');
   if(action==='insert')ed.commands.insertContentAt(ed.state.doc.content.size,{type:'paragraph',content:[{type:'text',text:'Added block'}]});
   if(action==='delete')ed.view.dispatch(ed.state.tr.delete(0,ed.state.doc.firstChild.nodeSize));
   if(action==='move') {const children=[];ed.state.doc.forEach(n=>children.push(n));const tr=ed.state.tr.replaceWith(0,ed.state.doc.content.size,[children[2],children[3],children[0],children[1]]);ed.view.dispatch(tr)}
   const expected=window.SourceDocument.key(ed.state.doc),output=api.getMarkdown();reload(output);
   assert(window.SourceDocument.key(ed.state.doc)===expected,'Structural source edit '+action);
 }
 reload('*same*\n\n_same_\n\nEnd.\n');
 ed.view.dispatch(ed.state.tr.delete(0,ed.state.doc.firstChild.nodeSize));
 assert(api.getMarkdown().includes('_same_'),'Deleted wrong repeated block spelling');

 // Formatting an edited paragraph must retain HTML/link metadata that the
 // editor itself cannot represent as a mark or attribute.
 for(const fixture of ['<sub>Subscript</sub> plain text.\n','[Title link](https://example.com "Keep tooltip") plain text.\n']) {
   reload(fixture);
   const text=ed.state.doc.firstChild.textContent,at=text.indexOf('plain');
   ed.chain().setTextSelection({from:1+at,to:1+at+5}).toggleBold().run();
   const output=api.getMarkdown();
   assert(output.includes('**plain**'),'Formatting was not applied');
   if(fixture.includes('<sub>'))assert(output.includes('<sub>Subscript</sub>'),'Lost unsupported HTML in an edited paragraph');
   if(fixture.includes('tooltip'))assert(output.includes('Keep tooltip'),'Lost link title in an edited paragraph');
 }

 for(const prefix of ['---\r\ntitle: Current metadata\r\n---\r\n','+++\ntitle = "Current metadata"\n+++\n','\ufeff---\ntitle: BOM metadata\n---\n']) {
   const fixture=prefix+'# One\n\nBody.\n';reload(fixture);
   ed.commands.insertContentAt(1,'X ');
   assert(api.getMarkdown()===prefix+'# X One\n\nBody.\n','Frontmatter changed while editing H1');
 }
 // Line endings, BOM and reference/comment gaps.



 for(const fixture of ['# One\n\nText.\n', '# One\r\n\r\nText.\r\n', '\ufeff# One\n\nText.\n', '# One\n\n[ref]: https://example.com\n']) {
   reload(fixture);ed.commands.insertContentAt(1,'X ');
   if(!ed.sourceDocument.ranges[0])throw Error('Unmapped fixture '+JSON.stringify(fixture)+' '+JSON.stringify(ed.state.doc.toJSON())+' '+JSON.stringify(ed.sourceDocument.keys));
   assert(api.getMarkdown()===fixture.replace('# One','# X One'),'Line ending/BOM preservation');
 }
 reload('> First\n>\n>> Second\n>>\n>>> Third\n');
 if(!ed.sourceDocument.ranges[0])throw Error('Unmapped quote '+JSON.stringify(ed.state.doc.toJSON())+' source '+ed.sourceDocument.source);
 let quotePos=-1;ed.state.doc.descendants((n,pos)=>{if(n.isText&&n.text==='Third')quotePos=pos});
 ed.commands.insertContentAt(quotePos,'Edited ');
 const quote=api.getMarkdown();
 for(let i=0;i<5;i++){reload(quote);assert(api.getMarkdown()===quote,'Nested quote depth grows')}
 assert(quote.includes('>>> Edited Third'),'Nested quote source spelling changed');
 assert(errors.length===0,errors.join('\n'));
 return {pass:true,checked,reports};
})()
"""#) as? [String:Any]
guard result?["pass"] as? Bool == true else { fputs("FAIL: source fidelity regression\n",stderr);exit(1) }
print("PASS: exact H1-only changes on both demo files, five Preview/Code/reopen cycles, every editable demo block, nested quotes, BOM and CRLF:",result?["checked"] ?? 0)
