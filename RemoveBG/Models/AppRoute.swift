import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct EditorRoute: Hashable {
    let id = UUID()
    let image: UIImage
    let toolKind: HomeToolKind

    static func == (lhs: EditorRoute, rhs: EditorRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct UploadCropRoute: Hashable {
    let id = UUID()
    let image: UIImage

    static func == (lhs: UploadCropRoute, rhs: UploadCropRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct UploadResultRoute: Hashable {
    let id = UUID()
    let originalImage: UIImage
    let resultImage: UIImage

    static func == (lhs: UploadResultRoute, rhs: UploadResultRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum AppRoute: Hashable {
    case paywall
    case settings
    case editor(EditorRoute)
    case uploadCrop(UploadCropRoute)
    case uploadResult(UploadResultRoute)
}
