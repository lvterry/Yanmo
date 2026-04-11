import SwiftUI

struct ToolbarView: View {
    var body: some View {
        HStack(spacing: 2) {
            toolbarButton("Bold", icon: "bold", action: .bold)
            toolbarButton("Italic", icon: "italic", action: .italic)
            toolbarButton("Strikethrough", icon: "strikethrough", action: .strikethrough)

            Divider().frame(height: 20).padding(.horizontal, 4)

            Menu {
                Button("Heading 1") { postFormat(.heading(1)) }
                Button("Heading 2") { postFormat(.heading(2)) }
                Button("Heading 3") { postFormat(.heading(3)) }
            } label: {
                Label("Heading", systemImage: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 50)

            Divider().frame(height: 20).padding(.horizontal, 4)

            toolbarButton("Inline Code", icon: "chevron.left.forwardslash.chevron.right", action: .inlineCode)
            toolbarButton("Code Block", icon: "curlybraces", action: .codeBlock)

            Divider().frame(height: 20).padding(.horizontal, 4)

            toolbarButton("Link", icon: "link", action: .link)
            toolbarButton("Image", icon: "photo", action: .image)

            Divider().frame(height: 20).padding(.horizontal, 4)

            toolbarButton("Ordered List", icon: "list.number", action: .orderedList)
            toolbarButton("Unordered List", icon: "list.bullet", action: .unorderedList)
            toolbarButton("Task List", icon: "checklist", action: .taskList)

            Divider().frame(height: 20).padding(.horizontal, 4)

            toolbarButton("Blockquote", icon: "text.quote", action: .blockquote)
            toolbarButton("Horizontal Rule", icon: "minus", action: .horizontalRule)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func toolbarButton(_ title: String, icon: String, action: FormatAction) -> some View {
        Button {
            postFormat(action)
        } label: {
            Image(systemName: icon)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    private func postFormat(_ action: FormatAction) {
        NotificationCenter.default.post(name: .insertMarkdownFormat, object: action)
    }
}
