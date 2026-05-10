import SwiftUI
import AppKit
import Combine

/// Wraps NSTextView in NSViewRepresentable for the Markdown source editor.
struct EditorView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var session: DocumentSession

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

        // Subscribe to per-document session events. The session is scene-scoped
        // via `focusedSceneValue`, so menu commands target the active window's
        // session — no need to gate by key window here.
        context.coordinator.subscribe(to: session)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.parent = self

        var textWasSetExternally = false
        let isComposingText = textView.hasMarkedText()
        if textView.string != document.text && !context.coordinator.isUpdating && !isComposingText {
            context.coordinator.isUpdating = true
            let selectedRange = textView.selectedRange()
            textView.string = document.text
            textView.setSelectedRange(Self.clampedRange(selectedRange, upperBound: (textView.string as NSString).length))
            context.coordinator.isUpdating = false
            textWasSetExternally = true
        }

        if !isComposingText {
            applyTheme(textView: textView)
        }

        if let container = textView.textContainer, container.widthTracksTextView != settings.wordWrap {
            if settings.wordWrap {
                let width = scrollView.contentSize.width
                textView.isHorizontallyResizable = false
                container.widthTracksTextView = true
                container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                textView.frame.size.width = width
            } else {
                container.widthTracksTextView = false
                container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                textView.isHorizontallyResizable = true
            }
        }

        // Only re-highlight the whole document when something appearance-related changed
        // or the text was replaced from outside. Per-keystroke incremental highlighting
        // is handled in `textDidChange`.
        let currentThemeID = settings.currentTheme.id
        let currentFontKey = "\(settings.editorFont.fontName):\(settings.editorFont.pointSize)"
        let appearanceChanged = context.coordinator.lastAppliedThemeID != currentThemeID
            || context.coordinator.lastAppliedFontKey != currentFontKey
        if textWasSetExternally || appearanceChanged {
            if !isComposingText {
                context.coordinator.lastAppliedThemeID = currentThemeID
                context.coordinator.lastAppliedFontKey = currentFontKey
                context.coordinator.applySyntaxHighlighting()
            } else {
                context.coordinator.deferSyntaxHighlighting(in: nil)
            }
        }
        context.coordinator.handleFileURLChange()
    }

    private func applyTheme(textView: NSTextView) {
        let theme = settings.currentTheme
        let font = settings.editorFont
        textView.backgroundColor = theme.editorBackground
        textView.insertionPointColor = theme.editorTextColor
        // Seed font + typing attributes so newly typed characters render in the
        // editor font immediately, instead of waiting for the debounced syntax
        // pass to overwrite system-default attributes.
        textView.font = font
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: theme.editorTextColor,
            .paragraphStyle: Self.editorParagraphStyle,
        ]
    }

    private static let editorParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2.0
        return style
    }()

    private static func clampedRange(_ range: NSRange, upperBound: Int) -> NSRange {
        let location = min(max(0, range.location), upperBound)
        let maxLength = upperBound - location
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
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
        var sessionCancellable: AnyCancellable?
        var saveSheetObserver: Any?
        private var saveTimeoutWork: DispatchWorkItem?
        var pendingImageInsert: PendingImageInsert?
        var isWaitingForSave = false
        var lastAppliedThemeID: String?
        var lastAppliedFontKey: String?
        private var cachedHighlighter: SyntaxHighlighter?
        private var cachedHighlighterKey: String?
        private var highlightWorkItem: DispatchWorkItem?
        private var pendingEditedRange: NSRange?
        private var deferredHighlightRange: NSRange?

        init(_ parent: EditorView) {
            self.parent = parent
        }

        deinit {
            if let obs = saveSheetObserver { NotificationCenter.default.removeObserver(obs) }
            saveTimeoutWork?.cancel()
        }

        func subscribe(to session: DocumentSession) {
            sessionCancellable = session.events.sink { [weak self] event in
                switch event {
                case .format(let action):
                    self?.insertFormat(action)
                case .scrollTo(let range):
                    self?.scrollTo(range)
                case .cycleViewMode, .exportHTML, .exportPDF, .showToast:
                    break
                }
            }
        }

        private func scrollTo(_ range: NSRange) {
            guard let textView else { return }
            textView.scrollRangeToVisible(range)
            textView.setSelectedRange(range)
        }

        func handleFileURLChange() {
            guard let pending = pendingImageInsert, let fileURL = parent.fileURL else { return }
            saveTimeoutWork?.cancel()
            saveTimeoutWork = nil
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
            let editedRange = pendingEditedRange
            pendingEditedRange = nil

            if textView.hasMarkedText() {
                deferSyntaxHighlighting(in: editedRange)
                return
            }

            isUpdating = true
            parent.document.text = textView.string
            isUpdating = false

            // Debounce syntax highlighting; pass the accumulated edited range so we only
            // re-highlight the affected paragraph(s).
            scheduleSyntaxHighlighting(in: mergedHighlightRange(editedRange))
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
            guard !textView.hasMarkedText() else {
                deferSyntaxHighlighting(in: editedRange)
                return
            }

            let highlighter = currentHighlighter()
            textStorage.beginEditing()
            highlighter.highlight(textStorage, in: editedRange)
            textStorage.endEditing()
        }

        /// Returns a `SyntaxHighlighter` matching the current theme/font, building
        /// (and caching) a new one only when those inputs have changed. The
        /// highlighter is rebuilt rarely (theme/font change), but `highlight(_:in:)`
        /// is called on every keystroke after the debounce fires.
        private func currentHighlighter() -> SyntaxHighlighter {
            let theme = parent.settings.currentTheme
            let font = parent.settings.editorFont
            let key = "\(theme.id)|\(font.fontName)|\(font.pointSize)"
            if let cached = cachedHighlighter, cachedHighlighterKey == key {
                return cached
            }
            let highlighter = SyntaxHighlighter(
                theme: theme,
                font: font,
                paragraphStyle: EditorView.editorParagraphStyle
            )
            cachedHighlighter = highlighter
            cachedHighlighterKey = key
            return highlighter
        }

        func deferSyntaxHighlighting(in editedRange: NSRange?) {
            highlightWorkItem?.cancel()
            highlightWorkItem = nil
            if let editedRange {
                deferredHighlightRange = merged(deferredHighlightRange, editedRange)
            }
        }

        private func mergedHighlightRange(_ editedRange: NSRange?) -> NSRange? {
            defer { deferredHighlightRange = nil }
            return merged(deferredHighlightRange, editedRange)
        }

        private func scheduleSyntaxHighlighting(in editedRange: NSRange?) {
            highlightWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.applySyntaxHighlighting(in: editedRange)
            }
            highlightWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.syntaxHighlightDebounce, execute: work)
        }

        private func merged(_ lhs: NSRange?, _ rhs: NSRange?) -> NSRange? {
            switch (lhs, rhs) {
            case (nil, nil):
                return nil
            case (let range?, nil), (nil, let range?):
                return range
            case (let lhs?, let rhs?):
                return NSUnionRange(lhs, rhs)
            }
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
                self?.scheduleSaveCancellationTimeout()
            }
        }

        /// After the save sheet dismisses, SwiftUI may take a moment to push the
        /// new `fileURL` through to `parent`. If it does, `handleFileURLChange()`
        /// (called from `updateNSView`) cancels this timeout. If not, the user
        /// cancelled the save panel — clean up after a short grace period and
        /// surface a toast.
        private func scheduleSaveCancellationTimeout() {
            saveTimeoutWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isWaitingForSave else { return }
                self.pendingImageInsert = nil
                self.isWaitingForSave = false
                self.removeSaveSheetObserver()
                self.postToast("Save the document to insert images as linked files.")
            }
            saveTimeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
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
            parent.session.post(.showToast(message))
        }
    }
}

// MARK: - MarkdownTextView (supports image drag-drop)

protocol ImageDropDelegate: AnyObject {
    func handleImageDrop(_ image: NSImage, at insertionPoint: Int)
    func handleImagePaste(_ image: NSImage)
    func handleUnsupportedImageDrop()
}

extension EditorView.Coordinator: ImageDropDelegate {
    func handleImageDrop(_ image: NSImage, at insertionPoint: Int) {
        queueLinkedImageInsert(image, at: insertionPoint)
    }

    func handleImagePaste(_ image: NSImage) {
        guard let textView = textView else { return }
        queueLinkedImageInsert(image, at: textView.selectedRange().location)
    }

    func handleUnsupportedImageDrop() {
        postToast("Format not supported. Use PNG, JPEG, GIF, or WebP.")
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
                    imageDropDelegate?.handleUnsupportedImageDrop()
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
