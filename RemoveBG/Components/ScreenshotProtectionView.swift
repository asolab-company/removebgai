import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ScreenshotProtectionView<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @State private var showScreenshotShield = false

    var body: some View {
        ZStack {
            content

            if isScreenCaptured || showScreenshotShield {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            showScreenshotShield = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                showScreenshotShield = false
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isScreenCaptured)
        .animation(.easeInOut(duration: 0.16), value: showScreenshotShield)
    }

    private var isScreenCaptured: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        isSceneCaptured
        #endif
    }
}
