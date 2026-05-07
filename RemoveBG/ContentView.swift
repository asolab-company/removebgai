import SwiftUI

struct ContentView: View {
    var body: some View {
        ScreenshotProtectionView {
            RootView()
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
}
