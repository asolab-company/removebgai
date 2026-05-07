import SwiftUI

struct SuccessSavedView: View {
    let image: UIImage
    let onProcessAnotherImage: () -> Void
    let onGoToMenu: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isCompactHeight = proxy.size.height <= 700
            let heightScale = min(max(proxy.size.height / 852, 0.86), 1.08)
            let topSpacing = isCompactHeight ? max(0, (proxy.size.height - 227 - 24 - 8 - 20 - 54 - 54 - 38) / 2) : 227 * heightScale

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: topSpacing)

                imageStage
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Done!")
                    .font(AppTypography.bold(24))
                    .foregroundStyle(AppColors.primaryText)
                    .padding(.top, 32 * heightScale)

                Text("Your new photo is ready in your gallery.")
                    .font(AppTypography.regular(16))
                    .foregroundStyle(AppColors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                Spacer(minLength: 30)

                PrimaryButton(title: "Process Another Image", systemIcon: "arrow.triangle.2.circlepath") {
                    onProcessAnotherImage()
                }
                .padding(.horizontal, 18)

                Button(action: onGoToMenu) {
                    Text("Go to Menu")
                        .font(AppTypography.medium(16))
                        .foregroundStyle(AppColors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.bottom, max(21, 21 * heightScale))
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private var imageStage: some View {
        ZStack {
            SuccessCornerGuides()
                .stroke(AppColors.tertiaryText.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 232, height: 227)

            SuccessCheckerboard(squareSize: 16)
                .frame(width: 168, height: 195)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: 168, height: 195)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(width: 232, height: 227)
    }
}

private struct SuccessCornerGuides: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner: CGFloat = 24
        let length: CGFloat = 64

        func addCorner(x: CGFloat, y: CGFloat, horizontalSign: CGFloat, verticalSign: CGFloat) {
            path.move(to: CGPoint(x: x + horizontalSign * corner, y: y))
            path.addLine(to: CGPoint(x: x + horizontalSign * length, y: y))
            path.move(to: CGPoint(x: x, y: y + verticalSign * corner))
            path.addLine(to: CGPoint(x: x, y: y + verticalSign * length))
            path.move(to: CGPoint(x: x + horizontalSign * corner, y: y))
            path.addQuadCurve(
                to: CGPoint(x: x, y: y + verticalSign * corner),
                control: CGPoint(x: x, y: y)
            )
        }

        addCorner(x: rect.minX, y: rect.minY, horizontalSign: 1, verticalSign: 1)
        addCorner(x: rect.maxX, y: rect.minY, horizontalSign: -1, verticalSign: 1)
        addCorner(x: rect.minX, y: rect.maxY, horizontalSign: 1, verticalSign: -1)
        addCorner(x: rect.maxX, y: rect.maxY, horizontalSign: -1, verticalSign: -1)

        return path
    }
}

private struct SuccessCheckerboard: View {
    let squareSize: CGFloat

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))

            for row in 0...rows {
                for column in 0...columns {
                    let isLight = (row + column).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color.white : AppColors.tertiaryText.opacity(0.32))
                    )
                }
            }
        }
    }
}

#Preview {
    SuccessSavedView(
        image: UIImage(systemName: "photo") ?? UIImage(),
        onProcessAnotherImage: {},
        onGoToMenu: {}
    )
}
