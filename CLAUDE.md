# MarsEdit

Native macOS markdown editor with live preview. SwiftUI shell + AppKit text editing + WebKit preview. Targets macOS 13+, Swift 5.9. ~3K LOC.

## Build & run

The `.xcodeproj` is **generated** by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. Don't hand-edit the project file.

```sh
xcodegen generate          # after editing project.yml
open MarsEdit.xcodeproj
```

Only third-party dependency: `swift-markdown` (Apple, SwiftPM, declared in `project.yml`). No tests target. No CI.

## Layout

```
MarsEdit/
├── App/             @main, DocumentGroup, menu commands
├── Document/        ReferenceFileDocument
├── Models/          AppSettings, Theme, ViewMode, OutlineItem
├── Views/           SwiftUI views + NSViewRepresentable wrappers
├── Rendering/       Markdown → HTML, syntax highlighting, front matter, asset scheme
├── Export/          HTML and PDF exporters
├── Preferences/     Settings UI
└── Resources/Themes/  *.css for preview themes
```

## Data flow

```
text  ──>  MarkdownDocument  ──>  EditorView (NSTextView)
                              \
                               ──>  MarkdownRenderer  ──>  PreviewView (WKWebView)
                                                      \
                                                       ──>  HTMLExporter / PDFExporter
```

## File map

| File | Purpose |
| --- | --- |
| `App/MarsEditApp.swift` | `@main`, DocumentGroup, menu commands |
| `Document/MarkdownDocument.swift` | Plain-text doc; UTF-8 with ISO-8859-1 fallback |
| `Models/AppSettings.swift` | `@AppStorage` singleton — font, theme, view mode, appearance |
| `Models/Theme.swift` | Six built-in themes; CSS lookup in `Resources/Themes/` |
| `Models/ViewMode.swift` | split / editor-only / preview-only — persisted; defers WKWebView init |
| `Models/OutlineItem.swift` | Heading parser for the sidebar |
| `Views/ContentView.swift` | Layout, outline, export dialogs, toasts |
| `Views/EditorView.swift` | **Largest file.** NSTextView wrapper, IME-safe, debounced highlight, image drag-drop |
| `Views/PreviewView.swift` | WKWebView; HTML shell loaded once, body injected via JS |
| `Views/OutlineSidebar.swift` · `ToolbarView.swift` · `StatusBarView.swift` | UI chrome |
| `Rendering/MarkdownRenderer.swift` | swift-markdown visitor → sanitized HTML |
| `Rendering/SyntaxHighlighter.swift` | Regex-based NSTextView attributes; skips fenced code & front matter |
| `Rendering/FrontMatter.swift` | Minimal YAML-like parser, `---` / `...` delimiters at doc start |
| `Rendering/LocalAssetSchemeHandler.swift` | `marsedit-asset://` → local file resolver (preview only) |
| `Export/HTMLExporter.swift` · `Export/PDFExporter.swift` | Render + theme CSS → file |
| `Preferences/PreferencesView.swift` | Settings UI |

## Conventions & gotchas

- **XcodeGen.** Edit `project.yml`, then re-run `xcodegen generate`. Never edit the `.xcodeproj` directly.
- **NotificationCenter dispatch.** Format actions, view-mode cycling, export, scroll-to-heading, and toasts are posted as notifications (e.g. `.insertMarkdownFormat`, `.cycleViewMode`, `.exportHTML`, `.exportPDF`, `.scrollToHeading`, `.showToast`). Toolbar/menu post; `EditorView` / `ContentView` observe. `.insertMarkdownFormat` is a global notification, so `EditorView` must gate handling to the active editor in the key window (`ActiveMarkdownEditor` / first responder) to avoid formatting every open document. Search `NotificationCenter` to find handlers.
- **NSTextView, not SwiftUI `TextEditor`.** Chosen for IME, find bar, performance. Don't replace.
- **Debounced, scoped syntax highlighting (~150ms).** Must skip fenced code blocks and front matter regions. During IME composition (`textView.hasMarkedText()`) highlighting and updates are deferred — preserve this when changing the editor.
- **Preview HTML shell loads once.** Subsequent updates inject the body via JS to preserve scroll position. Don't reload on every keystroke.
- **Local images use `marsedit-asset://`.** `LocalAssetSchemeHandler` resolves relative paths against the document directory. Don't emit raw `file://` URLs in rendered HTML — the CSP allows `marsedit-asset:` (see `MarkdownRenderer.assetCSPPolicy`).
- **HTML output is sanitized.** `javascript:` / `vbscript:` blocked; `data:` restricted to whitelisted image MIME types. Preserve sanitization when extending the renderer.
- **Adding a theme.** Drop a CSS file in `MarsEdit/Resources/Themes/` and register it in `Theme.swift`.
- **Settings.** Persisted via `@AppStorage` (UserDefaults). No iCloud sync.
- **Image drag-drop.** Dropped images are saved as PNG into a sibling `Assets/` folder next to the document, and a relative markdown reference (`Assets/<filename>`) is inserted.

## What this project does NOT have

No tests target. No CI config. No localization beyond English. No plugin system. No iCloud sync. No networking beyond what the preview WebView naturally does.
