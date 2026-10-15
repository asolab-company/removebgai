import SwiftUI
struct OnboardingAnimatedHero: View {
    static let cycleDuration: Duration = .seconds(7)
    let demo: OnboardingDemo
    let isActive: Bool
    var repeats = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var isPlaying: Bool { isActive && scenePhase == .active && !reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if isPlaying {
                    OnboardingHeroPlayback(demo: demo, reduceMotion: reduceMotion, repeats: repeats)
                } else {
                    OnboardingHeroFrame(demo: demo, reduceMotion: reduceMotion, values: .finished)
                }
            }
            .frame(width: 350, height: 350)
            .scaleEffect(min(proxy.size.width / 350, proxy.size.height / 350))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("onboarding.demo.\(demo.rawValue)")
        .allowsHitTesting(false)
    }

    private var accessibilityDescription: String {
        switch demo {
        case .removeBackground: "A portrait with its background selected and removed."
        case .changeBackground: "A portrait with a new color and sunset background."
        case .professionalEditing: "A sharp portrait with a softly blurred background."
        case .create: "An original photo and its finished background-free portrait."
        }
    }
}

private struct OnboardingHeroPlayback: View {
    let demo: OnboardingDemo
    let reduceMotion: Bool
    let repeats: Bool
    @State private var hasStarted = false

    var body: some View {
        let demo = demo
        let reduceMotion = reduceMotion
        Group {
            if repeats {
                OnboardingHeroFrame(demo: demo, reduceMotion: reduceMotion, values: DemoValues())
                    .keyframeAnimator(initialValue: DemoValues()) { _, values in
                        OnboardingHeroFrame(demo: demo, reduceMotion: reduceMotion, values: values)
                    } keyframes: { _ in
                        timeline
                    }
            } else {
                OnboardingHeroFrame(demo: demo, reduceMotion: reduceMotion, values: DemoValues())
                    .keyframeAnimator(initialValue: DemoValues(), trigger: hasStarted) { _, values in
                        OnboardingHeroFrame(demo: demo, reduceMotion: reduceMotion, values: values)
                    } keyframes: { _ in
                        timeline
                    }
                    .task { hasStarted = true }
            }
        }
    }

    @KeyframesBuilder<DemoValues>
    private var timeline: some Keyframes<DemoValues> {
        KeyframeTrack(\.selection) {
            LinearKeyframe(0, duration: 0.6)
            CubicKeyframe(1, duration: 0.3)
            LinearKeyframe(1, duration: 1.1)
            CubicKeyframe(0, duration: 0.3)
            LinearKeyframe(0, duration: 4.7)
        }
        KeyframeTrack(\.scan) {
            LinearKeyframe(-0.05, duration: 0.7)
            LinearKeyframe(1.05, duration: 1.3)
            LinearKeyframe(1.05, duration: 5)
        }
        KeyframeTrack(\.result) {
            LinearKeyframe(0, duration: 2)
            CubicKeyframe(1, duration: 1)
            if repeats {
                LinearKeyframe(1, duration: 3)
                CubicKeyframe(0, duration: 0.7)
                LinearKeyframe(0, duration: 0.3)
            } else {
                LinearKeyframe(1, duration: 4)
            }
        }
        KeyframeTrack(\.replacement) {
            LinearKeyframe(0, duration: 3.4)
            CubicKeyframe(1, duration: 0.8)
            if repeats {
                LinearKeyframe(1, duration: 1.8)
                CubicKeyframe(0, duration: 0.7)
                LinearKeyframe(0, duration: 0.3)
            } else {
                LinearKeyframe(1, duration: 2.8)
            }
        }
    }
}

private struct OnboardingHeroFrame: View {
    let demo: OnboardingDemo
    let reduceMotion: Bool
    let values: DemoValues

    var body: some View { hero(values: values) }

    @ViewBuilder
    private func hero(values: DemoValues) -> some View {
        if demo == .create {
            creationCollage(values: values)
        } else {
            VStack(spacing: 0) {
                photo(values: values)
                    .frame(width: 294, height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(8)

                HStack(spacing: 7) {
                    Image(systemName: values.result > 0.98 ? "checkmark.circle.fill" : "sparkles")
                        .foregroundStyle(AppColors.primaryBlue)
                    Text(status(values: values))
                        .foregroundStyle(AppColors.primaryText)
                        .contentTransition(.opacity)
                }
                .font(AppTypography.medium(13))
                .frame(height: 36)
                .padding(.bottom, 6)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 30))
            .overlay { RoundedRectangle(cornerRadius: 30).stroke(.white, lineWidth: 1) }
            .shadow(color: AppColors.primaryBlue.opacity(0.08), radius: 20, y: 10)
            .rotationEffect(.degrees(reduceMotion ? 0 : -3 + 3 * values.result))
        }
    }

