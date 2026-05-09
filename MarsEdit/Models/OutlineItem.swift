import Foundation

struct OutlineItem: Identifiable {
    let id = UUID()
    let level: Int       // 1–6
    let title: String
    let range: NSRange   // location in source text

    var indentLevel: Int { level - 1 }
}

struct OutlineParser {
    static func parse(_ text: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        let nsText = text as NSString
        let length = nsText.length
        var lineStart = 0
        var activeFence: (marker: Character, length: Int)?

        while lineStart < length {
            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            // Content range excludes the newline character(s)
            var contentEnd = lineRange.location + lineRange.length
            while contentEnd > lineRange.location {
                let prev = contentEnd - 1
                let ch = nsText.character(at: prev)
                if ch == 0x0A || ch == 0x0D { // \n or \r
                    contentEnd = prev
                } else {
                    break
                }
            }
            let contentRange = NSRange(location: lineRange.location, length: contentEnd - lineRange.location)
            let line = nsText.substring(with: contentRange)

            // Advance past the full line (including newline) for the next iteration
            lineStart = lineRange.location + lineRange.length

            if let fence = codeFence(in: line) {
                if let active = activeFence {
                    if fence.marker == active.marker && fence.length >= active.length {
                        activeFence = nil
                    }
                } else {
                    activeFence = fence
                }
                continue
            }
            if activeFence != nil { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }

            var level = 0
            for char in trimmed {
                if char == "#" { level += 1 } else { break }
            }
            guard level >= 1, level <= 6 else { continue }

            let afterHashes = trimmed.dropFirst(level)
            guard afterHashes.first == " " || afterHashes.isEmpty else { continue }

            let title = afterHashes.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }

            items.append(OutlineItem(level: level, title: title, range: contentRange))
        }
        return items
    }

    private static func codeFence(in line: String) -> (marker: Character, length: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }

        var count = 0
        for char in trimmed {
            if char == marker {
                count += 1
            } else {
                break
            }
        }
        guard count >= 3 else { return nil }
        return (marker, count)
    }
}
