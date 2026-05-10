import XCTest
@testable import MarsEdit

final class FrontMatterTests: XCTestCase {
    func testReturnsNilWhenAbsent() {
        XCTAssertNil(FrontMatter.parse("# Heading\nbody"))
        XCTAssertNil(FrontMatter.parse(""))
    }

    func testReturnsNilWhenOpeningWithoutClose() {
        XCTAssertNil(FrontMatter.parse("---\ntitle: Hi\nbody"))
    }

    func testRequiresOpeningOnFirstLine() {
        XCTAssertNil(FrontMatter.parse("\n---\ntitle: Hi\n---\nbody"))
    }

    func testParsesKeyValueEntries() {
        let fm = FrontMatter.parse("---\ntitle: Hello\nauthor: Ada\n---\nbody")
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.entries.count, 2)
        XCTAssertEqual(fm?.value(for: "title"), "Hello")
        XCTAssertEqual(fm?.value(for: "author"), "Ada")
    }

    func testAcceptsDotsAsClosingDelimiter() {
        let fm = FrontMatter.parse("---\ntitle: Hi\n...\nbody")
        XCTAssertEqual(fm?.value(for: "title"), "Hi")
    }

    func testStripsMatchingQuotes() {
        let fm = FrontMatter.parse(#"""
        ---
        a: "quoted"
        b: 'single'
        c: "mismatched'
        ---
        body
        """#)
        XCTAssertEqual(fm?.value(for: "a"), "quoted")
        XCTAssertEqual(fm?.value(for: "b"), "single")
        XCTAssertEqual(fm?.value(for: "c"), "\"mismatched'")
    }

    func testKeylessLineBecomesRawEntry() {
        let fm = FrontMatter.parse("---\nplain text line\n---\nbody")
        XCTAssertEqual(fm?.entries.count, 1)
        XCTAssertNil(fm?.entries.first?.key)
        XCTAssertEqual(fm?.entries.first?.value, "plain text line")
    }

    func testStrippingRemovesFrontMatterAndTrailingNewline() {
        let stripped = FrontMatter.stripping("---\ntitle: Hi\n---\nbody")
        XCTAssertEqual(stripped, "body")
    }

    func testStrippingLeavesSourceUntouchedWhenNoFrontMatter() {
        XCTAssertEqual(FrontMatter.stripping("body only"), "body only")
    }

    func testValueForReturnsFirstMatch() {
        let fm = FrontMatter.parse("---\ntag: a\ntag: b\n---\nbody")
        XCTAssertEqual(fm?.value(for: "tag"), "a")
    }
}
