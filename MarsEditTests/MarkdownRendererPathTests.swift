import XCTest
@testable import MarsEdit

final class MarkdownRendererPathTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MarsEditTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: isPath(_:containedIn:)

    func testContainedChild() {
        let root = URL(fileURLWithPath: "/docs")
        let file = URL(fileURLWithPath: "/docs/sub/img.png")
        XCTAssertTrue(MarkdownRenderer.isPath(file, containedIn: root))
    }

    func testRootItselfIsNotContained() {
        let root = URL(fileURLWithPath: "/docs")
        XCTAssertFalse(MarkdownRenderer.isPath(root, containedIn: root))
    }

    func testRejectsSiblingWithSharedPrefix() {
        // The whole reason isPath uses a trailing-/ boundary: /docs/Foo must
        // not be treated as a parent of /docs/FooBar.
        let root = URL(fileURLWithPath: "/docs/Foo")
        let sibling = URL(fileURLWithPath: "/docs/FooBar/baz.png")
        XCTAssertFalse(MarkdownRenderer.isPath(sibling, containedIn: root))
    }

    func testRejectsParentEscape() {
        let root = URL(fileURLWithPath: "/docs/project")
        let escape = URL(fileURLWithPath: "/docs/secret.png")
        XCTAssertFalse(MarkdownRenderer.isPath(escape, containedIn: root))
    }

    func testStandardizesDotDotComponents() {
        let root = URL(fileURLWithPath: "/docs/project")
        let traversal = URL(fileURLWithPath: "/docs/project/sub/../../escape.png")
        // After standardization the path resolves outside the root.
        XCTAssertFalse(MarkdownRenderer.isPath(traversal, containedIn: root))
    }

    // MARK: localAssetURL

    func testLocalAssetURLProducesAssetScheme() {
        let file = URL(fileURLWithPath: "/Users/foo/img.png")
        let asset = MarkdownRenderer.localAssetURL(for: file)
        XCTAssertEqual(asset.scheme, MarkdownRenderer.localAssetScheme)
        XCTAssertEqual(asset.host, "local")
        XCTAssertEqual(asset.path, "/Users/foo/img.png")
    }

    // MARK: resolveLocalImageSources

    func testResolvesRelativeImageSourceToAssetURL() {
        let html = #"<img src="image.png">"#
        let resolved = MarkdownRenderer.resolveLocalImageSources(in: html, relativeTo: tempRoot)
        let expectedPath = tempRoot.appendingPathComponent("image.png").standardizedFileURL.path
        XCTAssertTrue(
            resolved.contains("\(MarkdownRenderer.localAssetScheme)://local\(expectedPath)"),
            "got: \(resolved)"
        )
    }

    func testStripsImageSourceThatEscapesBaseDirectory() {
        let html = #"<img src="../escape.png">"#
        let resolved = MarkdownRenderer.resolveLocalImageSources(in: html, relativeTo: tempRoot)
        XCTAssertEqual(resolved, #"<img src="">"#)
    }

    func testLeavesRemoteSourcesUntouched() {
        let html = #"<img src="https://example.com/x.png">"#
        let resolved = MarkdownRenderer.resolveLocalImageSources(in: html, relativeTo: tempRoot)
        XCTAssertEqual(resolved, html)
    }

    func testLeavesAbsoluteRootedSourcesUntouched() {
        // shouldResolveAsLocalPath bails on leading "/" — those are treated as
        // server-absolute, not local-disk paths.
        let html = #"<img src="/abs/path.png">"#
        let resolved = MarkdownRenderer.resolveLocalImageSources(in: html, relativeTo: tempRoot)
        XCTAssertEqual(resolved, html)
    }

    func testLeavesFragmentSourcesUntouched() {
        let html = ##"<img src="#anchor">"##
        let resolved = MarkdownRenderer.resolveLocalImageSources(in: html, relativeTo: tempRoot)
        XCTAssertEqual(resolved, html)
    }

    func testReturnsHTMLUnchangedWhenBaseURLIsNil() {
        let html = #"<img src="image.png">"#
        XCTAssertEqual(MarkdownRenderer.resolveLocalImageSources(in: html, relativeTo: nil), html)
    }

    func testResolvesToFileURLWhenAssetSchemeDisabled() {
        let html = #"<img src="image.png">"#
        let resolved = MarkdownRenderer.resolveLocalImageSources(
            in: html,
            relativeTo: tempRoot,
            useAssetScheme: false
        )
        let expected = tempRoot.appendingPathComponent("image.png").standardizedFileURL.absoluteString
        XCTAssertTrue(resolved.contains(MarkdownRenderer.escapeHTML(expected)), "got: \(resolved)")
    }

    func testHandlesMultipleImages() {
        let html = #"<img src="a.png"><img src="b.png">"#
        let resolved = MarkdownRenderer.resolveLocalImageSources(in: html, relativeTo: tempRoot)
        let aPath = tempRoot.appendingPathComponent("a.png").standardizedFileURL.path
        let bPath = tempRoot.appendingPathComponent("b.png").standardizedFileURL.path
        XCTAssertTrue(resolved.contains("local\(aPath)"), "got: \(resolved)")
        XCTAssertTrue(resolved.contains("local\(bPath)"), "got: \(resolved)")
    }
}
