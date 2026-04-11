import SwiftUI

struct FindReplaceView: View {
    @Binding var isVisible: Bool
    @Binding var showReplace: Bool

    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var caseSensitive = false
    @State private var wholeWord = false
    @State private var useRegex = false
    @State private var matchCount = 0
    @State private var currentMatch = 0

    let onFind: (String, FindOptions) -> Int
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onReplace: (String) -> Void
    let onReplaceAll: (String) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                // Search field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))

                    TextField("Find", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { performSearch() }
                        .onChange(of: searchText) { _ in performSearch() }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                .frame(minWidth: 200)

                // Match count
                if !searchText.isEmpty {
                    Text(matchCount > 0 ? "\(currentMatch)/\(matchCount)" : "No results")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 60)
                }

                // Navigation buttons
                Button { onFindPrevious() } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)

                Button { onFindNext() } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)

                Divider().frame(height: 16)

                // Options
                Toggle("Aa", isOn: $caseSensitive)
                    .toggleStyle(.button)
                    .font(.system(size: 10, weight: .medium))
                    .help("Case Sensitive")
                    .onChange(of: caseSensitive) { _ in performSearch() }

                Toggle("W", isOn: $wholeWord)
                    .toggleStyle(.button)
                    .font(.system(size: 10, weight: .medium))
                    .help("Whole Word")
                    .onChange(of: wholeWord) { _ in performSearch() }

                Toggle(".*", isOn: $useRegex)
                    .toggleStyle(.button)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .help("Regular Expression")
                    .onChange(of: useRegex) { _ in performSearch() }

                Spacer()

                Button {
                    isVisible = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            // Replace row
            if showReplace {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))

                        TextField("Replace", text: $replaceText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                    .frame(minWidth: 200)

                    Button("Replace") {
                        onReplace(replaceText)
                    }
                    .disabled(matchCount == 0)

                    Button("Replace All") {
                        onReplaceAll(replaceText)
                    }
                    .disabled(matchCount == 0)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func performSearch() {
        let options = FindOptions(
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            useRegex: useRegex
        )
        matchCount = onFind(searchText, options)
        currentMatch = matchCount > 0 ? 1 : 0
    }
}

struct FindOptions {
    var caseSensitive: Bool
    var wholeWord: Bool
    var useRegex: Bool
}
