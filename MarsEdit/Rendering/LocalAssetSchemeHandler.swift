import Foundation
import UniformTypeIdentifiers
import WebKit

/// Resolves `marsedit-asset://local/...` URLs in the preview/PDF WebView to
/// local file contents. Each instance is scoped to a single document directory
/// — requests for files outside that directory are refused, so a maliciously
/// crafted markdown file can't use `..`-traversal to read arbitrary files
/// from the user's disk.
final class LocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    /// Files outside this directory are rejected. `nil` rejects every
    /// request, which is correct for untitled documents (they have no
    /// anchored directory and `MarkdownRenderer.resolveLocalImageSources`
    /// doesn't emit any `marsedit-asset://` URLs for them anyway).
    var allowedRoot: URL?

    init(allowedRoot: URL?) {
        self.allowedRoot = allowedRoot
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == MarkdownRenderer.localAssetScheme else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL))
            return
        }

        let fileURL = URL(fileURLWithPath: url.path)

        guard let root = allowedRoot,
              MarkdownRenderer.isPath(fileURL, containedIn: root) else {
            urlSchemeTask.didFailWithError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNoPermissionsToReadFile)
            )
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
