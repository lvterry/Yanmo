import SwiftUI

struct OutlineSidebar: View {
    let items: [OutlineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Outline")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if items.isEmpty {
                VStack {
                    Spacer()
                    Text("No headings found")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { item in
                            Button {
                                NotificationCenter.default.post(name: .scrollToHeading, object: item.range)
                            } label: {
                                Text(item.title)
                                    .font(fontForLevel(item.level))
                                    .foregroundStyle(item.level <= 2 ? .primary : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, CGFloat(item.indentLevel) * 12 + 12)
                                    .padding(.vertical, 4)
                                    .padding(.trailing, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
        .background(.ultraThinMaterial)
    }

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 13, weight: .bold)
        case 2: return .system(size: 12, weight: .semibold)
        case 3: return .system(size: 12, weight: .medium)
        default: return .system(size: 11, weight: .regular)
        }
    }
}
