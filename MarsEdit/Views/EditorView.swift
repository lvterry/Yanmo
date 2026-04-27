import SwiftUI
import AppKit

/// Wraps NSTextView in NSViewRepresentable for the Markdown source editor.
struct EditorView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
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
        context.coordinator.parent = self

        var textWasSetExternally = false
        if textView.string != document.text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            let selectedRange = textView.selectedRange()
            textView.string = document.text
            textView.setSelectedRange(selectedRange)
            context.coordinator.isUpdating = false
            textWasSetExternally = true
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

        // Only re-highlight the whole document when something appearance-related changed
        // or the text was replaced from outside. Per-keystroke incremental highlighting
        // is handled in `textDidChange`.
        let currentThemeID = settings.currentTheme.id
        let currentFontKey = "\(settings.editorFont.fontName):\(settings.editorFont.pointSize)"
        let appearanceChanged = context.coordinator.lastAppliedThemeID != currentThemeID
            || context.coordinator.lastAppliedFontKey != currentFontKey
        if textWasSetExternally || appearanceChanged {
            context.coordinator.lastAppliedThemeID = currentThemeID
            context.coordinator.lastAppliedFontKey = currentFontKey
            context.coordinator.applySyntaxHighlighting()
        }
        context.coordinator.handleFileURLChange()
    }

    private func applyTheme(textView: NSTextView) {
        let theme = settings.currentTheme
        textView.backgroundColor = theme.editorBackground
        textView.insertionPointColor = theme.editorTextColor
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        struct PendingImageInsert {
            let image: NSImage
            let insertionPoint: Int
        }

        private static let syntaxHighlightDebounce: TimeInterval = 0.15

        var parent: EditorView
        var textView: MarkdownTextView?
        var scrollView: NSScrollView?
        var isUpdating = false
        var formatObserver: Any?
        var scrollObserver: Any?
        var saveSheetObserver: Any?
        var pendingImageInsert: PendingImageInsert?
        var isWaitingForSave = false
        var lastAppliedThemeID: String?
        var lastAppliedFontKey: String?
        private var highlightWorkItem: DispatchWorkItem?
        private var pendingEditedRange: NSRange?

        init(_ parent: EditorView) {
            self.parent = parent
        }

        deinit {
            if let obs = formatObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = scrollObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = saveSheetObserver { NotificationCenter.default.removeObserver(obs) }
        }

        func handleFileURLChange() {
            guard let pending = pendingImageInsert, let fileURL = parent.fileURL else { return }
            insertLinkedImage(pending.image, at: pending.insertionPoint, fileURL: fileURL)
            pendingImageInsert = nil
            isWaitingForSave = false
            removeSaveSheetObserver()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Track the range affected by this edit so the debounced highlighter can scope
            // its work. Accumulate across rapid edits within the debounce window.
            let newLength = (replacementString as NSString?)?.length ?? 0
            let edit = NSRange(location: affectedCharRange.location, length: newLength)
            if let existing = pendingEditedRange {
                pendingEditedRange = NSUnionRange(existing, edit)
            } else {
                pendingEditedRange = edit
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isUpdating else { return }
            isUpdating = true
            parent.document.text = textView.string
            isUpdating = false

            // Debounce syntax highlighting; pass the accumulated edited range so we only
            // re-highlight the affected paragraph(s).
            highlightWorkItem?.cancel()
            let editedRange = pendingEditedRange
            pendingEditedRange = nil
            let work = DispatchWorkItem { [weak self] in
                self?.applySyntaxHighlighting(in: editedRange)
            }
            highlightWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.syntaxHighlightDebounce, execute: work)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let text = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
            let lineNumber = text.substring(to: lineRange.location).components(separatedBy: "\n").count
            let column = selectedRange.location - lineRange.location + 1
            DispatchQueue.main.async {
                self.parent.cursorPosition = (lineNumber, column)
            }
        }

        func applySyntaxHighlighting(in editedRange: NSRange? = nil) {
            guard let textView = textView, let textStorage = textView.textStorage else { return }
            let theme = parent.settings.currentTheme
            let font = parent.settings.editorFont
            let highlighter = SyntaxHighlighter(theme: theme, font: font)

            textStorage.beginEditing()
            highlighter.highlight(textStorage, in: editedRange)
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

        private func beginSaveForPendingImage() {
            guard !isWaitingForSave else { return }
            isWaitingForSave = true
            installSaveSheetObserver()

            let didSend = NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
            if !didSend {
                pendingImageInsert = nil
                isWaitingForSave = false
                removeSaveSheetObserver()
                postToast("Unable to save the document before inserting the image.")
            }
        }

        private func installSaveSheetObserver() {
            guard saveSheetObserver == nil, let window = textView?.window else { return }
            saveSheetObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndSheetNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.resolvePendingSaveOutcome(attemptsRemaining: 15)
            }
        }

        private func resolvePendingSaveOutcome(attemptsRemaining: Int) {
            guard isWaitingForSave else { return }
            if parent.fileURL != nil { return }
            guard attemptsRemaining > 0 else {
                pendingImageInsert = nil
                isWaitingForSave = false
                removeSaveSheetObserver()
                postToast("Save the document to insert images as linked files.")
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.resolvePendingSaveOutcome(attemptsRemaining: attemptsRemaining - 1)
            }
        }

        private func removeSaveSheetObserver() {
            if let observer = saveSheetObserver {
                NotificationCenter.default.removeObserver(observer)
                saveSheetObserver = nil
            }
        }

        private func insertLinkedImage(_ image: NSImage, at location: Int, fileURL: URL) {
            do {
                let relativePath = try LinkedImageWriter.write(image: image, nextTo: fileURL)
                let markdown = "![](\(relativePath))"
                let insertionLocation = min(location, textView?.string.utf16.count ?? location)
                textView?.insertText(markdown, replacementRange: NSRange(location: insertionLocation, length: 0))
            } catch {
                postToast(error.localizedDescription)
            }
        }

        private func postToast(_ message: String) {
            NotificationCenter.default.post(name: .showToast, object: message)
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
        queueLinkedImageInsert(image, at: insertionPoint)
    }

    func handleImagePaste(_ image: NSImage) {
        guard let textView = textView else { return }
        queueLinkedImageInsert(image, at: textView.selectedRange().location)
    }

    private func queueLinkedImageInsert(_ image: NSImage, at location: Int) {
        if let fileURL = parent.fileURL {
            insertLinkedImage(image, at: location, fileURL: fileURL)
            return
        }

        pendingImageInsert = PendingImageInsert(image: image, insertionPoint: location)
        beginSaveForPendingImage()
    }
}

private enum LinkedImageWriter {
    static func write(image: NSImage, nextTo fileURL: URL) throws -> String {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageWriteError.encodingFailed
        }

        let documentDirectory = fileURL.deletingLastPathComponent()
        let assetsDirectory = documentDirectory.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let suffix = UUID().uuidString.prefix(4).lowercased()
        let filename = "image-\(timestamp)-\(suffix).png"

        let fileOnDisk = assetsDirectory.appendingPathComponent(filename)
        try pngData.write(to: fileOnDisk, options: .atomic)

        return "Assets/\(filename)"
    }
}

private enum ImageWriteError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Unable to encode the image for insertion."
        }
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
