import SwiftUI

struct SettingsRow: View {
    let iconURL: String
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            RemoteAssetImage(url: iconURL, contentMode: .fit)
                .frame(width: 34, height: 34)

            Text(title)
                .font(AppTypography.medium(16))
                .foregroundStyle(AppColors.primaryText)

            Spacer()

            RemoteAssetImage(url: FigmaAssets.arrow, contentMode: .fit)
                .frame(width: 20, height: 20)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(AppColors.card)
        )
    }
}

#Preview {
    SettingsRow(
        iconURL: FigmaAssets.set06,
        title: "Privacy"
    )
    .padding()
    .background(AppColors.background)
}
