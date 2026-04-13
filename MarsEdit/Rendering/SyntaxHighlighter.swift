import AppKit

/// Applies Markdown syntax highlighting to an NSTextStorage.
/// This is cosmetic only — the underlying text remains plain Markdown.
struct SyntaxHighlighter {
    let theme: Theme
    let font: NSFont

    func highlight(_ textStorage: NSTextStorage) {
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Reset to base style
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.editorTextColor,
        ]
        textStorage.setAttributes(baseAttributes, range: fullRange)

        highlightHeadings(textStorage, text: text)
        highlightBold(textStorage, text: text)
        highlightItalic(textStorage, text: text)
        highlightStrikethrough(textStorage, text: text)
        highlightInlineCode(textStorage, text: text)
        highlightCodeBlocks(textStorage, text: text)
        highlightLinks(textStorage, text: text)
        highlightImages(textStorage, text: text)
        highlightBlockquotes(textStorage, text: text)
        highlightHorizontalRules(textStorage, text: text)
        highlightListMarkers(textStorage, text: text)
    }

    // MARK: - Headings

    private func highlightHeadings(_ storage: NSTextStorage, text: String) {
        let pattern = "^(#{1,6})\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
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

    private func highlightBold(_ storage: NSTextStorage, text: String) {
        let pattern = "(\\*\\*|__)(.+?)(\\*\\*|__)"
        applyInlineStyle(storage, text: text, pattern: pattern) { range in
            let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: boldFont, range: range)
        }
    }

    // MARK: - Italic

    private func highlightItalic(_ storage: NSTextStorage, text: String) {
        let pattern = "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"
        applyInlineStyle(storage, text: text, pattern: pattern) { range in
            let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italicFont, range: range)
        }
    }

    // MARK: - Strikethrough

    private func highlightStrikethrough(_ storage: NSTextStorage, text: String) {
        let pattern = "~~(.+?)~~"
        applyInlineStyle(storage, text: text, pattern: pattern) { range in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
    }

    // MARK: - Inline Code

    private func highlightInlineCode(_ storage: NSTextStorage, text: String) {
        let pattern = "(?<!`)`(?!`)([^`]+)`(?!`)"
        applyInlineStyle(storage, text: text, pattern: pattern) { range in
            let monoFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            storage.addAttributes([
                .font: monoFont,
                .backgroundColor: theme.editorCodeBackground,
            ], range: range)
        }
    }

    // MARK: - Code Blocks

    private func highlightCodeBlocks(_ storage: NSTextStorage, text: String) {
        let pattern = "^```[\\s\\S]*?^```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .dotMatchesLineSeparators]) else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            let monoFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            storage.addAttributes([
                .font: monoFont,
                .backgroundColor: theme.editorCodeBackground,
                .foregroundColor: theme.editorTextColor,
            ], range: match.range)
        }
    }

    // MARK: - Links

    private func highlightLinks(_ storage: NSTextStorage, text: String) {
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            storage.addAttribute(.foregroundColor, value: theme.editorLinkColor, range: match.range)
            if match.numberOfRanges > 1 {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            }
        }
    }

    // MARK: - Images

    private func highlightImages(_ storage: NSTextStorage, text: String) {
        let pattern = "!\\[([^\\]]*)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            storage.addAttribute(.foregroundColor, value: theme.editorLinkColor, range: match.range)
        }

        // Fold base64 embedded images: collapse the data body to near-invisible
        // while keeping the markdown syntax and a fold indicator visible.
        foldBase64Images(storage, text: text)
    }

    /// Visually folds base64 image data in the editor.
    ///
    /// For `![alt](data:image/png;base64,<HUGE DATA>)`:
    /// - `![alt](data:image/png;base64,` — visible, dimmed, normal font
    /// - `<HUGE DATA>` — collapsed to 0.1pt font, effectively invisible
    /// - `)` — visible at end
    ///
    /// The underlying text is untouched — only the visual rendering changes.
    private func foldBase64Images(_ storage: NSTextStorage, text: String) {
        // Match the full ![...](data:image/...;base64,...) pattern
        let pattern = "(!\\[[^\\]]*\\]\\(data:image/[^;]+;base64,)([A-Za-z0-9+/=\\s]{64,})(\\))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        let dimmedColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5)

        for match in matches {
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

    private func highlightBlockquotes(_ storage: NSTextStorage, text: String) {
        let pattern = "^>\\s?.*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
    }

    // MARK: - Horizontal Rules

    private func highlightHorizontalRules(_ storage: NSTextStorage, text: String) {
        let pattern = "^(---+|\\*\\*\\*+|___+)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            storage.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: match.range)
        }
    }

    // MARK: - List Markers

    private func highlightListMarkers(_ storage: NSTextStorage, text: String) {
        let pattern = "^\\s*([-*+]|\\d+\\.)\\s"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            storage.addAttribute(.foregroundColor, value: theme.editorLinkColor, range: match.range)
        }
    }

    // MARK: - Helpers

    private func applyInlineStyle(_ storage: NSTextStorage, text: String, pattern: String, apply: (NSRange) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            apply(match.range)
        }
    }
}
