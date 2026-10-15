import Foundation

enum OnboardingDemo: Int, CaseIterable, Identifiable {
    case removeBackground, changeBackground, professionalEditing, create
    var id: Int { rawValue }

    func advanced(by offset: Int) -> Self {
        let count = Self.allCases.count
        let index = ((rawValue + offset) % count + count) % count
        return Self(rawValue: index) ?? .removeBackground
    }
}

struct OnboardingPage: Identifiable {
    var id: OnboardingDemo { demo }
    let title: String
    let subtitleLines: [String]
    let buttonTitle: String
    let demo: OnboardingDemo
}
