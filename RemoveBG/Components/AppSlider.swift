import SwiftUI

struct AppSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = normalizedProgress
            let thumbX = progress * width - thumbSize / 2
            let fillWidth = progress * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.tertiaryText.opacity(0.22),
                                AppColors.tertiaryText.opacity(0.34)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)
                    .shadow(color: AppColors.white.opacity(0.85), radius: 1, y: -1)
                    .shadow(color: AppColors.black.opacity(0.05), radius: 2, y: 1)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "2B8CFF"),
                                AppColors.primaryBlue
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: trackHeight)
                    .shadow(color: AppColors.primaryBlue.opacity(0.22), radius: 4, y: 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.white,
                                Color(hex: "F7F7F7")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(AppColors.white.opacity(0.9), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .fill(AppColors.white.opacity(0.48))
                            .frame(width: 7, height: 7)
                            .offset(x: -4, y: -4),
                        alignment: .topLeading
                    )
                    .shadow(color: AppColors.black.opacity(0.16), radius: 7, y: 4)
                    .shadow(color: AppColors.black.opacity(0.06), radius: 1, y: 1)
                    .offset(x: thumbX)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(locationX: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: thumbSize)
    }

    private var normalizedProgress: CGFloat {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else {
            return 0
        }
        let rawProgress = (value - range.lowerBound) / distance
        return CGFloat(min(max(rawProgress, 0), 1))
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        let usableWidth = max(width, 1)
        let rawProgress = locationX / usableWidth
        let progress = min(max(Double(rawProgress), 0), 1)
        value = range.lowerBound + progress * (range.upperBound - range.lowerBound)
    }
}
