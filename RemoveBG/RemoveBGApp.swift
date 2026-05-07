import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct RemoveBGApp: App {
    init() {
        #if canImport(UIKit)
        UIView.appearance().overrideUserInterfaceStyle = .light
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
