import SwiftUI
import AppKit

/// Wraps NSTextView in NSViewRepresentable for the Markdown source editor.
struct EditorView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    @EnvironmentObject var settings: AppSettings

    @Binding var cursorPosition: (line: Int, column: Int)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.imageDropDelegate = context.coordinator
        textView.setupDragTypes()

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // Set initial content
        textView.string = document.text
        applyTheme(textView: textView)
        context.coordinator.applySyntaxHighlighting()

        // Listen for format actions
        context.coordinator.formatObserver = NotificationCenter.default.addObserver(
            forName: .insertMarkdownFormat, object: nil, queue: .main
        ) { notification in
            guard let action = notification.object as? FormatAction else { return }
            context.coordinator.insertFormat(action)
        }

        // Listen for scroll-to-heading
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: .scrollToHeading, object: nil, queue: .main
        ) { notification in
            guard let range = notification.object as? NSRange else { return }
            textView.scrollRangeToVisible(range)
            textView.setSelectedRange(range)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }

        if textView.string != document.text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            let selectedRange = textView.selectedRange()
            textView.string = document.text
            textView.setSelectedRange(selectedRange)
            context.coordinator.isUpdating = false
        }

        applyTheme(textView: textView)

        if settings.wordWrap {
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
        }

        context.coordinator.applySyntaxHighlighting()
    }

    private func applyTheme(textView: NSTextView) {
        let theme = settings.currentTheme
        textView.backgroundColor = theme.editorBackground
        textView.insertionPointColor = theme.editorTextColor
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        var textView: MarkdownTextView?
        var scrollView: NSScrollView?
        var isUpdating = false
        var formatObserver: Any?
        var scrollObserver: Any?
        private var highlightWorkItem: DispatchWorkItem?

        init(_ parent: EditorView) {
            self.parent = parent
        }

        deinit {
            if let obs = formatObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = scrollObserver { NotificationCenter.default.removeObserver(obs) }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isUpdating else { return }
            isUpdating = true
            parent.document.text = textView.string
            isUpdating = false

            // Debounce syntax highlighting
            highlightWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.applySyntaxHighlighting()
            }
            highlightWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let text = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
            let lineNumber = text.substring(to: lineRange.location).components(separatedBy: "\n").count
            let column = selectedRange.location - lineRange.location + 1
            parent.cursorPosition = (lineNumber, column)
        }

        func applySyntaxHighlighting() {
            guard let textView = textView, let textStorage = textView.textStorage else { return }
            let theme = parent.settings.currentTheme
            let font = parent.settings.editorFont
            let highlighter = SyntaxHighlighter(theme: theme, font: font)

            textStorage.beginEditing()
            highlighter.highlight(textStorage)
            textStorage.endEditing()
        }

        func insertFormat(_ action: FormatAction) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            let selectedText = (textView.string as NSString).substring(with: selectedRange)

            let replacement: String
            if action.isLinePrefix {
                replacement = action.wrapPrefix + selectedText
            } else if selectedText.isEmpty {
                replacement = action.wrapPrefix + "text" + action.wrapSuffix
            } else {
                replacement = action.wrapPrefix + selectedText + action.wrapSuffix
            }

            textView.insertText(replacement, replacementRange: selectedRange)
        }
    }
}

// MARK: - MarkdownTextView (supports image drag-drop)

protocol ImageDropDelegate: AnyObject {
    func handleImageDrop(_ image: NSImage, at insertionPoint: Int)
    func handleImagePaste(_ image: NSImage)
}

extension EditorView.Coordinator: ImageDropDelegate {
    func handleImageDrop(_ image: NSImage, at insertionPoint: Int) {
        insertBase64Image(image, at: insertionPoint)
    }

    func handleImagePaste(_ image: NSImage) {
        guard let textView = textView else { return }
        insertBase64Image(image, at: textView.selectedRange().location)
    }

    private func insertBase64Image(_ image: NSImage, at location: Int) {
        guard let textView = textView,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let base64 = pngData.base64EncodedString()
        let markdown = "![](data:image/png;base64,\(base64))"

        // Warn if large
        if pngData.count > 500_000 {
            let sizeStr = String(format: "%.1f MB", Double(pngData.count) / 1_000_000)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: "Image is large (\(sizeStr)). Consider linking to an external file instead."
                )
            }
        }

        textView.insertText(markdown, replacementRange: NSRange(location: location, length: 0))
    }
}

extension Notification.Name {
    static let showToast = Notification.Name("showToast")
}

class MarkdownTextView: NSTextView {
    weak var imageDropDelegate: ImageDropDelegate?

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            imageDropDelegate?.handleImagePaste(image)
            return
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let supportedTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .fileURL]

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: ["public.image"]
        ]) as? [URL], let url = fileURLs.first {
            if let image = NSImage(contentsOf: url) {
                let point = convert(sender.draggingLocation, from: nil)
                let insertionPoint = characterIndexForInsertion(at: point)
                // Check file type
                let ext = url.pathExtension.lowercased()
                let supported = ["png", "jpg", "jpeg", "gif", "webp"]
                if supported.contains(ext) {
                    imageDropDelegate?.handleImageDrop(image, at: insertionPoint)
                    return true
                } else {
                    NotificationCenter.default.post(
                        name: .showToast,
                        object: "Format not supported. Use PNG, JPEG, GIF, or WebP."
                    )
                    return false
                }
            }
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first {
            let point = convert(sender.draggingLocation, from: nil)
            let insertionPoint = characterIndexForInsertion(at: point)
            imageDropDelegate?.handleImageDrop(image, at: insertionPoint)
            return true
        }

        return super.performDragOperation(sender)
    }

    func setupDragTypes() {
        registerForDraggedTypes([.fileURL, .png, .tiff, .string])
    }
}
