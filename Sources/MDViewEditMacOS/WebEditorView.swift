import SwiftUI
import WebKit

/// Full-width rich (WYSIWYG) preview/editing surface backed by the bundled
/// md-editor-plus webview. All protocol handling lives in `WebEditorBridge`.
struct WebEditorPane: View {
    let bridge: WebEditorBridge

    var body: some View {
        WebEditorViewRepresentable(bridge: bridge)
    }
}

private struct WebEditorViewRepresentable: NSViewRepresentable {
    let bridge: WebEditorBridge

    func makeNSView(context: Context) -> WKWebView {
        bridge.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
