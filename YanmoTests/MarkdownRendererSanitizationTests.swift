import XCTest
@testable import Yanmo

final class MarkdownRendererSanitizationTests: XCTestCase {
    // MARK: escapeHTML

    func testEscapesAmpersandFirst() {
        XCTAssertEqual(MarkdownRenderer.escapeHTML("&<>\""), "&amp;&lt;&gt;&quot;")
    }

    func testEscapesExistingEntityWithoutDoubleEncoding() {
        // The contract is "& becomes &amp;" — we accept double-encoding of pre-existing
        // entities; the test pins this so the ordering of replacements doesn't drift.
        XCTAssertEqual(MarkdownRenderer.escapeHTML("&amp;"), "&amp;amp;")
    }

    // MARK: sanitizeLinkURL

    func testBlocksJavascriptScheme() {
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("javascript:alert(1)"), "")
    }

    func testBlocksJavascriptCaseInsensitive() {
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("JaVaScRiPt:alert(1)"), "")
    }

    func testBlocksJavascriptWithLeadingWhitespace() {
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("   javascript:alert(1)"), "")
    }

    func testBlocksJavascriptWithEmbeddedTabsAndNewlines() {
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("java\tscript:alert(1)"), "")
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("java\nscript:alert(1)"), "")
    }

    func testBlocksVbscriptScheme() {
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("vbscript:msgbox"), "")
    }

    func testBlocksDataSchemeOnLinks() {
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("data:text/html,<script>"), "")
    }

    func testAllowsAndEscapesHTTPS() {
        XCTAssertEqual(
            MarkdownRenderer.sanitizeLinkURL("https://example.com/?a=1&b=\"x\""),
            "https://example.com/?a=1&amp;b=&quot;x&quot;"
        )
    }

    func testAllowsRelativePath() {
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("../docs/index.html"), "../docs/index.html")
    }

    func testAllowsFragment() {
        XCTAssertEqual(MarkdownRenderer.sanitizeLinkURL("#section"), "#section")
    }

    // MARK: sanitizeImageURL

    func testImageBlocksJavascript() {
        XCTAssertEqual(MarkdownRenderer.sanitizeImageURL("javascript:alert(1)"), "")
    }

    func testImageBlocksVbscript() {
        XCTAssertEqual(MarkdownRenderer.sanitizeImageURL("vbscript:msgbox"), "")
    }

    func testImageAllowsWhitelistedDataMIMEs() {
        let allowed = [
            "data:image/png;base64,abc",
            "data:image/jpeg;base64,abc",
            "data:image/jpg;base64,abc",
            "data:image/gif;base64,abc",
            "data:image/webp;base64,abc",
            "data:image/bmp;base64,abc",
            "data:image/tiff;base64,abc",
            "data:image/heic;base64,abc",
            "data:image/heif;base64,abc",
        ]
        for url in allowed {
            XCTAssertFalse(MarkdownRenderer.sanitizeImageURL(url).isEmpty, "expected \(url) to pass")
        }
    }

    func testImageRejectsNonWhitelistedDataMIMEs() {
        let rejected = [
            "data:text/html;base64,abc",
            "data:image/svg+xml;base64,abc",
            "data:image/png",
            "data:application/octet-stream;base64,abc",
        ]
        for url in rejected {
            XCTAssertEqual(MarkdownRenderer.sanitizeImageURL(url), "", "expected \(url) to be blocked")
        }
    }

    func testImageDataMIMEMatchIsCaseInsensitive() {
        XCTAssertFalse(MarkdownRenderer.sanitizeImageURL("DATA:IMAGE/PNG;BASE64,abc").isEmpty)
    }

    func testImageAllowsHTTPSAndEscapes() {
        XCTAssertEqual(
            MarkdownRenderer.sanitizeImageURL("https://example.com/a&b.png"),
            "https://example.com/a&amp;b.png"
        )
    }

    // MARK: extractTitle

    func testTitleFromFrontMatter() {
        XCTAssertEqual(MarkdownRenderer.extractTitle(from: "---\ntitle: From FM\n---\n# H1"), "From FM")
    }

    func testEmptyFrontMatterTitleFallsThroughToH1() {
        XCTAssertEqual(MarkdownRenderer.extractTitle(from: "---\ntitle:\n---\n# H1"), "H1")
    }

    func testTitleFromFirstH1WhenNoFrontMatter() {
        XCTAssertEqual(MarkdownRenderer.extractTitle(from: "intro\n# Hello\n## Sub"), "Hello")
    }

    func testTitleDefaultsToUntitled() {
        XCTAssertEqual(MarkdownRenderer.extractTitle(from: ""), "Untitled")
        XCTAssertEqual(MarkdownRenderer.extractTitle(from: "no headings here"), "Untitled")
    }

    // MARK: renderFrontMatterTable (via renderHTML)

    func testFrontMatterIndentRendersPadding() {
        let html = MarkdownRenderer.renderHTML(from: """
        ---
        title: Root
          sub: indented
        ---
        body
        """)
        // Top-level keyed entry (indent=0) → no style attribute on <th>
        XCTAssertTrue(html.contains("<th>title</th>"), "Top-level <th> should have no inline style")
        // Indented keyed entry (indent=2) → style="padding-left: 36px" on <th>
        XCTAssertTrue(html.contains("<th style=\"padding-left: 36px\">sub</th>"), "Indented keyed <th> should have padding-left: 36px")
    }
}
