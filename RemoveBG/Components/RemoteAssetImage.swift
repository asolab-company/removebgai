import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RemoteAssetImage: View {
    let url: String
    var contentMode: ContentMode = .fill
    var placeholderStyle: AssetPlaceholderStyle = .icon

    var body: some View {
        Group {
            if let localImage = localImage {
                localImage
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let remoteURL = URL(string: url), remoteURL.scheme?.hasPrefix("http") == true {
                AsyncImage(url: remoteURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var localImage: Image? {
        #if canImport(UIKit)
        if UIImage(named: url) != nil {
            return Image(url)
        }
        #endif
        return nil
    }

    @ViewBuilder
    private var placeholder: some View {
        switch placeholderStyle {
        case .photo:
            PhotoPlaceholder()
        case .icon:
            FallbackIcon(name: url)
        }
    }
}

enum AssetPlaceholderStyle {
    case icon
    case photo
}

struct PhotoPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: "E3E3E3"))

            Checkerboard()
                .opacity(0.55)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Image(systemName: "photo")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
        }
    }
}

private struct Checkerboard: View {
    private let columns = Array(repeating: GridItem(.fixed(14), spacing: 0), count: 16)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<256, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? Color.white : Color(hex: "D8D8D8"))
                    .frame(width: 14, height: 14)
            }
        }
    }
}

struct FallbackIcon: View {
    let name: String

    var body: some View {
        Group {
            if name == FigmaAssets.logo {
                LogoMark()
            } else if name == FigmaAssets.vip {
                VipMark()
            } else if name == FigmaAssets.loading {
                ProgressView()
                    .tint(AppColors.primaryBlue)
            } else {
                Image(systemName: symbolName)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
            }
        }
    }

    private var iconColor: Color {
        switch name {
        case FigmaAssets.settings, FigmaAssets.lock, FigmaAssets.paywallClose, FigmaAssets.arrow:
            return AppColors.secondaryText
        case FigmaAssets.add:
            return AppColors.white
        case FigmaAssets.camera, FigmaAssets.gallery:
            return AppColors.white
        default:
            return AppColors.primaryBlue
        }
    }

    private var symbolName: String {
        switch name {
        case FigmaAssets.add:
            return "plus.circle.fill"
        case FigmaAssets.settings:
            return "gearshape.fill"
        case FigmaAssets.lock:
            return "lock.fill"
        case FigmaAssets.bluer:
            return "drop.fill"
        case FigmaAssets.aiBg:
            return "photo.on.rectangle.angled"
        case FigmaAssets.quality:
            return "sparkles"
        case FigmaAssets.magic:
            return "wand.and.stars"
        case FigmaAssets.paywallClose:
            return "xmark"
        case FigmaAssets.paywallShield:
            return "shield"
        case FigmaAssets.paywallShieldTick:
            return "checkmark"
        case FigmaAssets.paywallItem1:
            return "sparkle"
        case FigmaAssets.paywallItem2:
            return "photo"
        case FigmaAssets.paywallItem3:
            return "wand.and.stars"
        case FigmaAssets.paywallItem4:
            return "diamond.fill"
        case FigmaAssets.arrow:
            return "chevron.right"
        case FigmaAssets.back:
            return "chevron.left"
        case FigmaAssets.send:
            return "paperplane.fill"
        case FigmaAssets.save:
            return "square.and.arrow.down"
        case FigmaAssets.change:
            return "arrow.triangle.2.circlepath"
        case FigmaAssets.check:
            return "checkmark"
        case FigmaAssets.camera:
            return "camera.fill"
        case FigmaAssets.gallery:
            return "photo.fill"
        case FigmaAssets.set01:
            return "trash.fill"
        case FigmaAssets.set02:
            return "star.fill"
        case FigmaAssets.set03:
            return "doc.text.fill"
        case FigmaAssets.set04:
            return "arrow.counterclockwise"
        case FigmaAssets.set05:
            return "square.and.arrow.up"
        case FigmaAssets.set06:
            return "lock.shield.fill"
        default:
            return "circle.fill"
        }
    }
}

struct LogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                layer(color: AppColors.primaryText, side: side)
                    .offset(y: -side * 0.13)
                layer(color: Color(hex: "888888"), side: side)
                layer(color: Color(hex: "C7C7C7"), side: side)
                    .offset(y: side * 0.13)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func layer(color: Color, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: side * 0.63, height: side * 0.13)
            .rotationEffect(.degrees(45), anchor: .center)
            .scaleEffect(x: 1.45, y: 0.7)
    }
}

private struct VipMark: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "diamond.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColors.primaryBlue)
                .padding(6)

            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AppColors.primaryBlue)
                .offset(x: 1, y: -1)
        }
    }
}

#Preview {
    RemoteAssetImage(url: FigmaAssets.logo, contentMode: .fit)
        .frame(width: 64, height: 64)
        .padding()
        .background(AppColors.background)
}
