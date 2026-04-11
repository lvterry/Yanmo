import Foundation

struct HTMLExporter {
    let theme: Theme

    /// Exports Markdown to a self-contained HTML file with inlined CSS.
    func export(markdown: String) -> String {
        let htmlBody = MarkdownRenderer.renderHTML(from: markdown)
        let css = theme.loadCSS()
        let title = extractTitle(from: markdown)
        return MarkdownRenderer.fullHTML(body: htmlBody, css: css, title: title)
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
