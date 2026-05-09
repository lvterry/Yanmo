import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

final class MarkdownDocument: ReferenceFileDocument {
    typealias Snapshot = String

    @Published var text: String {
        didSet { cachedWordCount = nil }
    }

    /// Lazily-computed cache for `wordCount`. The status bar reads `wordCount`
    /// (and `readingTime(wpm:)` reads it twice more) on every body recompute,
    /// so without caching we'd walk the whole document several times per
    /// keystroke.
    private var cachedWordCount: Int?

    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown] }

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Attempt UTF-8 first, fall back to best-effort
        if let content = String(data: data, encoding: .utf8) {
            self.text = content
        } else if let content = String(data: data, encoding: .isoLatin1) {
            self.text = content
            // Non-UTF-8 file opened with fallback encoding
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = snapshot.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: - Document Statistics

    var wordCount: Int {
        if let cached = cachedWordCount { return cached }
        let count = Self.computeWordCount(of: text)
        cachedWordCount = count
        return count
    }

    func readingTime(wpm: Int) -> String {
        let count = wordCount
        guard count > 0 else { return "< 1 min" }
        let effectiveWPM = max(1, wpm)
        let minutes = (count + effectiveWPM - 1) / effectiveWPM
        return "\(minutes) min"
    }

    var isLargeFile: Bool {
        text.utf8.count > 2_000_000
    }

    /// Single-pass scalar walk: counts whitespace-separated runs without
    /// allocating an intermediate `[Substring]` (the previous
    /// `components(separatedBy:).filter` allocated one entry per word, which
    /// pressured the allocator on multi-MB documents).
    private static func computeWordCount(of text: String) -> Int {
        let separators = CharacterSet.whitespacesAndNewlines
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if separators.contains(scalar) {
                if inWord {
                    count += 1
                    inWord = false
                }
            } else {
                inWord = true
            }
        }
        if inWord { count += 1 }
        return count
    }
}
