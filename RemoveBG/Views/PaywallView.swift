import SwiftUI

struct PaywallView: View {
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: StoreKitManager
    @State private var hasClosed = false

    var body: some View {
        GeometryReader { proxy in
            let layout = PaywallLayout(size: proxy.size)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: closeOnce) {
                            RemoteAssetImage(url: FigmaAssets.paywallClose, contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, layout.closeTop)

                    if layout.showsLogo {
                        RemoteAssetImage(url: FigmaAssets.logo, contentMode: .fit)
                            .frame(width: 58, height: 58)
                            .padding(.top, 12)
                    }

                    VStack(spacing: 0) {
                        Group {
                            Text("Go ").font(AppTypography.semibold(layout.titleSize))
                            + Text("Pro").font(AppTypography.heavy(layout.titleSize))
                            + Text(".").font(AppTypography.semibold(layout.titleSize))
                        }
                        Text("Create Without Limits.")
                            .font(AppTypography.semibold(layout.titleSize))
                    }
                    .foregroundStyle(AppColors.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, layout.titleTop)

                    Text("AI-powered background removal in seconds.\nNo skills needed.")
                        .font(AppTypography.regular(16))
                        .foregroundStyle(AppColors.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, layout.subtitleTop)

                    Text("Premium Features")
                        .font(AppTypography.semibold(16))
                        .foregroundStyle(AppColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, layout.featuresTitleTop)

                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            FeatureRow(
                                iconURL: FigmaAssets.paywallItem1,
                                title: "AI Background Removal",
                                subtitle: "Instantly cut out subjects with high-precision AI.",
                                trailingText: nil
                            )
                            FeatureRow(
                                iconURL: FigmaAssets.paywallItem2,
                                title: "Smart Background Replacement",
                                subtitle: "Swap or generate backgrounds in seconds.",
                                trailingText: nil
                            )
                            FeatureRow(
                                iconURL: FigmaAssets.paywallItem3,
                                title: "Pro AI Photo Enhancer",
                                subtitle: "Improve lighting, sharpness, and automatically.",
                                trailingText: nil
                            )
                        }

                        FeatureRow(
                            iconURL: FigmaAssets.paywallItem4,
                            title: "Annual Access",
                            subtitle: store.annualSubtitleText,
                            trailingText: store.monthlyPriceText
                        )
                        .padding(.top, layout.priceTop)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                    HStack(spacing: 6) {
                        ZStack {
                            RemoteAssetImage(url: FigmaAssets.paywallShield, contentMode: .fit)
                            RemoteAssetImage(url: FigmaAssets.paywallShieldTick, contentMode: .fit)
                                .frame(width: 5, height: 8)
                        }
                        .frame(width: 20, height: 20)
                        Text("Cancel Anytime")
                            .font(AppTypography.semibold(12))
                            .foregroundStyle(AppColors.primaryBlue)
                    }
                    .padding(.top, 16)

                    PrimaryButton(title: "Next") {
                        Task {
                            let didPurchase = await store.purchaseAnnual()
                            if didPurchase || store.isPremium {
                                closeOnce()
                            }
                        }
                    }
                    .disabled(store.isPurchasing)
                    .opacity(store.isPurchasing ? 0.72 : 1)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                    legalFooter
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                }
            }
            .background(AppColors.background.ignoresSafeArea())
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await store.loadProducts()
        }
        .alert("StoreKit", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var legalFooter: some View {
        HStack {
            Button("Privacy Policy") {
                openURL(AppLinks.privacyPolicy)
            }

            Spacer()

            Button("Restore") {
                Task {
                    await store.restorePurchases()
                }
            }

            Spacer()

            Button("Terms of Use") {
                openURL(AppLinks.termsOfUse)
            }
        }
        .font(AppTypography.medium(12))
        .foregroundStyle(AppColors.tertiaryText)
        .buttonStyle(.plain)
        .padding(.horizontal, 30)
    }

    private func closeOnce() {
        guard !hasClosed else { return }
        hasClosed = true
        onClose()
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
}

private struct PaywallLayout {
    let size: CGSize

    private var isCompactHeight: Bool {
        size.height <= 700
    }

    var showsLogo: Bool {
        !isCompactHeight
    }

    var titleSize: CGFloat {
        isCompactHeight ? 26 : 32
    }

    var closeTop: CGFloat {
        isCompactHeight ? 14 : 18
    }

    var titleTop: CGFloat {
        isCompactHeight ? 10 : 16
    }

    var subtitleTop: CGFloat {
        isCompactHeight ? 12 : 16
    }

    var featuresTitleTop: CGFloat {
        isCompactHeight ? 18 : 24
    }

    var priceTop: CGFloat {
        isCompactHeight ? 18 : 24
    }
}

#Preview {
    PaywallView(onClose: {})
        .environmentObject(StoreKitManager())
}
