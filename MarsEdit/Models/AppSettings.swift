import SwiftUI
import Combine

enum LaunchBehavior: String, CaseIterable, Codable {
    case openLastFile = "openLast"
    case showOpenDialog = "showOpen"
    case newDocument = "newDocument"

    var label: String {
        switch self {
        case .openLastFile: return "Open last file"
        case .showOpenDialog: return "Show Open dialog"
        case .newDocument: return "New document"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum DefaultPageSize: String, CaseIterable, Codable {
    case a4 = "A4"
    case letter = "Letter"

    var label: String { rawValue }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - General
    @AppStorage("launchBehavior") var launchBehavior: LaunchBehavior = .showOpenDialog
    @AppStorage("autoSaveEnabled") var autoSaveEnabled: Bool = true

    // MARK: - Editor
    @AppStorage("editorFontName") var editorFontName: String = "JetBrains Mono"
    @AppStorage("editorFontSize") var editorFontSize: Double = 15.0
    @AppStorage("editorLineHeight") var editorLineHeight: Double = 1.6
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = false
    @AppStorage("highlightCurrentLine") var highlightCurrentLine: Bool = true
    @AppStorage("wordWrap") var wordWrap: Bool = true
    @AppStorage("readingSpeedWPM") var readingSpeedWPM: Int = 200

    // MARK: - Appearance
    @AppStorage("selectedThemeId") var selectedThemeId: String = ""
    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .system
    @AppStorage("pdfExportThemeId") var pdfExportThemeId: String = ""

    // MARK: - Export
    @AppStorage("defaultPageSize") var defaultPageSize: DefaultPageSize = .a4

    // MARK: - View State
    @AppStorage("toolbarVisible") var toolbarVisible: Bool = true
    @AppStorage("sidebarVisible") var sidebarVisible: Bool = false
    @AppStorage("syncScrollEnabled") var syncScrollEnabled: Bool = false

    var currentTheme: Theme {
        if !selectedThemeId.isEmpty, let theme = Theme.theme(for: selectedThemeId) {
            return theme
        }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? Theme.defaultDark : Theme.defaultLight
    }

    var editorFont: NSFont {
        if let font = NSFont(name: editorFontName, size: CGFloat(editorFontSize)) {
            return font
        }
        if let font = NSFont(name: "SF Mono", size: CGFloat(editorFontSize)) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
    }

    func increaseFontSize() {
        editorFontSize = min(editorFontSize + 1, 72)
    }

    func decreaseFontSize() {
        editorFontSize = max(editorFontSize - 1, 8)
    }

    func resetFontSize() {
        editorFontSize = 15.0
    }
}
