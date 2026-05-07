import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var currentIndex = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Remove Background Instantly",
            subtitleLines: ["AI-powered background removal in seconds.", "No skills needed."],
            buttonTitle: "Next",
            heroImage: FigmaAssets.onboarding1Background
        ),
        OnboardingPage(
            title: "Change Background Easily",
            subtitleLines: ["Replace your background", "with colors, gradients,", "or your own photos."],
            buttonTitle: "Next",
            heroImage: FigmaAssets.onboarding2Background
        ),
        OnboardingPage(
            title: "Professional\nAI Editing Tools",
            subtitleLines: ["Blur backgrounds, apply", "filters, and enhance your", "images with AI."],
            buttonTitle: "Next",
            heroImage: FigmaAssets.onboarding3Background
        ),
        OnboardingPage(
            title: "Start Creating\nAmazing Photos",
            subtitleLines: ["Join millions of users creating", "stunning images", "with Remove BG."],
            buttonTitle: "Get Started",
            heroImage: FigmaAssets.onboarding4Background
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            let layout = OnboardingLayout(size: proxy.size)

            ZStack {
                AppColors.background.ignoresSafeArea()

                TabView(selection: $currentIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page, layout: layout)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomControls(layout: layout)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func bottomControls(layout: OnboardingLayout) -> some View {
        VStack(spacing: 0) {
            Spacer()

            PrimaryButton(title: pages[currentIndex].buttonTitle) {
                if currentIndex < pages.count - 1 {
                    withAnimation(.easeInOut) { currentIndex += 1 }
                } else {
                    onFinish()
                }
            }
            .padding(.horizontal, 18)

            termsText
                .opacity(currentIndex == 0 ? 1 : 0)
                .padding(.top, layout.termsTop)
                .padding(.bottom, layout.termsBottom)
        }
    }

    private var termsText: some View {
        VStack(spacing: 0) {
            Text("By proceeding you accept")
                .foregroundStyle(AppColors.tertiaryText)

            HStack(spacing: 3) {
                Text("our")
                    .foregroundStyle(AppColors.tertiaryText)
                Button("Terms of Use") {
                    openURL(AppLinks.termsOfUse)
                }
                Text("and")
                    .foregroundStyle(AppColors.tertiaryText)
                Button("Privacy Policy") {
                    openURL(AppLinks.privacyPolicy)
                }
            }
            .foregroundStyle(AppColors.primaryBlue)
        }
        .font(AppTypography.medium(12))
        .buttonStyle(.plain)
        .multilineTextAlignment(.center)
        .frame(width: 260, height: 28)
    }

    private func pageView(_ page: OnboardingPage, layout: OnboardingLayout) -> some View {
        VStack(spacing: 0) {
            Image(page.heroImage)
                .resizable()
                .scaledToFit()
                .frame(width: layout.heroSize.width, height: layout.heroSize.height)
                .padding(.top, layout.heroTop)

            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? AppColors.primaryBlue : AppColors.tertiaryText)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 8)

            Text(page.title)
                .font(AppTypography.semibold(32))
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 332)
                .frame(minHeight: 76, alignment: .top)
                .padding(.top, layout.titleTop)

            Text(page.subtitleLines.joined(separator: "\n"))
                .font(AppTypography.regular(16))
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 277)
                .frame(minHeight: 57, alignment: .top)
                .padding(.top, layout.subtitleTop)

            Spacer(minLength: layout.bottomSpacer)
        }
    }
}

private struct OnboardingLayout {
    let size: CGSize

    private var isCompactHeight: Bool {
        size.height <= 700
    }

    var heroSize: CGSize {
        isCompactHeight
            ? CGSize(width: 300, height: 300)
            : CGSize(width: 393, height: 390)
    }

    var heroTop: CGFloat {
        isCompactHeight ? 16 : 28
    }

    var titleTop: CGFloat {
        isCompactHeight ? 24 : 32
    }

    var subtitleTop: CGFloat {
        isCompactHeight ? 12 : 16
    }

    var bottomSpacer: CGFloat {
        isCompactHeight ? 110 : 150
    }

    var termsTop: CGFloat {
        isCompactHeight ? 12 : 18
    }

    var termsBottom: CGFloat {
        isCompactHeight ? 20 : 30
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
