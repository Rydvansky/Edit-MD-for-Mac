import SwiftUI
import WebKit

/// Full-width rich (WYSIWYG) preview/editing surface backed by the bundled
/// md-editor-plus webview. All protocol handling lives in `WebEditorBridge`.
struct WebEditorPane: View {
    let bridge: WebEditorBridge
    let store: DocumentStore

    var body: some View {
        WebEditorViewRepresentable(bridge: bridge, store: store)
    }
}

private struct WebEditorViewRepresentable: NSViewRepresentable {
    let bridge: WebEditorBridge
    let store: DocumentStore

    func makeNSView(context: Context) -> WKWebView {
        bridge.makeWebView(store: store)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
