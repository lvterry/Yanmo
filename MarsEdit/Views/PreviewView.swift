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

    private struct RenderedBody {
        let raw: String
        let resolved: String
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // One handler per WebView, scoped to this document's directory.
        // `WKWebViewConfiguration.setURLSchemeHandler` cannot be replaced
        // after the WebView is created, so we hold a strong reference and
        // mutate `allowedRoot` when the document is saved (baseURL appears).
        let handler = LocalAssetSchemeHandler(allowedRoot: baseURL)
        context.coordinator.schemeHandler = handler
        config.setURLSchemeHandler(handler, forURLScheme: MarkdownRenderer.localAssetScheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        loadInitialShell(webView: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Keep the scheme handler's allowed root in sync with the document's
        // current location; SwiftUI re-runs updateNSView whenever baseURL
        // changes (e.g. after the user saves an untitled document).
        context.coordinator.schemeHandler?.allowedRoot = baseURL

        // Debounce preview updates
        context.coordinator.scheduleUpdate { [self] in
            self.applyUpdate(webView: webView, coordinator: context.coordinator)
        }
    }

    /// First render: load a stable HTML shell with theme CSS and an empty content div.
    /// Subsequent updates only swap the inner HTML, preserving scroll position natively.
    private func loadInitialShell(webView: WKWebView, coordinator: Coordinator) {
        let theme = settings.currentTheme
        let css = theme.loadCSS()
        let rendered = renderedBody()
        let title = MarkdownRenderer.extractTitle(from: document.text)
        let html = MarkdownRenderer.fullHTML(body: "<div id=\"content\">\(rendered.resolved)</div>", css: css, title: title)

        coordinator.lastThemeID = theme.id
        coordinator.lastBaseURL = baseURL
        coordinator.lastRawHTML = rendered.raw
        coordinator.lastBodyHTML = rendered.resolved
        coordinator.isShellLoaded = false
        coordinator.pendingBodyAfterLoad = nil
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Apply the latest content. If the shell needs to be rebuilt (theme/baseURL changed),
    /// do a full reload; otherwise inject the new body via JS.
    private func applyUpdate(webView: WKWebView, coordinator: Coordinator) {
        let theme = settings.currentTheme
        let needsFullReload = coordinator.lastThemeID != theme.id
            || coordinator.lastBaseURL != baseURL
        if needsFullReload {
            loadInitialShell(webView: webView, coordinator: coordinator)
            return
        }

        // Compare raw HTML first to skip the image-source resolver (which
        // regex-walks the full HTML) when the document hasn't changed.
        let raw = MarkdownRenderer.renderHTML(from: document.text)
        if raw == coordinator.lastRawHTML { return }
        coordinator.lastRawHTML = raw

        let body = MarkdownRenderer.resolveLocalImageSources(in: raw, relativeTo: baseURL)
        if body == coordinator.lastBodyHTML { return }
        coordinator.lastBodyHTML = body

        guard coordinator.isShellLoaded else {
            coordinator.pendingBodyAfterLoad = body
            return
        }

        injectBody(body, into: webView)
    }

    private func renderedBody() -> RenderedBody {
        let raw = MarkdownRenderer.renderHTML(from: document.text)
        let resolved = MarkdownRenderer.resolveLocalImageSources(in: raw, relativeTo: baseURL)
        return RenderedBody(raw: raw, resolved: resolved)
    }

    fileprivate func injectBody(_ body: String, into webView: WKWebView) {
        let literal = Self.jsStringLiteral(body)
        let script = """
        (function(){
          var c = document.getElementById('content');
          if (c) { c.innerHTML = \(literal); }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Encode an arbitrary string as a JS string literal (with surrounding quotes)
    /// using JSON, which handles all escaping (quotes, backslashes, newlines, lone surrogates).
    private static func jsStringLiteral(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
           let json = String(data: data, encoding: .utf8),
           json.count >= 2 {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PreviewView
        weak var webView: WKWebView?
        var schemeHandler: LocalAssetSchemeHandler?
        private var updateWorkItem: DispatchWorkItem?

        var isShellLoaded = false
        var lastThemeID: String?
        var lastBaseURL: URL?
        var lastRawHTML: String?
        var lastBodyHTML: String?
        var pendingBodyAfterLoad: String?

        private static let previewUpdateDebounce: TimeInterval = 0.3

        init(_ parent: PreviewView) {
            self.parent = parent
        }

        func scheduleUpdate(_ action: @escaping () -> Void) {
            updateWorkItem?.cancel()
            let work = DispatchWorkItem(block: action)
            updateWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewUpdateDebounce, execute: work)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isShellLoaded = true
            if let pending = pendingBodyAfterLoad {
                pendingBodyAfterLoad = nil
                parent.injectBody(pending, into: webView)
            }
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

    }
}
