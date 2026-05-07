import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 8) {
                Image(FigmaAssets.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 182, height: 182)
                    .padding(.top, 220)

                Text("Remove BG")
                    .font(AppTypography.semibold(32))
                    .foregroundStyle(AppColors.primaryText)
                    .padding(.top, -8)

                Text("Change Your Background.\nChange Your Story.")
                    .font(AppTypography.regular(16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.tertiaryText)

                Spacer()
            }
            .padding(.horizontal, 18)
        }
    }
}

#Preview {
    LoadingView()
}
