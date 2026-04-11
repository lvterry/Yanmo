import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

final class MarkdownDocument: ReferenceFileDocument {
    typealias Snapshot = String

    @Published var text: String
    @Published var fileURL: URL?

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
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.count
    }

    func readingTime(wpm: Int) -> String {
        let minutes = max(1, wordCount / max(1, wpm))
        if minutes < 2 { return "< 1 min" }
        return "\(minutes) min"
    }

    var isLargeFile: Bool {
        text.utf8.count > 2_000_000
    }
}
