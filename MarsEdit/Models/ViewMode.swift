import Foundation

enum ViewMode: String, CaseIterable, Codable {
    case split
    case editorOnly
    case previewOnly

    static var defaultMode: ViewMode {
        // Avoid eager WKWebView creation on macOS 26+, where WebKit can log
        // IconRendering.framework binary.metallib format warnings at startup.
        if #available(macOS 26.0, *) {
            return .editorOnly
        }
        return .split
    }

    var next: ViewMode {
        switch self {
        case .split: return .editorOnly
        case .editorOnly: return .previewOnly
        case .previewOnly: return .split
        }
    }

    var label: String {
        switch self {
        case .split: return "Split View"
        case .editorOnly: return "Editor Only"
        case .previewOnly: return "Preview Only"
        }
    }
}
