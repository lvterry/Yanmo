import Foundation
import Markdown

struct MarkdownRenderer {
    static let localAssetScheme = "marsedit-asset"

    /// Converts Markdown source text to an HTML string using swift-markdown (GFM).
    static func renderHTML(from markdown: String) -> String {
        let frontMatterHTML: String
        let body: String
        if let fm = FrontMatter.parse(markdown) {
            frontMatterHTML = renderFrontMatterTable(fm)
            body = String(markdown[fm.range.upperBound...])
        } else {
            frontMatterHTML = ""
            body = markdown
        }
        let document = Document(parsing: body, options: [.parseBlockDirectives])
        var visitor = HTMLVisitor()
        let bodyHTML = visitor.visit(document)
        if frontMatterHTML.isEmpty { return bodyHTML }
        return frontMatterHTML + "\n" + bodyHTML
    }

    private static func renderFrontMatterTable(_ fm: FrontMatter) -> String {
        guard !fm.entries.isEmpty else { return "" }
        var rows = ""
        for entry in fm.entries {
            if let key = entry.key {
                rows += "<tr><th>\(escapeHTML(key))</th><td>\(escapeHTML(entry.value))</td></tr>\n"
            } else {
                rows += "<tr><td colspan=\"2\"><code>\(escapeHTML(entry.value))</code></td></tr>\n"
            }
        }
        return "<table class=\"front-matter\">\n<tbody>\n\(rows)</tbody>\n</table>"
    }

    /// Wraps rendered HTML body with a full HTML document including theme CSS.
    static let assetCSPPolicy = "https: http: data: marsedit-asset:"
    static let exportCSPPolicy = "https: http: data: file:"

