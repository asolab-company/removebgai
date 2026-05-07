import SwiftUI

struct PrimaryButton: View {
    let title: String
    var iconURL: String? = nil
    var systemIcon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconURL {
                    RemoteAssetImage(url: iconURL, contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else if let systemIcon {
                    Circle()
                        .fill(AppColors.white.opacity(0.14))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: systemIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.white)
                        )
                }
                Text(title)
                    .font(AppTypography.medium(16))
                    .foregroundStyle(AppColors.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(AppColors.primaryBlue)
                    .shadow(color: AppColors.primaryBlue.opacity(0.38), radius: 4, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("With Icon") {
    PrimaryButton(title: "Upload Image", iconURL: FigmaAssets.add, action: {})
        .padding()
        .background(AppColors.background)
}

#Preview("Text Only") {
    PrimaryButton(title: "Next", action: {})
        .padding()
        .background(AppColors.background)
}
