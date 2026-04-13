import AppKit
import WebKit

final class PDFExporter: NSObject, WKNavigationDelegate {
    let theme: Theme
    let pageSize: DefaultPageSize

    private var webView: WKWebView?
    private var offscreenWindow: NSWindow?
    private var outputURL: URL?
    private var retainedSelf: PDFExporter?

    init(theme: Theme, pageSize: DefaultPageSize) {
        self.theme = theme
        self.pageSize = pageSize
        super.init()
    }

    /// Page dimensions in points.
    private var pageDimensions: (width: CGFloat, height: CGFloat) {
        switch pageSize {
        case .a4:     return (595.28, 841.89)
        case .letter: return (612, 792)
        }
    }

    private let marginPoints: CGFloat = 54 // ~0.75 inch margins

    /// The content width that text should flow within.
    private var contentWidth: CGFloat {
        pageDimensions.width - marginPoints * 2
    }

    func exportPDF(html: String, baseURL: URL?, to url: URL) {
        retainedSelf = self
        outputURL = url

        // Inject print-specific CSS so content fits within the page margins
        // and preserves the full theme appearance (colors, backgrounds).
        let printCSS = """
        /* Force WebKit to preserve all colors and backgrounds in print output
           instead of stripping them for "printer-friendly" output. */
        * {
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
            color-adjust: exact !important;
        }
        body {
            max-width: none !important;
            width: auto !important;
            margin: 0 !important;
            padding: 0 !important;
            box-sizing: border-box !important;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        pre {
            white-space: pre-wrap !important;
            word-wrap: break-word !important;
        }
        table {
            display: table !important;
            table-layout: fixed !important;
            word-break: break-word;
        }
        th, td {
            -webkit-print-color-adjust: exact !important;
        }
        img {
            max-width: 100% !important;
            height: auto !important;
        }
        h1, h2, h3, h4, h5, h6 {
            page-break-after: avoid;
        }
        pre, blockquote, table, figure {
            page-break-inside: avoid;
        }
        """

        let augmentedHTML = html.replacingOccurrences(
            of: "</style>",
            with: "\n\(printCSS)\n</style>"
        )

        let config = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: contentWidth, height: pageDimensions.height),
            configuration: config
        )
        webView.navigationDelegate = self
        self.webView = webView

        // NSPrintOperation requires the view to live inside a window.
        // Create an offscreen window to host the WKWebView.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: pageDimensions.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        // Position offscreen so it's never visible
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderBack(nil)
        self.offscreenWindow = window

        webView.loadHTMLString(augmentedHTML, baseURL: baseURL)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = outputURL else {
            finish()
            return
        }
        printToPDF(from: webView, to: url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError("Failed to load content for PDF: \(error.localizedDescription)")
        finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError("Failed to load content for PDF: \(error.localizedDescription)")
        finish()
    }

    // MARK: - Print-to-PDF

    private func printToPDF(from webView: WKWebView, to url: URL) {
        let printInfo = NSPrintInfo()

        // Page size
        let (pageW, pageH) = pageDimensions
        printInfo.paperSize = NSSize(width: pageW, height: pageH)

        // Margins
        printInfo.topMargin = marginPoints
        printInfo.bottomMargin = marginPoints
        printInfo.leftMargin = marginPoints
        printInfo.rightMargin = marginPoints

        // Output to file, not printer
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        // Pagination
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.scalingFactor = 1.0

        let printOp = webView.printOperation(with: printInfo)
        printOp.showsPrintPanel = false
        printOp.showsProgressPanel = false

        // runModal requires a window — use the offscreen window hosting the WKWebView.
        guard let window = offscreenWindow else {
            showError("PDF export failed: no window available.")
            finish()
            return
        }

        printOp.runModal(for: window, delegate: self,
                         didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                         contextInfo: nil)
    }

    @objc private func printOperationDidRun(
        _ printOperation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        // This callback can fire on a background thread. Dispatch all
        // AppKit work and cleanup to the main thread.
        DispatchQueue.main.async { [self] in
            if !success {
                showError("PDF export failed. The print operation did not complete.")
            }
            finish()
        }
    }

    private func finish() {
        assert(Thread.isMainThread, "finish() must be called on the main thread")
        webView?.navigationDelegate = nil
        offscreenWindow?.orderOut(nil)
        offscreenWindow?.contentView = nil
        offscreenWindow = nil
        webView = nil
        outputURL = nil
        retainedSelf = nil
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Export Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
