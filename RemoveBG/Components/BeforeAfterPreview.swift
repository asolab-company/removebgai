import SwiftUI

enum PreviewLayout {
    case tool
    case onboarding1
    case onboarding2
    case onboarding3
    case onboarding4
}

struct BeforeAfterPreview: View {
    let beforeImage: String
    let afterImage: String
    let centerIcon: String
    var large: Bool = false
    var layout: PreviewLayout = .tool

    private var cardSize: CGSize {
        isOnboarding ? .init(width: 202.3, height: 202) : .init(width: 134.84, height: 134.65)
    }

    private var canvasSize: CGSize {
        isOnboarding ? .init(width: 393, height: 390) : .init(width: 284, height: 148)
    }

    private var captionFontSize: CGFloat { isOnboarding ? 18 : 12 }
    private var captionSize: CGSize { isOnboarding ? .init(width: 92.8, height: 34) : .init(width: 60, height: 22) }
    private var cardRadius: CGFloat { isOnboarding ? 24 : 16 }
    private var isOnboarding: Bool { large || layout != .tool }

    private var beforePosition: CGPoint {
        switch layout {
        case .tool:
            return CGPoint(x: 74, y: 74)
        case .onboarding1:
            return CGPoint(x: 123.15, y: 204.1)
        case .onboarding2:
            return CGPoint(x: 246.15, y: 204.1)
        case .onboarding3:
            return CGPoint(x: 124.15, y: 204.1)
        case .onboarding4:
            return CGPoint(x: 253.15, y: 198.1)
        }
    }

    private var afterPosition: CGPoint {
        switch layout {
        case .tool:
            return CGPoint(x: 210, y: 74)
        case .onboarding1:
            return CGPoint(x: 271.15, y: 315)
        case .onboarding2:
            return CGPoint(x: 147.15, y: 316)
        case .onboarding3:
            return CGPoint(x: 268.15, y: 314)
        case .onboarding4:
            return CGPoint(x: 141.15, y: 319)
        }
    }

    private var badgePosition: CGPoint {
        switch layout {
        case .tool:
            return CGPoint(x: 142, y: 101)
        case .onboarding1:
            return CGPoint(x: 321, y: 333)
        case .onboarding2:
            return CGPoint(x: 65, y: 317)
        case .onboarding3:
            return CGPoint(x: 317, y: 330)
        case .onboarding4:
            return CGPoint(x: 53, y: 322)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            card(image: beforeImage, caption: "before", rotation: -6)
                .position(beforePosition)

            card(image: afterImage, caption: "after", rotation: 6)
                .position(afterPosition)

            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(AppColors.glass)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(AppColors.white, lineWidth: 1)
                    )
                RemoteAssetImage(url: centerIcon, contentMode: .fit)
                    .frame(width: isOnboarding ? 16 : 16, height: isOnboarding ? 16 : 16)
            }
            .frame(width: 40, height: 40)
            .position(badgePosition)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func card(image: String, caption: String, rotation: Double) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(AppColors.white)
                .overlay(
                    RemoteAssetImage(url: image, placeholderStyle: .photo)
                        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardRadius)
                        .stroke(AppColors.borderWhite20, lineWidth: isOnboarding ? 1.5 : 1)
                )

            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                .fill(AppColors.overlayDark)
                .frame(width: captionSize.width, height: captionSize.height)
                .overlay(
                    Text(caption)
                        .font(AppTypography.bold(captionFontSize))
                        .foregroundStyle(AppColors.white)
                )
                .offset(y: isOnboarding ? -2 : -1)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .rotationEffect(.degrees(rotation))
    }
}

#Preview("Card") {
    BeforeAfterPreview(
        beforeImage: FigmaAssets.homeBlurBefore,
        afterImage: FigmaAssets.homeBlurAfter,
        centerIcon: FigmaAssets.bluer
    )
    .padding()
    .background(AppColors.background)
}

#Preview("Large") {
    BeforeAfterPreview(
        beforeImage: FigmaAssets.onboarding1Before,
        afterImage: FigmaAssets.onboarding1After,
        centerIcon: FigmaAssets.quality,
        large: true
    )
    .padding()
    .background(AppColors.background)
}
