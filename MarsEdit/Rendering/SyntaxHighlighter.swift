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

    /// Highlight the storage. If `editedRange` is non-nil, only re-highlight a
    /// region around that range; otherwise re-highlight the whole document.
    func highlight(_ textStorage: NSTextStorage, in editedRange: NSRange? = nil) {
        let text = textStorage.string
        let fullLength = textStorage.length
        let fullRange = NSRange(location: 0, length: fullLength)

        let target: NSRange = {
            guard let edited = editedRange else { return fullRange }
            return Self.expandedRange(for: edited, in: text, fullLength: fullLength)
        }()

        // Reset to base style across the target range
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.editorTextColor,
        ]
        textStorage.setAttributes(baseAttributes, range: target)

        highlightHeadings(textStorage, text: text, range: target)
        highlightBold(textStorage, text: text, range: target)
        highlightItalic(textStorage, text: text, range: target)
        highlightStrikethrough(textStorage, text: text, range: target)
        highlightInlineCode(textStorage, text: text, range: target)
        highlightCodeBlocks(textStorage, text: text, range: target)
        highlightLinks(textStorage, text: text, range: target)
        highlightImages(textStorage, text: text, range: target)
        highlightBlockquotes(textStorage, text: text, range: target)
        highlightHorizontalRules(textStorage, text: text, range: target)
        highlightListMarkers(textStorage, text: text, range: target)
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

        var range = NSRange(location: start, length: end - start)

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

    // MARK: - Headings

    private func highlightHeadings(_ storage: NSTextStorage, text: String, range: NSRange) {
        for match in Self.headingRegex.matches(in: text, range: range) {
            let level = match.range(at: 1).length
            let fontSize = max(font.pointSize, font.pointSize + CGFloat(4 - level) * 2)
            let headingFont = NSFontManager.shared.convert(font, toSize: fontSize)
            let boldFont = NSFontManager.shared.convert(headingFont, toHaveTrait: .boldFontMask)
            storage.addAttributes([
                .font: boldFont,
                .foregroundColor: theme.editorHeadingColor,
            ], range: match.range)
        }
    }

    // MARK: - Bold

    private func highlightBold(_ storage: NSTextStorage, text: String, range: NSRange) {
        applyInlineStyle(storage, text: text, regex: Self.boldRegex, range: range) { matchRange in
            let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: boldFont, range: matchRange)
        }
    }

    // MARK: - Italic

    private func highlightItalic(_ storage: NSTextStorage, text: String, range: NSRange) {
        applyInlineStyle(storage, text: text, regex: Self.italicRegex, range: range) { matchRange in
            let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italicFont, range: matchRange)
        }
    }

    // MARK: - Strikethrough

    private func highlightStrikethrough(_ storage: NSTextStorage, text: String, range: NSRange) {
        applyInlineStyle(storage, text: text, regex: Self.strikethroughRegex, range: range) { matchRange in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: matchRange)
        }
    }

    // MARK: - Inline Code

    private func highlightInlineCode(_ storage: NSTextStorage, text: String, range: NSRange) {
        applyInlineStyle(storage, text: text, regex: Self.inlineCodeRegex, range: range) { matchRange in
            let monoFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            storage.addAttributes([
                .font: monoFont,
                .backgroundColor: theme.editorCodeBackground,
            ], range: matchRange)
        }
    }

    // MARK: - Code Blocks

    private func highlightCodeBlocks(_ storage: NSTextStorage, text: String, range: NSRange) {
        for match in Self.codeBlockRegex.matches(in: text, range: range) {
            let monoFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            storage.addAttributes([
                .font: monoFont,
                .backgroundColor: theme.editorCodeBackground,
                .foregroundColor: theme.editorTextColor,
            ], range: match.range)
        }
    }

    // MARK: - Links

    private func highlightLinks(_ storage: NSTextStorage, text: String, range: NSRange) {
        for match in Self.linkRegex.matches(in: text, range: range) {
            storage.addAttribute(.foregroundColor, value: theme.editorLinkColor, range: match.range)
            if match.numberOfRanges > 1 {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            }
        }
    }

    // MARK: - Images

    private func highlightImages(_ storage: NSTextStorage, text: String, range: NSRange) {
        for match in Self.imageRegex.matches(in: text, range: range) {
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
                .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 2, weight: .regular),
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
                .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 2, weight: .regular),
            ], range: suffixRange)
        }
    }

    // MARK: - Blockquotes

    private func highlightBlockquotes(_ storage: NSTextStorage, text: String, range: NSRange) {
        for match in Self.blockquoteRegex.matches(in: text, range: range) {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
    }

    // MARK: - Horizontal Rules

    private func highlightHorizontalRules(_ storage: NSTextStorage, text: String, range: NSRange) {
        for match in Self.horizontalRuleRegex.matches(in: text, range: range) {
            storage.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: match.range)
        }
    }

    // MARK: - List Markers

    private func highlightListMarkers(_ storage: NSTextStorage, text: String, range: NSRange) {
        for match in Self.listMarkerRegex.matches(in: text, range: range) {
            storage.addAttribute(.foregroundColor, value: theme.editorLinkColor, range: match.range)
        }
    }

    // MARK: - Helpers

    private func applyInlineStyle(_ storage: NSTextStorage, text: String, regex: NSRegularExpression, range: NSRange, apply: (NSRange) -> Void) {
        for match in regex.matches(in: text, range: range) {
            apply(match.range)
        }
    }
}
