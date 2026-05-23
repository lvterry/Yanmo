import AppKit
import Combine
import Foundation

/// App-wide store for user-editable markdown templates surfaced under
/// File ▸ New from Template.
///
/// Templates live in `~/Library/Application Support/Yanmo/Templates/` so
/// users can freely edit them in Finder. On first launch (when the user
/// directory does not yet exist), seed templates bundled with the app are
/// copied in. Once the directory exists we never touch its contents — if the
/// user empties it, the menu reflects that.
///
/// The list is refreshed on `NSApplication.didBecomeActiveNotification`, which
/// covers the common workflow of editing in Finder/another editor and
/// switching back. File contents are read lazily when a template is selected,
/// so in-place body edits are picked up without any explicit refresh.
final class TemplateStore: ObservableObject {
    struct Template: Identifiable, Hashable {
        let url: URL
        let displayName: String
        var id: URL { url }
    }

    @Published private(set) var templates: [Template] = []

    let userDirectory: URL
    private let bundleSeedDirectory: URL?
    private var activationObserver: NSObjectProtocol?

    static let shared = TemplateStore()

    init(userDirectory: URL = TemplateStore.defaultUserDirectory(),
         bundleSeedDirectory: URL? = TemplateStore.defaultBundleSeedDirectory(),
         observeActivation: Bool = true) {
        self.userDirectory = userDirectory
        self.bundleSeedDirectory = bundleSeedDirectory
        seedIfNeeded()
        reload()
        if observeActivation {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reload()
            }
        }
    }

    deinit {
        if let token = activationObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    static func defaultUserDirectory() -> URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Yanmo", isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true)
    }

    static func defaultBundleSeedDirectory() -> URL? {
        if let url = Bundle.main.url(forResource: "Templates", withExtension: nil) {
            return url
        }
        return Bundle.main.resourceURL?.appendingPathComponent("Templates", isDirectory: true)
    }

    func reload() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: userDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            templates = []
            return
        }

        let listed = contents
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { Template(url: $0, displayName: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        if listed != templates {
            templates = listed
        }
    }

    func readContents(of template: Template) throws -> String {
        try String(contentsOf: template.url, encoding: .utf8)
    }

    func revealInFinder() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: userDirectory.path) {
            try? fm.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([userDirectory])
    }

    /// Seed the user directory from the bundle on first run. Only acts when
    /// the user directory does not exist — once present, contents are the
    /// user's to manage.
    private func seedIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: userDirectory.path) else { return }

        do {
            try fm.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let seedRoot = bundleSeedDirectory,
              let seeds = try? fm.contentsOfDirectory(
                at: seedRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
              ) else {
            return
        }

        for seed in seeds where seed.pathExtension.lowercased() == "md" {
            let destination = userDirectory.appendingPathComponent(seed.lastPathComponent)
            try? fm.copyItem(at: seed, to: destination)
        }
    }
}
