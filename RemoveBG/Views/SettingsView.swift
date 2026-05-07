import SwiftUI
import StoreKit

struct SettingsView: View {
    let onBack: () -> Void
    let onOpenPaywall: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var store: StoreKitManager
    @State private var showingDeleteDataConfirmation = false
    @State private var settingsMessage: SettingsMessage?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(AppColors.primaryText)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Text("Settings")
                        .font(AppTypography.bold(20))
                        .foregroundStyle(AppColors.primaryText)

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)

                if !store.isPremium {
                    Button(action: onOpenPaywall) {
                        HStack(spacing: 4) {
                            Image(FigmaAssets.vip)
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .foregroundStyle(AppColors.white)
                                .frame(width: 32, height: 32)
                            (
                                Text("Go to ")
                                    .font(AppTypography.medium(16))
                                + Text("PRO")
                                    .font(AppTypography.bold(16))
                            )
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
                    .padding(.horizontal, 18)
                    .padding(.top, 32)
                }

                Text("Support & Legal")
                    .font(AppTypography.semibold(20))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, store.isPremium ? 32 : 24)

                VStack(spacing: 8) {
                    Button {
                        openURL(AppLinks.privacyPolicy)
                    } label: {
                        SettingsRow(iconURL: FigmaAssets.set06, title: "Privacy")
                    }
                    .buttonStyle(.plain)

                    Button {
                        openURL(AppLinks.termsOfUse)
                    } label: {
                        SettingsRow(iconURL: FigmaAssets.set03, title: "Terms and Conditions")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)

                Text("General")
                    .font(AppTypography.semibold(20))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    ShareLink(
                        item: AppLinks.appStore,
                        subject: Text(AppLinks.shareSubject),
                        message: Text(AppLinks.shareMessage)
                    ) {
                        SettingsRow(iconURL: FigmaAssets.set05, title: "Share app")
                    }
                    .buttonStyle(.plain)

                    Button {
                        requestReview()
                    } label: {
                        SettingsRow(iconURL: FigmaAssets.set02, title: "Rate Us")
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            await store.restorePurchases()
                        }
                    } label: {
                        SettingsRow(iconURL: FigmaAssets.set04, title: "Restore")
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingDeleteDataConfirmation = true
                    } label: {
                        SettingsRow(iconURL: FigmaAssets.set01, title: "Delete Data")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .confirmationDialog(
            "Delete Data?",
            isPresented: $showingDeleteDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Data", role: .destructive) {
                deleteUserData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local files, cache, and app settings from this device.")
        }
        .alert(item: $settingsMessage) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.body),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("StoreKit", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.errorMessage = nil
                }
            }
        )
    }

    private func deleteUserData() {
        do {
            try UserDataManager.deleteAllUserData()
            settingsMessage = SettingsMessage(
                title: "Data Deleted",
                body: "Your local app data has been removed from this device."
            )
        } catch {
            settingsMessage = SettingsMessage(
                title: "Could Not Delete Data",
                body: error.localizedDescription
            )
        }
    }
}

private struct SettingsMessage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

#Preview {
    SettingsView(
        onBack: {},
        onOpenPaywall: {}
    )
    .environmentObject(StoreKitManager())
}
