import SwiftUI

struct StatusBarView: View {
    @ObservedObject var document: MarkdownDocument
    @EnvironmentObject var settings: AppSettings

    let cursorPosition: (line: Int, column: Int)

    var body: some View {
        HStack(spacing: 16) {
            // Word count
            Text("\(document.wordCount) words")

            Divider().frame(height: 12)

            // Reading time
            Text(document.readingTime(wpm: settings.readingSpeedWPM))

            Divider().frame(height: 12)

            // Cursor position
            Text("Ln \(cursorPosition.line), Col \(cursorPosition.column)")

            Spacer()

            // Encoding
            Text("UTF-8")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
