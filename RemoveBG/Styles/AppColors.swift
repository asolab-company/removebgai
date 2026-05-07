import SwiftUI

enum AppColors {
    static let background = Color(hex: "F3F3F3")
    static let primaryText = Color(hex: "222222")
    static let secondaryText = Color(hex: "939393")
    static let tertiaryText = Color(hex: "B1B1B1")
    static let primaryBlue = Color(hex: "0F70E6")
    static let white = Color.white
    static let black = Color.black
    static let card = Color.white
    static let overlayDark = Color(red: 54 / 255, green: 54 / 255, blue: 54 / 255).opacity(0.67)
    static let borderWhite20 = Color.white.opacity(0.2)
    static let glass = Color.white.opacity(0.46)
}

extension Color {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
