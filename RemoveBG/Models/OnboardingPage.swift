import Foundation

struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitleLines: [String]
    let buttonTitle: String
    let heroImage: String
}
