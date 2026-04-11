import SwiftUI

@main
struct MarsEditApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document)
                .environmentObject(settings)
                .frame(minWidth: 700, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .textFormatting) {
                formatMenuCommands
            }
            CommandGroup(after: .toolbar) {
                viewMenuCommands
            }
            CommandGroup(replacing: .help) {}
            exportCommands
            CommandGroup(after: .windowArrangement) {
                Section {
                    Button("Increase Font Size") {
                        settings.increaseFontSize()
                    }
                    .keyboardShortcut("+", modifiers: .command)

                    Button("Decrease Font Size") {
                        settings.decreaseFontSize()
                    }
                    .keyboardShortcut("-", modifiers: .command)

                    Button("Reset Font Size") {
                        settings.resetFontSize()
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(settings)
        }
    }

    // MARK: - Format Menu

    @ViewBuilder
    private var formatMenuCommands: some View {
        Button("Bold") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.bold)
        }
        .keyboardShortcut("b", modifiers: .command)

        Button("Italic") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.italic)
        }
        .keyboardShortcut("i", modifiers: .command)

        Button("Inline Code") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.inlineCode)
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])

        Button("Insert Link") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.link)
        }
        .keyboardShortcut("k", modifiers: .command)

        Divider()

        Menu("Heading") {
            ForEach(1...3, id: \.self) { level in
                Button("H\(level)") {
                    NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.heading(level))
                }
            }
        }

        Button("Blockquote") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.blockquote)
        }

        Button("Horizontal Rule") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.horizontalRule)
        }

        Divider()

        Button("Ordered List") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.orderedList)
        }

        Button("Unordered List") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.unorderedList)
        }

        Button("Task List") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.taskList)
        }

        Divider()

        Button("Code Block") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.codeBlock)
        }

        Button("Strikethrough") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.strikethrough)
        }

        Button("Image") {
            NotificationCenter.default.post(name: .insertMarkdownFormat, object: FormatAction.image)
        }
    }

    // MARK: - View Menu

    @ViewBuilder
    private var viewMenuCommands: some View {
        Button("Toggle Toolbar") {
            settings.toolbarVisible.toggle()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])

        Button("Toggle Sidebar") {
            settings.sidebarVisible.toggle()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        Button("Cycle View Mode") {
            NotificationCenter.default.post(name: .cycleViewMode, object: nil)
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])

        Button("Toggle Synchronized Scroll") {
            settings.syncScrollEnabled.toggle()
        }
        .keyboardShortcut("y", modifiers: [.command, .shift])
    }

    // MARK: - Export

    private var exportCommands: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export to HTML…") {
                NotificationCenter.default.post(name: .exportHTML, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Export to PDF…") {
                NotificationCenter.default.post(name: .exportPDF, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }

}

// MARK: - Notification Names

extension Notification.Name {
    static let insertMarkdownFormat = Notification.Name("insertMarkdownFormat")
    static let cycleViewMode = Notification.Name("cycleViewMode")
    static let exportHTML = Notification.Name("exportHTML")
    static let exportPDF = Notification.Name("exportPDF")
    static let scrollToHeading = Notification.Name("scrollToHeading")
}

// MARK: - Format Actions

enum FormatAction {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case link
    case image
    case heading(Int)
    case blockquote
    case horizontalRule
    case orderedList
    case unorderedList
    case taskList

    var wrapPrefix: String {
        switch self {
        case .bold: return "**"
        case .italic: return "_"
        case .strikethrough: return "~~"
        case .inlineCode: return "`"
        case .codeBlock: return "```\n"
        case .link: return "["
        case .image: return "!["
        case .heading(let level): return String(repeating: "#", count: level) + " "
        case .blockquote: return "> "
        case .horizontalRule: return "\n---\n"
        case .orderedList: return "1. "
        case .unorderedList: return "- "
        case .taskList: return "- [ ] "
        }
    }

    var wrapSuffix: String {
        switch self {
        case .bold: return "**"
        case .italic: return "_"
        case .strikethrough: return "~~"
        case .inlineCode: return "`"
        case .codeBlock: return "\n```"
        case .link: return "](url)"
        case .image: return "](image_url)"
        default: return ""
        }
    }

    var isLinePrefix: Bool {
        switch self {
        case .heading, .blockquote, .horizontalRule, .orderedList, .unorderedList, .taskList:
            return true
        default:
            return false
        }
    }
}
