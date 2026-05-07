import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AccessView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)

            Spacer()
                .frame(height: 190)

            Image(FigmaAssets.camera)
                .resizable()
                .scaledToFit()
                .frame(width: 186, height: 186)

            Text("You did not provide access to your gallery.")
                .font(AppTypography.bold(16))
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.top, 24)

            Text("Without it, we cannot clean your gallery.")
                .font(AppTypography.regular(14))
                .foregroundStyle(AppColors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.top, 4)

            Spacer()

            PrimaryButton(title: "Provide access") {
                openAppSettings()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 83)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Text("Provide Access")
                .font(AppTypography.bold(20))
                .foregroundStyle(AppColors.primaryText)

            Spacer()
        }
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

#Preview {
    AccessView(onBack: {})
}
