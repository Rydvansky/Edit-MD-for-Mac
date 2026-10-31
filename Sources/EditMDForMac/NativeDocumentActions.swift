import AppKit
import UniformTypeIdentifiers
import WebKit

/// Native system actions; the transport never reads or writes files itself.
@MainActor
final class NativeDocumentActions {
    private weak var store: DocumentStore?
    init(store: DocumentStore) { self.store = store }

    func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "copyContent":
            Task {
                do { if let snapshot = try await store?.captureEditorSnapshot() { copyToPasteboard(snapshot.markdown) } }
                catch { store?.showError("Could not copy the latest editor content.", recovery: error.localizedDescription) }
            }
        case "copyFilePath": if let path = store?.fileURL?.path { copyToPasteboard(path) }
        case "openInFinder": if let url = store?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case "duplicate":
            Task {
                do { if let snapshot = try await store?.captureEditorSnapshot() { duplicateCurrentFile(markdown: snapshot.markdown) } }
                catch { store?.showError("Could not duplicate the latest editor content.", recovery: error.localizedDescription) }
            }
        case "exportHtml": if let html = message["html"] as? String { exportHTML(html) }
        case "exportPdf": if let html = message["html"] as? String { exportPDF(html, filename: message["filename"] as? String) }
        case "openFromClipboard": openFromClipboardPath()
        case "browseMarkdown": if let store { WindowManager.shared.openPanel(from: store) }
        case "openExternal":
            if let string = message["url"] as? String, let url = URL(string: string),
               ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        default: NSLog("[NativeDocumentActions] unsupported action: %@", message["type"] as? String ?? "unknown")
        }
    }

    func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func duplicateCurrentFile(markdown: String) {
        guard let store, let url = store.fileURL else { return }
        let copyName = url.deletingPathExtension().lastPathComponent + " copy"
        let copyURL = url.deletingLastPathComponent()
            .appendingPathComponent(copyName)
            .appendingPathExtension(url.pathExtension)
        do {
            try markdown.write(to: copyURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([copyURL])
        } catch {
            store.showError("Could not duplicate the file.", recovery: error.localizedDescription)
        }
    }

    func exportHTML(_ html: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (store?.fileURL?.deletingPathExtension().lastPathComponent ?? "document") + ".html"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            store?.showError("Could not export HTML.", recovery: error.localizedDescription)
        }
    }

    func exportPDF(_ html: String, filename: String?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let base = (filename as NSString?)?.deletingPathExtension
            ?? store?.fileURL?.deletingPathExtension().lastPathComponent
            ?? "document"
        panel.nameFieldStringValue = base + ".pdf"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Render the standalone export HTML in an offscreen webview and print to PDF.
        let renderer = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200))
        let delegate = PDFRenderDelegate { [weak self] in
            renderer.createPDF { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url)
                        } catch {
                            self?.store?.showError("Could not write the PDF.", recovery: error.localizedDescription)
                        }
                    case .failure(let error):
                        self?.store?.showError("Could not render the PDF.", recovery: error.localizedDescription)
                    }
                }
            }
        }
        // Retain renderer + delegate until the PDF is written.
        pdfRetained.append((renderer, delegate))
        renderer.navigationDelegate = delegate
        renderer.loadHTMLString(html, baseURL: store?.documentBaseURL)
    }

    private var pdfRetained: [(WKWebView, PDFRenderDelegate)] = []

    func openFromClipboardPath() {
        guard
            let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty
        else { return }
        let url = URL(fileURLWithPath: string)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        WindowManager.shared.open(urls: [url], useActiveEmptyWindow: true, preferredStore: store)
    }
}


private final class PDFRenderDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give the page a beat for fonts/layout before rasterizing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [onFinish] in
            onFinish()
        }
    }
}
