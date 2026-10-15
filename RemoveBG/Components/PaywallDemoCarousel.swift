import SwiftUI
struct PaywallDemoCarousel: View {
    let heroSize: CGFloat
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var selectedDemo: OnboardingDemo = .removeBackground
    @State private var isVisible = false

    private var canAutoAdvance: Bool {
        isVisible && scenePhase == .active && !voiceOverEnabled
    }

    var body: some View {
        ZStack {
            Color.clear
            OnboardingAnimatedHero(
                demo: selectedDemo,
                isActive: isVisible && !voiceOverEnabled,
                repeats: false
            )
            .id(selectedDemo)
            .transition(.opacity)
        }
        .frame(width: heroSize, height: heroSize)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let distance = value.translation
                    guard abs(distance.width) > abs(distance.height), abs(distance.width) >= 40 else { return }
                    advance(by: distance.width < 0 ? 1 : -1)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Feature preview")
        .accessibilityValue("\(selectedDemo.rawValue + 1) of 4: \(demoTitle(selectedDemo))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: advance(by: 1)
            case .decrement: advance(by: -1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("paywall.demo.carousel")
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedDemo = .removeBackground
                isVisible = true
            }
        }
        .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
        .onDisappear { isVisible = false }
        .task(id: PlaybackID(demo: selectedDemo, isPlaying: canAutoAdvance)) {
            guard canAutoAdvance else { return }
            let scheduledDemo = selectedDemo
            do {
                try await Task.sleep(for: OnboardingAnimatedHero.cycleDuration)
            } catch {
                return
            }
            guard !Task.isCancelled, canAutoAdvance, selectedDemo == scheduledDemo else { return }
            advance(by: 1)
        }
    }

    private func advance(by offset: Int) {
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.2 : 0.25)) {
            selectedDemo = selectedDemo.advanced(by: offset)
        }
    }

    private func demoTitle(_ demo: OnboardingDemo) -> String {
        switch demo {
        case .removeBackground: "Remove background"
        case .changeBackground: "Change background"
        case .professionalEditing: "Professional AI editing"
        case .create: "Create amazing photos"
        }
    }

    private struct PlaybackID: Equatable {
        let demo: OnboardingDemo
        let isPlaying: Bool
    }
}