    private func photo(values: DemoValues) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                switch demo {
                case .removeBackground:
                    TransparencyGrid()
                    asset("onboarding_beach", size: size)
                        .opacity(1 - values.result)
                    selection(cutout: "onboarding_portrait_cutout", size: size, values: values)
                    portrait(size: size)
                case .changeBackground:
                    Color(hex: "D6C9F3")
                    asset("onboarding_sunset", size: size)
                        .opacity(values.replacement)
                    asset("onboarding_change_before", size: size)
                        .opacity(1 - values.result)
                    selection(cutout: "onboarding_change_cutout", size: size, values: values)
                    asset("onboarding_change_cutout", size: size)
                case .professionalEditing, .create:
                    asset("onboarding_edit_before", size: size)
                    asset("onboarding_edit_before", size: size)
                        .blur(radius: 9)
                        .scaleEffect(1.08)
                        .opacity(values.result)
                    selection(cutout: "onboarding_edit_cutout", size: size, values: values)
                    asset("onboarding_edit_cutout", size: size)
                }

                Rectangle()
                    .fill(.white.opacity(0.85))
                    .frame(height: 2)
                    .shadow(color: AppColors.primaryBlue, radius: 8)
                    .offset(y: size.height * (values.scan - 0.5))
                    .opacity(values.selection)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    private func selection(cutout: String, size: CGSize, values: DemoValues) -> some View {
        AppColors.primaryBlue.opacity(0.4)
            .mask {
                ZStack {
                    Rectangle().fill(.white)
                    if demo == .removeBackground {
                        portrait(size: size).blendMode(.destinationOut)
                    } else {
                        asset(cutout, size: size).blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            .opacity(values.selection)
    }

    private func portrait(size: CGSize) -> some View {
        Image("onboarding_portrait_cutout")
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height, alignment: .bottom)
    }

    private func asset(_ name: String, size: CGSize) -> some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func creationCollage(values: DemoValues) -> some View {
        ZStack {
            photo(values: DemoValues())
                .frame(width: 205, height: 205)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(7)
                .background(.white, in: RoundedRectangle(cornerRadius: 28))
                .rotationEffect(.degrees(-9))
                .offset(x: -52, y: -51)

            ZStack {
                TransparencyGrid()
                Image("onboarding_edit_cutout").resizable().scaledToFill()
            }
            .frame(width: 195, height: 195)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(7)
            .background(.white, in: RoundedRectangle(cornerRadius: 28))
            .rotationEffect(.degrees(8))
            .offset(x: 51, y: 27 - (reduceMotion ? 0 : 8 * values.result))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)

            Label("Made with Remove BG", systemImage: "sparkles")
                .font(AppTypography.medium(13))
                .foregroundStyle(AppColors.primaryBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white, in: Capsule())
                .shadow(color: AppColors.primaryBlue.opacity(0.08), radius: 12, y: 6)
                .offset(y: 143)
        }
    }

    private func status(values: DemoValues) -> String {
        if values.selection > 0.1 { return "Selecting background…" }
        switch demo {
        case .removeBackground:
            return values.result > 0.98 ? "Background removed" : "Remove the background"
        case .changeBackground:
            return values.result > 0.98 ? (values.replacement > 0.5 ? "Try a new scene" : "Choose your color") : "Reimagine your background"
        case .professionalEditing:
            return values.result > 0.98 ? "Your subject, in focus" : "Add a professional blur"
        case .create:
            return "Made with Remove BG"
        }
    }

}
private struct DemoValues {
    var selection: Double = 0
    var scan: Double = -0.05
    var result: Double = 0
    var replacement: Double = 0

    static let finished = DemoValues(result: 1, replacement: 1)
}

private struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 16
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0..<Int(ceil(size.height / side)) {
                for column in 0..<Int(ceil(size.width / side)) where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)),
                        with: .color(Color(hex: "E1E4E9"))
                    )
                }
            }
        }
    }
}
