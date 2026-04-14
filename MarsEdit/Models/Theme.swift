import SwiftUI

enum ThemeMode: String, CaseIterable, Codable {
    case light
    case dark
}

struct Theme: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let mode: ThemeMode
    let cssFileName: String

    var cssResourceName: String {
        cssFileName.replacingOccurrences(of: ".css", with: "")
    }

    static let builtIn: [Theme] = [
        Theme(id: "default-light", name: "Default Light", mode: .light, cssFileName: "default-light.css"),
        Theme(id: "default-dark", name: "Default Dark", mode: .dark, cssFileName: "default-dark.css"),
        Theme(id: "solarized-light", name: "Solarized Light", mode: .light, cssFileName: "solarized-light.css"),
        Theme(id: "solarized-dark", name: "Solarized Dark", mode: .dark, cssFileName: "solarized-dark.css"),
        Theme(id: "nord", name: "Nord", mode: .dark, cssFileName: "nord.css"),
        Theme(id: "github", name: "GitHub", mode: .light, cssFileName: "github.css"),
    ]

    static let defaultLight = Theme(id: "default-light", name: "Default Light", mode: .light, cssFileName: "default-light.css")
    static let defaultDark = Theme(id: "default-dark", name: "Default Dark", mode: .dark, cssFileName: "default-dark.css")

    static func theme(for id: String) -> Theme? {
        builtIn.first { $0.id == id }
    }

    func loadCSS() -> String {
        // Try multiple bundle lookup strategies (folder reference vs group)
        let lookups: [URL?] = [
            Bundle.main.url(forResource: cssResourceName, withExtension: "css", subdirectory: "Themes"),
            Bundle.main.url(forResource: cssResourceName, withExtension: "css", subdirectory: "Resources/Themes"),
            Bundle.main.url(forResource: cssFileName, withExtension: nil, subdirectory: "Themes"),
            Bundle.main.url(forResource: cssFileName, withExtension: nil, subdirectory: "Resources/Themes"),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/Themes/\(cssFileName)"),
            Bundle.main.resourceURL?.appendingPathComponent("Themes/\(cssFileName)"),
        ]

        for case let url? in lookups {
            if let css = try? String(contentsOf: url) {
                return css
            }
        }

        // Fallback: return embedded default CSS
        return Self.fallbackCSS(for: mode)
    }

    /// Comprehensive fallback CSS when bundle resources can't be found.
    static func fallbackCSS(for mode: ThemeMode) -> String {
        let bg = mode == .light ? "#ffffff" : "#1e1e1e"
        let fg = mode == .light ? "#24292f" : "#d4d4d4"
        let fgSecondary = mode == .light ? "#656d76" : "#8b949e"
        let link = mode == .light ? "#0969da" : "#58a6ff"
        let border = mode == .light ? "#d0d7de" : "#3d444d"
        let codeBg = mode == .light ? "#f6f8fa" : "#2d2d2d"
        let headerBg = mode == .light ? "#f6f8fa" : "#262626"
        let stripeBg = mode == .light ? "#f6f8fa" : "#262626"
        let quoteBorder = mode == .light ? "#d0d7de" : "#3d444d"

        return """
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Helvetica, Arial, sans-serif;
            font-size: 15px;
            line-height: 1.6;
            max-width: 780px;
            margin: 0 auto;
            padding: 24px 32px;
            background-color: \(bg);
            color: \(fg);
            -webkit-font-smoothing: antialiased;
            -webkit-text-size-adjust: 100%;
        }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 24px;
            margin-bottom: 16px;
            font-weight: 600;
            line-height: 1.25;
            color: \(fg);
        }
        h1 {
            font-size: 2em;
            padding-bottom: 0.3em;
            border-bottom: 1px solid \(border);
        }
        h2 {
            font-size: 1.5em;
            padding-bottom: 0.3em;
            border-bottom: 1px solid \(border);
        }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: 0.875em; }
        h6 { font-size: 0.85em; color: \(fgSecondary); }
        p { margin-top: 0; margin-bottom: 16px; }
        ul, ol { margin-top: 0; margin-bottom: 16px; padding-left: 2em; }
        li { margin-bottom: 4px; }
        a { color: \(link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 600; }
        code {
            font-family: 'JetBrains Mono', 'SF Mono', 'Menlo', 'Consolas', monospace;
            background-color: \(codeBg);
            padding: 0.2em 0.4em;
            border-radius: 6px;
            font-size: 85%;
        }
        pre {
            background-color: \(codeBg);
            padding: 16px;
            border-radius: 6px;
            overflow-x: auto;
            line-height: 1.45;
            margin-bottom: 16px;
        }
        pre code {
            background: none;
            padding: 0;
            border-radius: 0;
            font-size: 85%;
        }
        blockquote {
            border-left: 4px solid \(quoteBorder);
            padding: 0 16px;
            margin: 0 0 16px 0;
            color: \(fgSecondary);
        }
        blockquote > :first-child { margin-top: 0; }
        blockquote > :last-child { margin-bottom: 0; }
        table {
            border-collapse: collapse;
            border-spacing: 0;
            width: 100%;
            margin-bottom: 16px;
            display: block;
            overflow-x: auto;
        }
        th, td {
            border: 1px solid \(border);
            padding: 8px 13px;
            text-align: left;
        }
        th {
            font-weight: 600;
            background-color: \(headerBg);
        }
        tr { background-color: \(bg); }
        tr:nth-child(2n) { background-color: \(stripeBg); }
        img {
            max-width: 100%;
            height: auto;
            border-radius: 4px;
        }
        hr {
            border: none;
            border-top: 1px solid \(border);
            margin: 24px 0;
        }
        .task-list { list-style: none; padding-left: 1.5em; }
        .task-list-item input[type="checkbox"] { margin-right: 0.5em; }
        del { text-decoration: line-through; color: \(fgSecondary); }
        """
    }

    // Editor pane colors derived from theme mode
    var editorBackground: NSColor {
        switch id {
        case "default-light": return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        case "default-dark": return NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0)
        case "solarized-light": return NSColor(red: 0.992, green: 0.965, blue: 0.890, alpha: 1.0)
        case "solarized-dark": return NSColor(red: 0.0, green: 0.169, blue: 0.212, alpha: 1.0)
        case "nord": return NSColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1.0)
        case "github": return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        default: return mode == .light ? .white : NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0)
        }
    }

    var editorTextColor: NSColor {
        switch id {
        case "default-light": return NSColor(red: 0.141, green: 0.161, blue: 0.180, alpha: 1.0)
        case "default-dark": return NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1.0)
        case "solarized-light": return NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1.0)
        case "solarized-dark": return NSColor(red: 0.514, green: 0.580, blue: 0.588, alpha: 1.0)
        case "nord": return NSColor(red: 0.847, green: 0.871, blue: 0.914, alpha: 1.0)
        case "github": return NSColor(red: 0.141, green: 0.161, blue: 0.184, alpha: 1.0)
        default: return mode == .light ? .black : .white
        }
    }

    var editorHeadingColor: NSColor {
        switch id {
        case "solarized-light", "solarized-dark": return NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1.0)
        case "nord": return NSColor(red: 0.533, green: 0.753, blue: 0.816, alpha: 1.0)
        default: return editorTextColor
        }
    }

    var editorLinkColor: NSColor {
        switch id {
        case "default-light": return NSColor(red: 0.012, green: 0.400, blue: 0.839, alpha: 1.0)
        case "default-dark": return NSColor(red: 0.345, green: 0.651, blue: 1.0, alpha: 1.0)
        case "solarized-light", "solarized-dark": return NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1.0)
        case "nord": return NSColor(red: 0.533, green: 0.753, blue: 0.816, alpha: 1.0)
        case "github": return NSColor(red: 0.035, green: 0.412, blue: 0.855, alpha: 1.0)
        default: return .linkColor
        }
    }

    var editorCodeBackground: NSColor {
        switch id {
        case "default-light": return NSColor(red: 0.965, green: 0.973, blue: 0.980, alpha: 1.0)
        case "default-dark": return NSColor(red: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)
        case "solarized-light": return NSColor(red: 0.933, green: 0.910, blue: 0.835, alpha: 1.0)
        case "solarized-dark": return NSColor(red: 0.027, green: 0.212, blue: 0.259, alpha: 1.0)
        case "nord": return NSColor(red: 0.231, green: 0.259, blue: 0.322, alpha: 1.0)
        case "github": return NSColor(red: 0.937, green: 0.945, blue: 0.957, alpha: 1.0)
        default: return mode == .light ? NSColor(white: 0.95, alpha: 1.0) : NSColor(white: 0.2, alpha: 1.0)
        }
    }
}
