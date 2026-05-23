import XCTest
@testable import Yanmo

final class CommandLineToolInstallerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CLIInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    private func makeScript() throws -> URL {
        let url = tempDir.appendingPathComponent("mars")
        try "#!/bin/sh\nexec /usr/bin/open -a Yanmo \"$@\"\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testUnavailableWhenScriptMissing() {
        let installPath = tempDir.appendingPathComponent("bin/mars")
        let missing = tempDir.appendingPathComponent("missing-script")
        let status = CommandLineToolInstaller.evaluate(scriptURL: missing, installPath: installPath)
        if case .unavailable = status { return }
        XCTFail("Expected .unavailable, got \(status)")
    }

    func testNotInstalledWhenPathAbsent() throws {
        let script = try makeScript()
        let installPath = tempDir.appendingPathComponent("bin/mars")
        let status = CommandLineToolInstaller.evaluate(scriptURL: script, installPath: installPath)
        XCTAssertEqual(status, .notInstalled)
    }

    func testInstalledWhenSymlinkResolvesToScript() throws {
        let script = try makeScript()
        let installPath = tempDir.appendingPathComponent("mars-link")
        try FileManager.default.createSymbolicLink(at: installPath, withDestinationURL: script)

        let status = CommandLineToolInstaller.evaluate(scriptURL: script, installPath: installPath)
        if case .installed = status { return }
        XCTFail("Expected .installed, got \(status)")
    }

    func testInstalledElsewhereWhenSymlinkPointsAtDifferentTarget() throws {
        let script = try makeScript()
        let other = tempDir.appendingPathComponent("other-mars")
        try "#!/bin/sh\necho other\n".write(to: other, atomically: true, encoding: .utf8)
        let installPath = tempDir.appendingPathComponent("mars-link")
        try FileManager.default.createSymbolicLink(at: installPath, withDestinationURL: other)

        let status = CommandLineToolInstaller.evaluate(scriptURL: script, installPath: installPath)
        if case .installedElsewhere = status { return }
        XCTFail("Expected .installedElsewhere, got \(status)")
    }

    func testInstalledElsewhereWhenRegularFileAtPath() throws {
        let script = try makeScript()
        let installPath = tempDir.appendingPathComponent("regular-mars")
        try "#!/bin/sh\necho hi\n".write(to: installPath, atomically: true, encoding: .utf8)

        let status = CommandLineToolInstaller.evaluate(scriptURL: script, installPath: installPath)
        if case .installedElsewhere = status { return }
        XCTFail("Expected .installedElsewhere, got \(status)")
    }
}
