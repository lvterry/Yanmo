import AppKit
import SwiftUI

struct FontPickerButton: View {
    @Binding var fontName: String
    @Binding var fontSize: Double

    @StateObject private var bridge = FontPanelBridge()

    var body: some View {
        Button(action: openPanel) {
            Text(fontName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 160, alignment: .leading)
        }
        .onDisappear {
            if NSFontManager.shared.target as AnyObject === bridge {
                NSFontManager.shared.target = nil
            }
            NSFontPanel.shared.orderOut(nil)
        }
    }

    private func openPanel() {
        let current = NSFont(name: fontName, size: CGFloat(fontSize))
            ?? .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        bridge.currentFont = current
        bridge.onChange = { font in
            fontName = font.fontName
            fontSize = Double(font.pointSize)
        }
        let manager = NSFontManager.shared
        manager.target = bridge
        manager.setSelectedFont(current, isMultiple: false)
        NSFontPanel.shared.makeKeyAndOrderFront(nil)
    }
}

private final class FontPanelBridge: NSObject, ObservableObject {
    var currentFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var onChange: ((NSFont) -> Void)?

    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let new = manager.convert(currentFont)
        currentFont = new
        onChange?(new)
    }

    @objc func validModesForFontPanel(_ panel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }
}