    static func fullHTML(body: String, css: String, title: String = "", cspImageSources: String = assetCSPPolicy) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src \(cspImageSources); font-src *;">
        <title>\(escapeHTML(title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Extracts the first H1 heading from markdown text, or returns "Untitled".
    /// A `title:` entry in front matter takes precedence.
    static func extractTitle(from markdown: String) -> String {
        if let fm = FrontMatter.parse(markdown),
           let title = fm.value(for: "title"), !title.isEmpty {
            return title
        }
        let body = FrontMatter.stripping(markdown)
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return "Untitled"
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Sanitizes a URL for safe insertion into link attributes.
    /// Blocks schemes that can execute script or embed active content.
    static func sanitizeURL(_ url: String) -> String {
        sanitizeLinkURL(url)
    }

    static func sanitizeLinkURL(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")

        let blocked = ["javascript:", "vbscript:", "data:"]
        for scheme in blocked {
            if lower.hasPrefix(scheme) { return "" }
        }

        return escapeHTML(trimmed)
    }

    static func sanitizeImageURL(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let compactLower = trimmed.lowercased()
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")

        if compactLower.hasPrefix("javascript:") || compactLower.hasPrefix("vbscript:") {
            return ""
        }

        if compactLower.hasPrefix("data:") {
            let allowedPrefixes = [
                "data:image/png;base64,",
                "data:image/jpeg;base64,",
                "data:image/jpg;base64,",
                "data:image/gif;base64,",
                "data:image/webp;base64,",
                "data:image/bmp;base64,",
                "data:image/tiff;base64,",
                "data:image/heic;base64,",
                "data:image/heif;base64,",
            ]
            guard allowedPrefixes.contains(where: { compactLower.hasPrefix($0) }) else { return "" }
        }

        return escapeHTML(trimmed)
    }

    private static let imageSourceRegex = try! NSRegularExpression(
        pattern: #"(<img\b[^>]*\bsrc=")([^"]+)(")"#,
        options: [.caseInsensitive]
    )

    static func resolveLocalImageSources(in html: String, relativeTo baseURL: URL?, useAssetScheme: Bool = true) -> String {
        guard let baseURL else { return html }

        let nsHTML = html as NSString
        let matches = imageSourceRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
        guard !matches.isEmpty else { return html }

        var resolvedHTML = html
        for match in matches.reversed() {
            guard match.numberOfRanges == 4 else { continue }
            let srcRange = match.range(at: 2)
            let escapedSource = nsHTML.substring(with: srcRange)
            let source = escapedSource
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")

            guard shouldResolveAsLocalPath(source),
                  let absoluteURL = resolvedLocalFileURL(for: source, relativeTo: baseURL) else {
                continue
            }

            let resolved: URL = useAssetScheme ? localAssetURL(for: absoluteURL) : absoluteURL
            let replacement = escapeHTML(resolved.absoluteString)
            let stringRange = Range(srcRange, in: resolvedHTML)!
            resolvedHTML.replaceSubrange(stringRange, with: replacement)
        }

        return resolvedHTML
    }

    private static func shouldResolveAsLocalPath(_ source: String) -> Bool {
        if source.isEmpty || source.hasPrefix("#") || source.hasPrefix("/") {
            return false
        }

        if let url = URL(string: source), let scheme = url.scheme?.lowercased(), !scheme.isEmpty {
            return scheme == "file"
        }

        return true
    }

    private static func resolvedLocalFileURL(for source: String, relativeTo baseURL: URL) -> URL? {
        if let url = URL(string: source), let scheme = url.scheme?.lowercased(), scheme == "file" {
            return url.standardizedFileURL
        }

        return baseURL.appendingPathComponent(source).standardizedFileURL
    }

    static func localAssetURL(for fileURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = localAssetScheme
        components.host = "local"
        components.path = fileURL.path
        return components.url ?? fileURL
    }
}

// MARK: - HTML Visitor

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    // MARK: Block Elements

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined(separator: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let tag = "h\(heading.level)"
        let content = heading.children.map { visit($0) }.joined()
        let id = content.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "<\(tag) id=\"\(id)\">\(content)</\(tag)>"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = paragraph.children.map { visit($0) }.joined()
        return "<p>\(content)</p>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let content = blockQuote.children.map { visit($0) }.joined(separator: "\n")
        return "<blockquote>\n\(content)\n</blockquote>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language ?? ""
        let escaped = MarkdownRenderer.escapeHTML(codeBlock.code)
        let langAttr = lang.isEmpty ? "" : " class=\"language-\(MarkdownRenderer.escapeHTML(lang))\""
        return "<pre><code\(langAttr)>\(escaped)</code></pre>"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let items = orderedList.children.map { visit($0) }.joined(separator: "\n")
        let start = orderedList.startIndex
        let startAttr = start != 1 ? " start=\"\(start)\"" : ""
        return "<ol\(startAttr)>\n\(items)\n</ol>"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let isTaskList = unorderedList.children.contains { child in
            if let item = child as? ListItem {
                return item.checkbox != nil
            }
            return false
        }
        let classAttr = isTaskList ? " class=\"task-list\"" : ""
        let items = unorderedList.children.map { visit($0) }.joined(separator: "\n")
        return "<ul\(classAttr)>\n\(items)\n</ul>"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        if let checkbox = listItem.checkbox {
            // For task list items, unwrap paragraph children so the text
            // renders inline next to the checkbox instead of as a block <p>.
            let checked = checkbox == .checked ? " checked" : ""
            var parts: [String] = []
            for child in listItem.children {
                if let para = child as? Paragraph {
                    // Render paragraph children directly (inline content) without the <p> wrapper
                    let inline = para.children.map { visit($0) }.joined()
                    parts.append(inline)
                } else {
                    parts.append(visit(child))
                }
            }
            let content = parts.joined(separator: "\n")
            return "<li class=\"task-list-item\"><input type=\"checkbox\" disabled\(checked)> \(content)</li>"
        }
        let content = listItem.children.map { visit($0) }.joined(separator: "\n")
        return "<li>\(content)</li>"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        MarkdownRenderer.escapeHTML(html.rawHTML)
    }

    mutating func visitTable(_ table: Table) -> String {
        var result = "<table>\n<thead>\n<tr>\n"
        let head = table.head
        for cell in head.cells {
            var cellContent: [String] = []
            for child in cell.children {
                cellContent.append(visit(child))
            }
            let content = cellContent.joined()
            result += "<th>\(content)</th>\n"
        }
        result += "</tr>\n</thead>\n"

        let bodyRows = Array(table.body.rows)
        if !bodyRows.isEmpty {
            result += "<tbody>\n"
            for row in bodyRows {
                result += "<tr>\n"
                for cell in row.cells {
                    var cellContent: [String] = []
                    for child in cell.children {
                        cellContent.append(visit(child))
                    }
                    let content = cellContent.joined()
                    result += "<td>\(content)</td>\n"
                }
                result += "</tr>\n"
            }
            result += "</tbody>\n"
        }
        result += "</table>"
        return result
    }

    // MARK: Inline Elements

    mutating func visitText(_ text: Text) -> String {
        MarkdownRenderer.escapeHTML(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let content = strong.children.map { visit($0) }.joined()
        return "<strong>\(content)</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let content = emphasis.children.map { visit($0) }.joined()
        return "<em>\(content)</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let content = strikethrough.children.map { visit($0) }.joined()
        return "<del>\(content)</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(MarkdownRenderer.escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let content = link.children.map { visit($0) }.joined()
        let dest = MarkdownRenderer.sanitizeLinkURL(link.destination ?? "")
        return "<a href=\"\(dest)\">\(content)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alt = image.children.map { visit($0) }.joined()
        let src = MarkdownRenderer.sanitizeImageURL(image.source ?? "")
        let title = image.title.map { " title=\"\(MarkdownRenderer.escapeHTML($0))\"" } ?? ""
        return "<img src=\"\(src)\" alt=\"\(MarkdownRenderer.escapeHTML(alt))\"\(title)>"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        MarkdownRenderer.escapeHTML(html.rawHTML)
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        "<code>\(MarkdownRenderer.escapeHTML(symbolLink.destination ?? ""))</code>"
    }
}
