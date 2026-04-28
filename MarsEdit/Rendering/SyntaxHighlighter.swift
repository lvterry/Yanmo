import AppKit

/// Applies Markdown syntax highlighting to an NSTextStorage.
/// This is cosmetic only — the underlying text remains plain Markdown.
struct SyntaxHighlighter {
    let theme: Theme
    let font: NSFont

    // MARK: - Cached compiled regexes (compiled once, reused for every keystroke)

    private static let headingRegex      = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: .anchorsMatchLines)
    private static let boldRegex         = try! NSRegularExpression(pattern: "(\\*\\*|__)(.+?)(\\*\\*|__)")
    private static let italicRegex       = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)")
    private static let strikethroughRegex = try! NSRegularExpression(pattern: "~~(.+?)~~")
    private static let inlineCodeRegex   = try! NSRegularExpression(pattern: "(?<!`)`(?!`)([^`]+)`(?!`)")
    private static let codeBlockRegex    = try! NSRegularExpression(pattern: "^```[\\s\\S]*?^```", options: [.anchorsMatchLines, .dotMatchesLineSeparators])
    private static let linkRegex         = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
    private static let imageRegex        = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)")
    private static let base64ImageRegex  = try! NSRegularExpression(pattern: "(!\\[[^\\]]*\\]\\(data:image/[^;]+;base64,)([A-Za-z0-9+/=\\s]{64,})(\\))", options: [.dotMatchesLineSeparators])
    private static let blockquoteRegex   = try! NSRegularExpression(pattern: "^>\\s?.*$", options: .anchorsMatchLines)
    private static let horizontalRuleRegex = try! NSRegularExpression(pattern: "^(---+|\\*\\*\\*+|___+)\\s*$", options: .anchorsMatchLines)
    private static let listMarkerRegex   = try! NSRegularExpression(pattern: "^\\s*([-*+]|\\d+\\.)\\s", options: .anchorsMatchLines)
    private static let frontMatterDelimiterLineRegex = try! NSRegularExpression(pattern: "^(---|\\.\\.\\.)\\s*$", options: .anchorsMatchLines)

    /// Highlight the storage. If `editedRange` is non-nil, only re-highlight a
    /// region around that range; otherwise re-highlight the whole document.
    func highlight(_ textStorage: NSTextStorage, in editedRange: NSRange? = nil) {
        let text = textStorage.string
        let fullLength = textStorage.length
        let fullRange = NSRange(location: 0, length: fullLength)

        let frontMatterRange = Self.frontMatterNSRange(in: text)

        var target: NSRange = {
            guard let edited = editedRange else { return fullRange }
            return Self.expandedRange(for: edited, in: text, fullLength: fullLength)
        }()

        // Front matter is anchored to offset 0; if an edit lands inside (or
        // could plausibly affect) it, expand the highlight target to cover
        // the whole front-matter region from offset 0.
        if let fmRange = frontMatterRange,
           target.location < fmRange.location + fmRange.length + 1 {
            let newEnd = max(target.location + target.length, fmRange.location + fmRange.length)
            target = NSRange(location: 0, length: newEnd)
        } else if let edited = editedRange,
                  edited.location < 2048,
                  Self.startsWithFrontMatterOpening(text) {
            let targetEnd = target.location + target.length
            target = NSRange(location: 0, length: targetEnd)
        }

        // Reset to base style across the target range
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.editorTextColor,
        ]
        textStorage.setAttributes(baseAttributes, range: target)

        highlightStrikethrough(textStorage, text: text, range: target, skipping: frontMatterRange)
        highlightLinks(textStorage, text: text, range: target, skipping: frontMatterRange)
        highlightImages(textStorage, text: text, range: target, skipping: frontMatterRange)
        highlightBlockquotes(textStorage, text: text, range: target, skipping: frontMatterRange)
        highlightHorizontalRules(textStorage, text: text, range: target, skipping: frontMatterRange)
        highlightListMarkers(textStorage, text: text, range: target, skipping: frontMatterRange)
    }

    // MARK: - Front Matter

    private static func frontMatterNSRange(in text: String) -> NSRange? {
        guard let fm = FrontMatter.parse(text) else { return nil }
        return NSRange(fm.range, in: text)
    }

    private static func startsWithFrontMatterOpening(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let nsText = text as NSString
        let firstLineRange = nsText.lineRange(for: NSRange(location: 0, length: 0))
        let firstLine = nsText.substring(with: firstLineRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return firstLine == "---"
    }

    private static func skip(_ matchRange: NSRange, frontMatter: NSRange?) -> Bool {
        guard let fm = frontMatter else { return false }
        return NSIntersectionRange(matchRange, fm).length > 0
    }

    // MARK: - Range expansion

    /// Expand the edited range outward to safe boundaries:
    /// - At least to the surrounding paragraph (between blank lines).
    /// - If a fenced code block straddles the expanded range, expand to the full document
    ///   (fences span paragraphs and switch the meaning of intervening text).
    private static func expandedRange(for editedRange: NSRange, in text: String, fullLength: Int) -> NSRange {
        guard fullLength > 0 else { return NSRange(location: 0, length: 0) }
        let nsText = text as NSString

        // Clamp inputs.
        let location = max(0, min(editedRange.location, fullLength))
        let endLocation = max(location, min(editedRange.location + editedRange.length, fullLength))

        // Walk back to a blank line (or document start).
        var start = location
        while start > 0 {
            let probe = NSRange(location: start - 1, length: 0)
            let lineRange = nsText.lineRange(for: probe)
            let lineText = nsText.substring(with: lineRange)
            if lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }
            if lineRange.location >= start { break } // safety
            start = lineRange.location
        }

        // Walk forward to a blank line (or document end).
        var end = endLocation
        while end < fullLength {
            let lineRange = nsText.lineRange(for: NSRange(location: end, length: 0))
            let lineEnd = lineRange.location + lineRange.length
            if lineEnd <= end { break } // safety
            end = lineEnd
            let lineText = nsText.substring(with: lineRange)
            if lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }
        }

        let range = NSRange(location: start, length: end - start)

        // Fenced code blocks span paragraphs. If any fence pair intersects the expanded
        // range — or if the edit point sits inside one — fall back to a full re-highlight.
        let fences = codeBlockRegex.matches(in: text, range: NSRange(location: 0, length: fullLength))
        for m in fences {
            if NSIntersectionRange(m.range, range).length > 0 || NSLocationInRange(location, m.range) {
                return NSRange(location: 0, length: fullLength)
            }
        }
        // Also: an unbalanced fence (open ``` with no matching close) means a fence was
        // just opened/closed — re-highlight the whole document.
        let fenceCount = nsText.components(separatedBy: "```").count - 1
        if fenceCount % 2 == 1 {
            return NSRange(location: 0, length: fullLength)
        }

        return range
    }

    // MARK: - Strikethrough

    private func highlightStrikethrough(_ storage: NSTextStorage, text: String, range: NSRange, skipping frontMatter: NSRange?) {
        applyInlineStyle(storage, text: text, regex: Self.strikethroughRegex, range: range, skipping: frontMatter) { matchRange in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: matchRange)
        }
    }

    // MARK: - Links

    private func highlightLinks(_ storage: NSTextStorage, text: String, range: NSRange, skipping frontMatter: NSRange?) {
        for match in Self.linkRegex.matches(in: text, range: range) {
            if Self.skip(match.range, frontMatter: frontMatter) { continue }
            storage.addAttribute(.foregroundColor, value: theme.editorLinkColor, range: match.range)
            if match.numberOfRanges > 1 {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            }
        }
    }

    // MARK: - Images

    private func highlightImages(_ storage: NSTextStorage, text: String, range: NSRange, skipping frontMatter: NSRange?) {
        for match in Self.imageRegex.matches(in: text, range: range) {
            if Self.skip(match.range, frontMatter: frontMatter) { continue }
            storage.addAttribute(.foregroundColor, value: theme.editorLinkColor, range: match.range)
        }

        // Fold base64 embedded images: collapse the data body to near-invisible
        // while keeping the markdown syntax and a fold indicator visible.
        foldBase64Images(storage, text: text, range: range)
    }

    /// Visually folds base64 image data in the editor.
    ///
    /// For `![alt](data:image/png;base64,<HUGE DATA>)`:
    /// - `![alt](data:image/png;base64,` — visible, dimmed, normal font
    /// - `<HUGE DATA>` — collapsed to 0.1pt font, effectively invisible
    /// - `)` — visible at end
    ///
    /// The underlying text is untouched — only the visual rendering changes.
    private func foldBase64Images(_ storage: NSTextStorage, text: String, range: NSRange) {
        let dimmedColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5)

        for match in Self.base64ImageRegex.matches(in: text, range: range) {
            guard match.numberOfRanges == 4 else { continue }

            let prefixRange = match.range(at: 1)  // ![alt](data:image/png;base64,
            let dataRange = match.range(at: 2)     // the actual base64 data
            let suffixRange = match.range(at: 3)   // )

            // Style the prefix: visible but dimmed
            storage.addAttributes([
                .foregroundColor: dimmedColor,
                .font: font,
            ], range: prefixRange)

            // Collapse the base64 body to near-invisible (0.1pt font, transparent)
            // The text remains in the document for copy/paste/save,
            // but takes up virtually no visual space.
            let tinyFont = NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular)
            storage.addAttributes([
                .font: tinyFont,
                .foregroundColor: NSColor.clear,
            ], range: dataRange)

            // Style the closing paren: dimmed
            storage.addAttributes([
                .foregroundColor: dimmedColor,
                .font: font,
            ], range: suffixRange)
        }
    }

    // MARK: - Blockquotes

    private func highlightBlockquotes(_ storage: NSTextStorage, text: String, range: NSRange, skipping frontMatter: NSRange?) {
        for match in Self.blockquoteRegex.matches(in: text, range: range) {
            if Self.skip(match.range, frontMatter: frontMatter) { continue }
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
    }

    // MARK: - Horizontal Rules

    private func highlightHorizontalRules(_ storage: NSTextStorage, text: String, range: NSRange, skipping frontMatter: NSRange?) {
        for match in Self.horizontalRuleRegex.matches(in: text, range: range) {
            if Self.skip(match.range, frontMatter: frontMatter) { continue }
            storage.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: match.range)
        }
    }

    // MARK: - List Markers

    private func highlightListMarkers(_ storage: NSTextStorage, text: String, range: NSRange, skipping frontMatter: NSRange?) {
        for match in Self.listMarkerRegex.matches(in: text, range: range) {
            if Self.skip(match.range, frontMatter: frontMatter) { continue }
            storage.addAttribute(.foregroundColor, value: theme.editorLinkColor, range: match.range)
        }
    }

    // MARK: - Helpers

    private func applyInlineStyle(
        _ storage: NSTextStorage,
        text: String,
        regex: NSRegularExpression,
        range: NSRange,
        skipping frontMatter: NSRange?,
        apply: (NSRange) -> Void
    ) {
        for match in regex.matches(in: text, range: range) {
            if Self.skip(match.range, frontMatter: frontMatter) { continue }
            apply(match.range)
        }
    }
}
