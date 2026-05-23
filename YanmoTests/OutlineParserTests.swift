import XCTest
@testable import Yanmo

final class OutlineParserTests: XCTestCase {
    func testExtractsHeadingsAtAllLevels() {
        let items = OutlineParser.parse("# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6")
        XCTAssertEqual(items.map(\.level), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(items.map(\.title), ["H1", "H2", "H3", "H4", "H5", "H6"])
    }

    func testIgnoresBeyondLevelSix() {
        let items = OutlineParser.parse("####### Too deep")
        XCTAssertTrue(items.isEmpty)
    }

    func testRequiresSpaceAfterHashes() {
        let items = OutlineParser.parse("#NoSpace\n# Real")
        XCTAssertEqual(items.map(\.title), ["Real"])
    }

    func testRejectsEmptyTitle() {
        let items = OutlineParser.parse("# \n#")
        XCTAssertTrue(items.isEmpty)
    }

    func testIgnoresHeadingsInsideBacktickFence() {
        let items = OutlineParser.parse("# Before\n```\n# Inside\n```\n# After")
        XCTAssertEqual(items.map(\.title), ["Before", "After"])
    }

    func testIgnoresHeadingsInsideTildeFence() {
        let items = OutlineParser.parse("~~~\n# Inside\n~~~\n# After")
        XCTAssertEqual(items.map(\.title), ["After"])
    }

    func testFenceOnlyClosedByMatchingMarker() {
        let items = OutlineParser.parse("```\n# Inside\n~~~\n# Still inside\n```\n# After")
        XCTAssertEqual(items.map(\.title), ["After"])
    }

    func testRangeLocatesHeadingInSource() {
        let source = "intro\n## Target\nrest"
        let items = OutlineParser.parse(source)
        XCTAssertEqual(items.count, 1)
        let item = items[0]
        let nsSource = source as NSString
        XCTAssertEqual(nsSource.substring(with: item.range), "## Target")
    }

    func testIndentLevelIsZeroBased() {
        let items = OutlineParser.parse("# A\n### C")
        XCTAssertEqual(items.map(\.indentLevel), [0, 2])
    }

    func testHandlesCRLFLineEndings() {
        let items = OutlineParser.parse("# A\r\n## B\r\n")
        XCTAssertEqual(items.map(\.title), ["A", "B"])
    }
}
