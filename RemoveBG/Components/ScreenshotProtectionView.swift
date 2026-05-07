import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ScreenshotProtectionView<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var isScreenCaptured = false
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
        .onAppear {
            updateCaptureState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            updateCaptureState()
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

    private func updateCaptureState() {
        #if targetEnvironment(simulator)
        isScreenCaptured = false
        #else
        isScreenCaptured = UIScreen.main.isCaptured
        #endif
    }
}
