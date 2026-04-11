import Foundation

enum ViewMode: String, CaseIterable, Codable {
    case split
    case editorOnly
    case previewOnly

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
