import Foundation
import SwiftUI

@MainActor
final class CommandLineToolInstaller: ObservableObject {
    enum Status: Equatable {
        case notInstalled
        case installed(target: URL)
        case installedElsewhere(target: URL)
        case unavailable(reason: String)
    }

    enum ActionResult {
        case success
        case cancelled
        case failure(String)
    }

    static let defaultInstallPath = URL(fileURLWithPath: "/usr/local/bin/yanmo")

    @Published private(set) var status: Status = .notInstalled

    let scriptURL: URL?
    let installPath: URL

    init(scriptURL: URL? = Bundle.main.url(forResource: "yanmo", withExtension: nil),
         installPath: URL = CommandLineToolInstaller.defaultInstallPath) {
        self.scriptURL = scriptURL
        self.installPath = installPath
        refresh()
    }

    func refresh() {
        status = Self.evaluate(scriptURL: scriptURL, installPath: installPath)
    }

    nonisolated static func evaluate(scriptURL: URL?, installPath: URL) -> Status {
        guard let scriptURL else {
            return .unavailable(reason: "Bundled `yanmo` script not found.")
        }
        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            return .unavailable(reason: "Bundled `yanmo` script not found.")
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: installPath.path, isDirectory: &isDir)
        // Also check for a dangling symlink (fileExists follows symlinks).
        let linkAttrs = try? fm.attributesOfItem(atPath: installPath.path)
        let hasEntry = exists || linkAttrs != nil

        if !hasEntry {
            return .notInstalled
        }

        let resolved = installPath.resolvingSymlinksInPath().standardizedFileURL
        let target = scriptURL.resolvingSymlinksInPath().standardizedFileURL
        if resolved == target {
            return .installed(target: resolved)
        }
        return .installedElsewhere(target: resolved)
    }

    func install() -> ActionResult {
        guard let scriptURL else {
            return .failure("Bundled `yanmo` script not found.")
        }
        let scriptPath = scriptURL.path
        let installPathStr = installPath.path
        guard !scriptPath.contains("'"), !installPathStr.contains("'") else {
            return .failure("Refusing to install: path contains a single quote.")
        }
        let installDir = (installPathStr as NSString).deletingLastPathComponent
        let command = "/bin/mkdir -p '\(installDir)' && /bin/chmod +x '\(scriptPath)' && /bin/ln -sf '\(scriptPath)' '\(installPathStr)'"
        let result = runPrivileged(command)
        refresh()
        return result
    }

    func uninstall() -> ActionResult {
        let installPathStr = installPath.path
        guard !installPathStr.contains("'") else {
            return .failure("Refusing to uninstall: path contains a single quote.")
        }
        let command = "/bin/rm -f '\(installPathStr)'"
        let result = runPrivileged(command)
        refresh()
        return result
    }

    private func runPrivileged(_ shellCommand: String) -> ActionResult {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            return .failure("Could not create AppleScript.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 {
                return .cancelled
            }
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            return .failure(message)
        }
        return .success
    }
}
