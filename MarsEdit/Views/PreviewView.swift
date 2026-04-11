import SwiftUI
import WebKit

/// Wraps WKWebView to render the Markdown preview as HTML.
struct PreviewView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    @EnvironmentObject var settings: AppSettings

    let baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        loadPreview(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Debounce preview updates
        context.coordinator.scheduleUpdate {
            loadPreview(webView: webView)
        }
    }

    private func loadPreview(webView: WKWebView) {
        let theme = settings.currentTheme
        let css = theme.loadCSS()
        let htmlBody = MarkdownRenderer.renderHTML(from: document.text)
        let title = extractTitle(from: document.text)
        let fullHTML = MarkdownRenderer.fullHTML(body: htmlBody, css: css, title: title)

        // Preserve scroll position
        webView.evaluateJavaScript("window.scrollY") { result, _ in
            let scrollY = result as? CGFloat ?? 0
            webView.loadHTMLString(fullHTML, baseURL: self.baseURL)
            // Restore scroll after load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))")
            }
        }
    }

    private func extractTitle(from markdown: String) -> String {
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return "Untitled"
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PreviewView
        weak var webView: WKWebView?
        private var updateWorkItem: DispatchWorkItem?

        init(_ parent: PreviewView) {
            self.parent = parent
        }

        func scheduleUpdate(_ action: @escaping () -> Void) {
            updateWorkItem?.cancel()
            let work = DispatchWorkItem(block: action)
            updateWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow loading our HTML content, but open external links in browser
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// Scrolls the preview to match a percentage offset from the editor.
        func syncScroll(to percentage: CGFloat) {
            guard let webView = webView else { return }
            webView.evaluateJavaScript("""
                var docHeight = document.documentElement.scrollHeight - window.innerHeight;
                window.scrollTo(0, docHeight * \(percentage));
            """)
        }
    }
}
