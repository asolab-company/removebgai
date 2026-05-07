import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    let onOpenPaywall: () -> Void
    let onOpenSettings: () -> Void
    let onOpenEditor: (UIImage, HomeToolKind) -> Void
    @EnvironmentObject private var store: StoreKitManager
    @State private var isImageSelectionPresented = false
    @State private var selectedToolKind: HomeToolKind = .upload

    private let toolCards: [ToolCardModel] = [
        ToolCardModel(
            title: "Blur Background",
            subtitle: "Artistic depth effect",
            previewImage: FigmaAssets.bluer,
            kind: .blurBackground
        ),
        ToolCardModel(
            title: "AI Background",
            subtitle: "Replace background",
            previewImage: FigmaAssets.aiBg,
            kind: .aiBackground
        ),
        ToolCardModel(
            title: "Enhance Quality",
            subtitle: "Upscale & Sharpen",
            previewImage: FigmaAssets.quality,
            kind: .enhanceQuality
        ),
        ToolCardModel(
            title: "Remove Object",
            subtitle: "Erase unwanted object",
            previewImage: FigmaAssets.magic,
            kind: .removeObject
        )
    ]

    var body: some View {
        ZStack {
            content
                .blur(radius: isImageSelectionPresented ? 12 : 0)
                .disabled(isImageSelectionPresented)

            if isImageSelectionPresented {
                ImageSelectionOverlay(
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isImageSelectionPresented = false
                        }
                    },
                    onImageSelected: { image in
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isImageSelectionPresented = false
                        }
                        onOpenEditor(image, selectedToolKind)
                    }
                )
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isImageSelectionPresented)
        .navigationBarBackButtonHidden(true)
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                uploadCard
                    .padding(.horizontal, 18)
                    .padding(.top, 32)

                Text("AI Tools")
                    .font(AppTypography.semibold(20))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    ForEach(toolCards) { card in
                        toolCard(card)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            RemoteAssetImage(url: FigmaAssets.logo, contentMode: .fit)
                .frame(width: 32, height: 32)

            Text("Remove BG")
                .font(AppTypography.bold(24))
                .foregroundStyle(AppColors.primaryText)

            Spacer()

            if !store.isPremium {
                Button(action: onOpenPaywall) {
                    RemoteAssetImage(url: FigmaAssets.vip, contentMode: .fit)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Button(action: onOpenSettings) {
                RemoteAssetImage(url: FigmaAssets.settings, contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }

    private var uploadCard: some View {
        VStack(spacing: 16) {
            Text("Upload your picture to have\nthe background removed.")
                .font(AppTypography.medium(14))
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.center)

            PrimaryButton(title: "Upload Image", iconURL: FigmaAssets.add) {
                showImageSelection(for: .upload)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(AppColors.card)
        )
    }

    private func toolCard(_ card: ToolCardModel) -> some View {
        Button {
            showImageSelection(for: card.kind)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                RemoteAssetImage(url: card.previewImage, contentMode: .fit)
                    .frame(width: 284, height: 148)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(AppTypography.bold(16))
                            .foregroundStyle(AppColors.primaryText)
                        Text(card.subtitle)
                            .font(AppTypography.regular(14))
                            .foregroundStyle(AppColors.primaryText)
                    }

                    Spacer()

                    if card.kind.requiresPremium && !store.isPremium {
                        RemoteAssetImage(url: FigmaAssets.lock, contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 26)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(AppColors.card)
            )
        }
        .buttonStyle(.plain)
    }

    private func showImageSelection(for kind: HomeToolKind) {
        guard !kind.requiresPremium || store.isPremium else {
            onOpenPaywall()
            return
        }

        selectedToolKind = kind
        withAnimation(.easeInOut(duration: 0.22)) {
            isImageSelectionPresented = true
        }
    }
}

#Preview {
    HomeView(
        onOpenPaywall: {},
        onOpenSettings: {},
        onOpenEditor: { _, _ in }
    )
    .environmentObject(StoreKitManager())
}
