import SwiftUI

struct ZoomablePreviewModifier: ViewModifier {
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .animation(.easeOut(duration: 0.16), value: scale)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value, 1), 4)
                    }
                    .onEnded { _ in
                        if scale < 1.04 {
                            scale = 1
                        }
                        lastScale = scale
                    }
            )
            .onTapGesture(count: 2) {
                if scale > 1 {
                    scale = 1
                    lastScale = 1
                } else {
                    scale = 2
                    lastScale = 2
                }
            }
    }
}

extension View {
    func zoomablePreview() -> some View {
        modifier(ZoomablePreviewModifier())
    }
}
