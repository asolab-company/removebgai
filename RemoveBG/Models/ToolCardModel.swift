import Foundation

enum HomeToolKind: Hashable {
    case upload
    case blurBackground
    case aiBackground
    case enhanceQuality
    case removeObject
    case eraser

    var requiresPremium: Bool {
        switch self {
        case .upload, .eraser:
            return false
        case .blurBackground, .aiBackground, .enhanceQuality, .removeObject:
            return true
        }
    }
}

struct ToolCardModel: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let previewImage: String
    let kind: HomeToolKind
}
