import Foundation

struct HTMLExporter {
    let theme: Theme

    func export(markdown: String) -> String {
        let htmlBody = MarkdownRenderer.renderHTML(from: markdown)
        let css = theme.loadCSS()
        let title = extractTitle(from: markdown)
        return MarkdownRenderer.fullHTML(body: htmlBody, css: css, title: title)
    }

    func exportForBrowser(markdown: String, documentDirectory: URL?) -> String {
        let htmlBody = MarkdownRenderer.renderHTML(from: markdown)
        let resolvedBody = MarkdownRenderer.resolveLocalImageSources(
            in: htmlBody,
            relativeTo: documentDirectory,
            useAssetScheme: false
        )
        let css = theme.loadCSS()
        let title = extractTitle(from: markdown)
        return MarkdownRenderer.fullHTML(
            body: resolvedBody,
            css: css,
            title: title,
            cspImageSources: MarkdownRenderer.exportCSPPolicy
        )
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
}
