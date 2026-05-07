import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RootView: View {
    @StateObject private var store = StoreKitManager()
    @State private var path: [AppRoute] = []
    @State private var isLoading = true
    @State private var hasPresentedLaunchPaywall = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    LoadingView()
                } else if !hasCompletedOnboarding {
                    OnboardingView {
                        hasCompletedOnboarding = true
                        DispatchQueue.main.async {
                            path.append(.paywall)
                        }
                    }
                } else {
                    HomeView(
                        onOpenPaywall: { path.append(.paywall) },
                        onOpenSettings: { path.append(.settings) },
                        onOpenEditor: openEditorOrPaywall
                    )
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .paywall:
                    PaywallView(onClose: closeTopRoute)
                case .settings:
                    SettingsView(onBack: closeTopRoute, onOpenPaywall: { path.append(.paywall) })
                case .editor(let editorRoute):
                    EditorView(
                        image: editorRoute.image,
                        toolKind: editorRoute.toolKind,
                        onBack: closeTopRoute,
                        onGoToMenu: closeToHome
                    )
                case .uploadCrop(let cropRoute):
                    UploadCropView(
                        image: cropRoute.image,
                        onBack: closeTopRoute,
                        onContinue: { resultImage in
                            path.append(.uploadResult(UploadResultRoute(
                                originalImage: cropRoute.image,
                                resultImage: resultImage
                            )))
                        }
                    )
                case .uploadResult(let resultRoute):
                    UploadResultView(
                        originalImage: resultRoute.originalImage,
                        resultImage: resultRoute.resultImage,
                        onBack: closeToHome,
                        onOpenPaywall: { path.append(.paywall) },
                        onOpenEditor: { image, kind in
                            openEditorOrPaywall(image: image, kind: kind)
                        },
                        onProcessAnotherImage: { image in
                            path.removeAll()
                            path.append(.uploadCrop(UploadCropRoute(image: image)))
                        }
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .environmentObject(store)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isLoading = false
                presentLaunchPaywallIfNeeded()
            }
        }
        .onChange(of: store.hasLoadedProducts) { _, _ in
            presentLaunchPaywallIfNeeded()
        }
        .task {
            await store.loadProducts()
            presentLaunchPaywallIfNeeded()
            await OpenAIAPIKeyManager.shared.refreshKeyIfNeeded()
        }
    }

    private func closeTopRoute() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    private func closeToHome() {
        path.removeAll()
    }

    private func openEditorOrPaywall(image: UIImage, kind: HomeToolKind) {
        guard !kind.requiresPremium || store.isPremium else {
            path.append(.paywall)
            return
        }

        if kind == .upload {
            path.append(.uploadCrop(UploadCropRoute(image: image)))
        } else {
            path.append(.editor(EditorRoute(image: image, toolKind: kind)))
        }
    }

    private func presentLaunchPaywallIfNeeded() {
        guard !isLoading else { return }
        guard hasCompletedOnboarding else { return }
        guard store.hasLoadedProducts else { return }
        guard !store.isPremium else { return }
        guard !hasPresentedLaunchPaywall else { return }
        guard !path.contains(.paywall) else { return }

        hasPresentedLaunchPaywall = true
        path.append(.paywall)
    }
}

#Preview {
    RootView()
}
