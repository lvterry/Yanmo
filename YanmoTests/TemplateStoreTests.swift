import XCTest
@testable import Yanmo

final class TemplateStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemplateStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    private func makeStore(seedFiles: [String: String] = [:],
                          preExistingUserFiles: [String: String]? = nil) throws -> TemplateStore {
        let userDir = tempRoot.appendingPathComponent("user", isDirectory: true)
        let bundleDir = tempRoot.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        for (name, body) in seedFiles {
            try body.write(to: bundleDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        if let userFiles = preExistingUserFiles {
            try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
            for (name, body) in userFiles {
                try body.write(to: userDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
        return TemplateStore(userDirectory: userDir,
                             bundleSeedDirectory: bundleDir,
                             observeActivation: false)
    }

    func testSeedsBundleTemplatesWhenUserDirectoryMissing() throws {
        let store = try makeStore(seedFiles: [
            "Skill.md": "skill body",
            "Note.md": "note body",
        ])

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.userDirectory.path))
        XCTAssertEqual(store.templates.map(\.displayName), ["Note", "Skill"])
        let skillContents = try store.readContents(of: store.templates.first { $0.displayName == "Skill" }!)
        XCTAssertEqual(skillContents, "skill body")
    }

    func testDoesNotReSeedWhenUserDirectoryAlreadyExists() throws {
        let store = try makeStore(
            seedFiles: ["Skill.md": "from bundle"],
            preExistingUserFiles: [:] // creates empty user directory
        )

        XCTAssertTrue(store.templates.isEmpty, "Existing empty user directory must be respected (no re-seed)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.userDirectory.appendingPathComponent("Skill.md").path))
    }

    func testReloadIgnoresNonMarkdownFiles() throws {
        let store = try makeStore(preExistingUserFiles: [
            "Real.md": "x",
            "README.txt": "x",
            ".DS_Store": "x",
        ])

        XCTAssertEqual(store.templates.map(\.displayName), ["Real"])
    }

    func testReloadIgnoresSubdirectories() throws {
        let store = try makeStore(preExistingUserFiles: ["Top.md": "x"])
        let nested = store.userDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "x".write(to: nested.appendingPathComponent("Inner.md"), atomically: true, encoding: .utf8)

        store.reload()
        XCTAssertEqual(store.templates.map(\.displayName), ["Top"])
    }

    func testReloadSortsCaseInsensitively() throws {
        let store = try makeStore(preExistingUserFiles: [
            "banana.md": "x",
            "Apple.md": "x",
            "cherry.md": "x",
        ])

        XCTAssertEqual(store.templates.map(\.displayName), ["Apple", "banana", "cherry"])
    }

    func testReloadPicksUpAddedAndRemovedFiles() throws {
        let store = try makeStore(preExistingUserFiles: ["A.md": "x"])
        XCTAssertEqual(store.templates.map(\.displayName), ["A"])

        try "y".write(to: store.userDirectory.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertEqual(store.templates.map(\.displayName), ["A", "B"])

        try FileManager.default.removeItem(at: store.userDirectory.appendingPathComponent("A.md"))
        store.reload()
        XCTAssertEqual(store.templates.map(\.displayName), ["B"])
    }

    func testReadContentsReturnsFileBody() throws {
        let body = "# Hello\n\nBody."
        let store = try makeStore(preExistingUserFiles: ["Hello.md": body])
        let template = try XCTUnwrap(store.templates.first)
        XCTAssertEqual(try store.readContents(of: template), body)
    }
}
