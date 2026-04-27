import SwiftUI
import AppKit

@main
struct MarsEditApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .environmentObject(settings)
                .frame(minWidth: 700, minHeight: 500)
        }
        .commands {
            SkillCommands()
            CommandGroup(replacing: .textFormatting) {
                formatMenuCommands
            }
            CommandGroup(after: .pasteboard) {
                findMenuCommands
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

    // MARK: - Find Menu
    //
    // NSTextView already handles `performFindPanelAction:` when `usesFindBar = true`
    // (set in EditorView.makeNSView). These menu items just need to forward the
    // standard tag-based action up the responder chain.

    @ViewBuilder
    private var findMenuCommands: some View {
        Section {
            Menu("Find") {
                Button("Find…") { Self.sendFindPanelAction(.showFindPanel) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find Next") { Self.sendFindPanelAction(.next) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { Self.sendFindPanelAction(.previous) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { Self.sendFindPanelAction(.setFindString) }
                    .keyboardShortcut("e", modifiers: .command)
                Divider()
                Button("Replace…") { Self.sendFindPanelAction(.replaceAll) }
                Button("Replace All") { Self.sendFindPanelAction(.replaceAll) }
                Button("Replace") { Self.sendFindPanelAction(.replace) }
                Button("Replace and Find") { Self.sendFindPanelAction(.replaceAndFind) }
            }
        }
    }

    /// Forwards a Find-menu action to the first responder via the standard
    /// AppKit `performFindPanelAction:` selector. Constructs an NSMenuItem with the
    /// appropriate tag because that's how the receiver discovers which action to run.
    private static func sendFindPanelAction(_ action: NSFindPanelAction) {
        let item = NSMenuItem()
        item.tag = Int(action.rawValue)
        NSApp.sendAction(#selector(FindPanelActionResponding.performFindPanelAction(_:)), to: nil, from: item)
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

// MARK: - Skill Template Commands

private struct SkillCommands: Commands {
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Skill") {
                newDocument {
                    MarkdownDocument(text: SkillTemplate.defaultText)
                }
            }
        }
    }
}

private enum SkillTemplate {
    static let defaultText = """
    ---
    name: my-skill
    description: Use this skill when [describe the task, file type, workflow, or domain that should trigger it].
    ---

    # Skill Name

    ## Purpose

    Replace this section with the specific capability this skill provides and the situations where Codex should use it.

    ## Workflow

    1. Identify the relevant input, files, or user request.
    2. Follow the task-specific steps for this skill.
    3. Validate the output before responding.

    ## References And Resources

    Add only resources that directly support the skill:

    - `references/` for detailed docs Codex should read only when needed.
    - `scripts/` for repeatable or fragile operations that should run deterministically.
    - `assets/` for templates, images, or files used in generated output.

    ## Validation

    Describe the checks Codex should run or the evidence it should inspect before considering the task complete.
    """
}

// Lightweight protocol that exposes the AppKit selector to `#selector` without
// pretending it's declared on NSResponder/NSText. NSTextView responds to this
// at runtime when `usesFindBar = true`.
@objc private protocol FindPanelActionResponding {
    func performFindPanelAction(_ sender: Any?)
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
