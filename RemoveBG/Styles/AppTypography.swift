import SwiftUI

enum AppTypography {
    static func heavy(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
    static func bold(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func semibold(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func medium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
    static func regular(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
}
