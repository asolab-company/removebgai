import SwiftUI

struct PaywallView: View {
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: StoreKitManager
    @State private var hasClosed = false

    var body: some View {
        GeometryReader { proxy in
            let layout = PaywallLayout(size: proxy.size)

            ScrollView {
                VStack(spacing: 0) {
                    PaywallDemoCarousel(heroSize: layout.heroSize)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .topLeading) {
                            Button(action: closeOnce) {
                                RemoteAssetImage(url: FigmaAssets.paywallClose, contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                        }
                        .padding(.top, layout.closeTop)

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

                        subscriptionRow
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
                            let didPurchase = await store.purchaseSubscription()
                            if didPurchase || store.isPremium {
                                closeOnce()
                            }
                        }
                    }
                    .disabled(!store.canPurchase)
                    .opacity(store.canPurchase ? 1 : 0.55)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                    legalFooter
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .background { AppColors.background.ignoresSafeArea() }
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

    @ViewBuilder
    private var subscriptionRow: some View {
        if let offer = store.subscriptionOffer {
            FeatureRow(
                iconURL: FigmaAssets.paywallItem4,
                title: offer.title,
                subtitle: offer.description,
                trailingText: offer.billingText
            )
            .accessibilityIdentifier("paywall.subscription.offer")
        } else {
            HStack(spacing: 12) {
                if store.isLoadingProducts || !store.hasLoadedProducts {
                    ProgressView()
                    Text("Loading subscription…")
                } else {
                    Text(store.productLoadingError ?? "Subscription unavailable")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Try again") {
                        Task { await store.loadProducts() }
                    }
                    .foregroundStyle(AppColors.primaryBlue)
                }
            }
            .font(AppTypography.regular(14))
            .foregroundStyle(AppColors.secondaryText)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: 32))
            .accessibilityIdentifier("paywall.subscription.unavailable")
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

    var heroSize: CGFloat {
        min(size.width - 36, isCompactHeight ? 210 : 250)
    }

    var closeTop: CGFloat {
        isCompactHeight ? 14 : 18
    }

    var featuresTitleTop: CGFloat {
        isCompactHeight ? 18 : 24
    }

    var priceTop: CGFloat {
        isCompactHeight ? 18 : 24
    }
}
