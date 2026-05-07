import SwiftUI

struct FeatureRow: View {
    let iconURL: String
    let title: String
    let subtitle: String
    let trailingText: String?

    var body: some View {
        HStack(spacing: 8) {
            RemoteAssetImage(url: iconURL, contentMode: .fit)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bold(14))
                    .foregroundStyle(AppColors.primaryText)
                Text(subtitle)
                    .font(AppTypography.regular(14))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let trailingText {
                Text(trailingText)
                    .font(AppTypography.regular(14))
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(AppColors.card)
        )
    }
}

#Preview {
    FeatureRow(
        iconURL: FigmaAssets.paywallItem1,
        title: "AI Background Removal",
        subtitle: "Instantly cut out subjects with high-precision AI.",
        trailingText: nil
    )
    .padding()
    .background(AppColors.background)
}
