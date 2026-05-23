import Foundation

/// Detects and parses a YAML-style front matter block at the very start of a
/// Markdown document. Intentionally minimal — handles the common
/// `key: value` form without pulling in a YAML dependency.
struct FrontMatter {
    struct Entry {
        let key: String?
        let value: String
        let indent: Int
    }

    let range: Range<String.Index>
    let entries: [Entry]

    private static let entryRegex = try! NSRegularExpression(
        pattern: "^\\s*([A-Za-z0-9_-]+)\\s*:\\s*(.*)$"
    )

    static func parse(_ source: String) -> FrontMatter? {
        guard let (range, inner) = locate(in: source) else { return nil }
        let entries = inner
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { parseLine(String($0)) }
        return FrontMatter(range: range, entries: entries)
    }

    static func stripping(_ source: String) -> String {
        guard let (range, _) = locate(in: source) else { return source }
        return String(source[range.upperBound...])
    }

    /// Returns the value for the first entry with the given key, if any.
    func value(for key: String) -> String? {
        entries.first { $0.key == key }?.value
    }

    // MARK: - Private

    private static func locate(in source: String) -> (Range<String.Index>, String)? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }

        var closingIndex: Int?
        for i in 1..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" || trimmed == "..." {
                closingIndex = i
                break
            }
        }
        guard let closing = closingIndex else { return nil }

        // Compute the substring range covering lines[0...closing] plus the
        // newline after the closing delimiter (if present).
        var cursor = source.startIndex
        var lineStarts: [String.Index] = [cursor]
        for line in lines.dropLast() {
            let remaining = source.distance(from: cursor, to: source.endIndex)
            cursor = source.index(cursor, offsetBy: min(line.count, remaining))
            if cursor < source.endIndex {
                cursor = source.index(after: cursor) // skip the \n
            }
            lineStarts.append(cursor)
        }

        let startIdx = source.startIndex
        let closingLineStart = lineStarts[closing]
        let closingRemaining = source.distance(from: closingLineStart, to: source.endIndex)
        var endIdx = source.index(closingLineStart, offsetBy: min(lines[closing].count, closingRemaining))
        if endIdx < source.endIndex {
            endIdx = source.index(after: endIdx) // include the trailing \n
        }

        let innerStart = lineStarts[1]
        let innerEnd = closingLineStart
        let inner = String(source[innerStart..<innerEnd])

        return (startIdx..<endIdx, inner)
    }

    private static func parseLine(_ line: String) -> Entry? {
        var indent = 0
        for ch in line {
            if ch == " " {
                indent += 1
            } else if ch == "\t" {
                indent += 4
            } else {
                break
            }
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        if let match = entryRegex.firstMatch(in: line, range: range), match.numberOfRanges == 3 {
            let key = nsLine.substring(with: match.range(at: 1))
            var value = nsLine.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            value = stripQuotes(value)
            return Entry(key: key, value: value, indent: indent)
        }
        return Entry(key: nil, value: trimmed, indent: indent)
    }

    private static func stripQuotes(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        let first = s.first!
        let last = s.last!
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
