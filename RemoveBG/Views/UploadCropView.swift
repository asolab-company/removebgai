import Photos
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct UploadCropView: View {
    let image: UIImage
    let onBack: () -> Void
    let onContinue: (UIImage) -> Void

    @State private var selectedPreset: UploadCropPreset = .individual
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var individualCropRect: CGRect = .zero

    var body: some View {
        GeometryReader { proxy in
            let layout = UploadCropLayout(size: proxy.size)
            let stageSize = layout.stageSize
            let cropRect = activeCropRect(stageSize: stageSize, layout: layout)

            VStack(spacing: 0) {
                UploadEditorHeader(title: "Crop", onBack: onBack)
                    .padding(.horizontal, 18)
                    .padding(.top, layout.headerTop)

                Spacer(minLength: layout.imageTop)

                InteractiveCropPreview(
                    image: image.normalizedForEditing(),
                    stageSize: stageSize,
                    cropRect: cropRect,
                    preset: selectedPreset,
                    scale: $scale,
                    lastScale: $lastScale,
                    offset: $offset,
                    lastOffset: $lastOffset,
                    individualCropRect: $individualCropRect
                )
                .frame(width: stageSize.width, height: stageSize.height)

                Spacer(minLength: layout.presetsTop)

                HStack(alignment: .top, spacing: layout.presetSpacing) {
                    ForEach(UploadCropPreset.allCases) { preset in
                        UploadCropPresetButton(
                            preset: preset,
                            imageAspect: image.safeAspectRatio,
                            isSelected: selectedPreset == preset
                        ) {
                            selectedPreset = preset
                            resetTransform()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

                Spacer(minLength: 22)

                PrimaryButton(title: "Continue") {
                    let output = image.croppedForUpload(
                        stageSize: stageSize,
                        cropRect: cropRect,
                        scale: scale,
                        offset: offset,
                        preset: selectedPreset
                    )
                    onContinue(output)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, layout.bottomPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .background(AppColors.background.ignoresSafeArea())
        }
        .navigationBarBackButtonHidden(true)
    }

    private func resetTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func activeCropRect(stageSize: CGSize, layout: UploadCropLayout) -> CGRect {
        if selectedPreset == .individual {
            return individualCropRect.normalized(in: stageSize)
        }
        return layout.cropRect(for: selectedPreset, image: image, in: stageSize)
    }
}

struct UploadResultView: View {
    let originalImage: UIImage
    let resultImage: UIImage
    let onBack: () -> Void
    let onOpenPaywall: () -> Void
    let onOpenEditor: (UIImage, HomeToolKind) -> Void
    let onProcessAnotherImage: (UIImage) -> Void
    @EnvironmentObject private var store: StoreKitManager

    @State private var isComparing = false
    @State private var isSharePresented = false
    @State private var alertMessage: String?
    @State private var isImageSelectionPresented = false
    @State private var isSuccessPresented = false

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let layout = UploadResultLayout(size: proxy.size)

                VStack(spacing: 0) {
                    UploadEditorHeader(title: "Result", onBack: onBack) {
                        Button {
                            isSharePresented = true
                        } label: {
                            Image(FigmaAssets.send)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, layout.headerTop)

                    Color.clear
                        .frame(height: layout.imageTop)

                    UploadResultPreview(
                        image: isComparing ? originalImage : resultImage,
                        size: layout.previewSize,
                        isComparing: isComparing
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isComparing {
                                    isComparing = true
                                }
                            }
                            .onEnded { _ in
                                isComparing = false
                            }
                    )

                    Color.clear
                        .frame(height: layout.toolsTop)

                    UploadResultOptionsSection(
                        title: "Edit Tools",
                        options: UploadEditTool.allCases.map { $0.option },
                        selectedID: nil,
                        style: .activeBlue,
                        isPremium: store.isPremium
                    ) { option in
                        isComparing = false
                        if option.toolKind.requiresPremium && !store.isPremium {
                            onOpenPaywall()
                        } else {
                            onOpenEditor(resultImage, option.toolKind)
                        }
                    }
                    .padding(.horizontal, 18)

                    Spacer(minLength: layout.saveTop)

                    UploadPrimaryActionButton(
                        title: "Save to Photos",
                        systemIcon: "square.and.arrow.down"
                    ) {
                        saveToPhotos()
                    }
                    .padding(.horizontal, 18)

                    Button {
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(AppColors.tertiaryText.opacity(0.14))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppColors.tertiaryText)
                                )

                            Text("Process Another Image")
                                .font(AppTypography.medium(16))
                                .foregroundStyle(AppColors.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                    .padding(.horizontal, 18)
                    .padding(.bottom, layout.bottomPadding)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .background(AppColors.background.ignoresSafeArea())
            }
            .blur(radius: isImageSelectionPresented ? 12 : 0)
            .disabled(isImageSelectionPresented || isSuccessPresented)

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
                            isSuccessPresented = false
                        }
                        onProcessAnotherImage(image)
                    }
                )
                .zIndex(3)
            }

            if isSuccessPresented {
                SuccessSavedView(
                    image: resultImage,
                    onProcessAnotherImage: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isImageSelectionPresented = true
                        }
                    },
                    onGoToMenu: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isSuccessPresented = false
                        }
                        onBack()
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isImageSelectionPresented)
        .animation(.easeInOut(duration: 0.22), value: isSuccessPresented)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $isSharePresented) {
            UploadActivityView(activityItems: [resultImage])
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Remove BG", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func saveToPhotos() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                alertMessage = "Allow photo access in Settings to save the image."
                return
            }

            do {
                guard let pngData = resultImage.pngData() else {
                    alertMessage = "Could not prepare this image as PNG."
                    return
                }

                try await PHPhotoLibrary.shared().performChanges {
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = UTType.png.identifier
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .photo, data: pngData, options: options)
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    isSuccessPresented = true
                }
            } catch {
                alertMessage = "Could not save this image. Please try again."
            }
        }
    }
}

private struct UploadEditorHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Text(title)
                .font(AppTypography.bold(20))
                .foregroundStyle(AppColors.primaryText)

            Spacer()

            trailing()
        }
        .frame(height: 32)
    }
}

private struct InteractiveCropPreview: View {
    let image: UIImage
    let stageSize: CGSize
    let cropRect: CGRect
    let preset: UploadCropPreset
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    @Binding var individualCropRect: CGRect

    var body: some View {
        ZStack {
            imageLayer

            CropDimOverlay(cropRect: cropRect)
                .fill(Color.black.opacity(0.28), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            Rectangle()
                .stroke(AppColors.white, lineWidth: 4)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .allowsHitTesting(false)

            CropCorners()
                .stroke(AppColors.white, style: StrokeStyle(lineWidth: 5, lineCap: .square, lineJoin: .miter))
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .allowsHitTesting(false)

            if preset == .individual {
                CropResizeHandles(cropRect: $individualCropRect, stageSize: stageSize)
            }
        }
        .frame(width: stageSize.width, height: stageSize.height)
        .contentShape(Rectangle())
        .clipped()
        .shadow(color: AppColors.black.opacity(0.24), radius: 25)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard preset != .original else {
                        return
                    }
                    let proposed = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    offset = proposed.clamped(for: image.size, stageSize: stageSize, cropRect: cropRect, scale: scale)
                }
                .onEnded { _ in
                    guard preset != .original else {
                        return
                    }
                    offset = offset.clamped(for: image.size, stageSize: stageSize, cropRect: cropRect, scale: scale)
                    lastOffset = offset
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard preset != .original else {
                        return
                    }
                    scale = min(max(lastScale * value, 1), 5)
                    offset = offset.clamped(for: image.size, stageSize: stageSize, cropRect: cropRect, scale: scale)
                }
                .onEnded { _ in
                    guard preset != .original else {
                        return
                    }
                    scale = min(max(scale, 1), 5)
                    offset = offset.clamped(for: image.size, stageSize: stageSize, cropRect: cropRect, scale: scale)
                    lastScale = scale
                    lastOffset = offset
                }
        )
        .onAppear {
            if individualCropRect == .zero {
                individualCropRect = CGRect(origin: .zero, size: stageSize)
            }
        }
        .onChange(of: stageSize) { _, newSize in
            individualCropRect = individualCropRect.normalized(in: newSize)
            offset = offset.clamped(for: image.size, stageSize: newSize, cropRect: cropRect, scale: scale)
            lastOffset = offset
        }
        .onChange(of: cropRect) { _, newRect in
            offset = offset.clamped(for: image.size, stageSize: stageSize, cropRect: newRect, scale: scale)
            lastOffset = offset
        }
    }

    @ViewBuilder
    private var imageLayer: some View {
        if preset == .original {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: stageSize.width, height: stageSize.height)
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: stageSize.width, height: stageSize.height)
                .scaleEffect(scale)
                .offset(offset)
        }
    }
}

private struct CropCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 64
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

private struct CropDimOverlay: Shape {
    let cropRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cropRect)
        return path
    }
}

private struct CropResizeHandles: View {
    @Binding var cropRect: CGRect
    let stageSize: CGSize
    @State private var dragStartRect: CGRect?

    var body: some View {
        ZStack {
            ForEach(CropResizeHandle.allCases) { handle in
                Circle()
                    .fill(AppColors.white)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(AppColors.primaryBlue, lineWidth: 2)
                    )
                    .shadow(color: AppColors.black.opacity(0.18), radius: 5, y: 2)
                    .position(handle.position(in: activeRect))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let start = dragStartRect ?? activeRect
                                dragStartRect = start
                                cropRect = handle.resizedRect(
                                    from: start,
                                    translation: value.translation,
                                    stageSize: stageSize
                                )
                            }
                            .onEnded { _ in
                                cropRect = activeRect.normalized(in: stageSize)
                                dragStartRect = nil
                            }
                    )
            }
        }
        .frame(width: stageSize.width, height: stageSize.height)
    }

    private var activeRect: CGRect {
        cropRect.normalized(in: stageSize)
    }
}

private enum CropResizeHandle: CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String {
        switch self {
        case .topLeft:
            return "topLeft"
        case .topRight:
            return "topRight"
        case .bottomLeft:
            return "bottomLeft"
        case .bottomRight:
            return "bottomRight"
        }
    }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    func resizedRect(from rect: CGRect, translation: CGSize, stageSize: CGSize) -> CGRect {
        let minSide: CGFloat = 92
        var next = rect

        switch self {
        case .topLeft:
            next.origin.x += translation.width
            next.origin.y += translation.height
            next.size.width -= translation.width
            next.size.height -= translation.height
        case .topRight:
            next.origin.y += translation.height
            next.size.width += translation.width
            next.size.height -= translation.height
        case .bottomLeft:
            next.origin.x += translation.width
            next.size.width -= translation.width
            next.size.height += translation.height
        case .bottomRight:
            next.size.width += translation.width
            next.size.height += translation.height
        }

        if next.width < minSide {
            let delta = minSide - next.width
            switch self {
            case .topLeft, .bottomLeft:
                next.origin.x -= delta
            case .topRight, .bottomRight:
                break
            }
            next.size.width = minSide
        }

        if next.height < minSide {
            let delta = minSide - next.height
            switch self {
            case .topLeft, .topRight:
                next.origin.y -= delta
            case .bottomLeft, .bottomRight:
                break
            }
            next.size.height = minSide
        }

        return next.normalized(in: stageSize)
    }
}

private struct UploadCropPresetButton: View {
    let preset: UploadCropPreset
    let imageAspect: CGFloat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 50, height: 50)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? AppColors.primaryBlue : AppColors.tertiaryText.opacity(0.45), lineWidth: 2)
                        .frame(width: iconSize.width, height: iconSize.height)

                    if preset.showsInnerMark {
                        Image(systemName: "crop")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? AppColors.primaryBlue : AppColors.tertiaryText.opacity(0.45))
                    }
                }
                .frame(width: 50, height: 50)

                Text(preset.title)
                    .font(AppTypography.regular(12))
                    .foregroundStyle(isSelected ? AppColors.primaryBlue : AppColors.tertiaryText.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: 56)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconSize: CGSize {
        let aspect = preset.aspectRatio(imageAspect: imageAspect)
        let maxW: CGFloat = 42
        let maxH: CGFloat = 50
        if aspect >= maxW / maxH {
            return CGSize(width: maxW, height: maxW / aspect)
        }
        return CGSize(width: maxH * aspect, height: maxH)
    }
}

private struct UploadResultPreview: View {
    let image: UIImage
    let size: CGSize
    let isComparing: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            UploadCheckerboard(squareSize: 16)

            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .zoomablePreview()

            Text(isComparing ? "Original" : "Hold to compare")
                .font(AppTypography.bold(12))
                .foregroundStyle(AppColors.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(
                    Capsule()
                        .fill(Color(red: 54 / 255, green: 54 / 255, blue: 54 / 255).opacity(0.6))
                        .blur(radius: 0.1)
                )
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct UploadResultOptionsSection: View {
    let title: String
    let options: [UploadOptionItem]
    let selectedID: String?
    var style: UploadOptionStyle = .selectable
    var isPremium = true
    var onSelect: (UploadOptionItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.semibold(16))
                .foregroundStyle(AppColors.primaryText)

            HStack(spacing: 22) {
                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        UploadOptionButton(
                            option: option,
                            isSelected: selectedID == option.id,
                            style: style,
                            isLocked: option.toolKind.requiresPremium && !isPremium
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UploadOptionButton: View {
    let option: UploadOptionItem
    let isSelected: Bool
    let style: UploadOptionStyle
    let isLocked: Bool

    var body: some View {
        let isBlue = !isLocked && (style == .activeBlue || isSelected)

        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isBlue ? AppColors.primaryBlue.opacity(0.2) : AppColors.tertiaryText.opacity(0.2))
                    .frame(width: 40, height: 40)

                option.icon
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isBlue ? AppColors.primaryBlue : AppColors.tertiaryText)

                if isLocked {
                    Circle()
                        .fill(AppColors.primaryText.opacity(0.86))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AppColors.white)
                        )
                        .offset(x: 15, y: -15)
                }

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AppColors.primaryBlue : Color.clear, lineWidth: 2)
                    .frame(width: 40, height: 40)
            }

            Text(option.title)
                .font(AppTypography.regular(12))
                .foregroundStyle(isBlue ? AppColors.primaryBlue : AppColors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 48)
        }
        .contentShape(Rectangle())
    }
}

private enum UploadOptionStyle {
    case selectable
    case activeBlue
}

private struct UploadPrimaryActionButton: View {
    let title: String
    let systemIcon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColors.white.opacity(0.14))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: systemIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.white)
                    )

                Text(title)
                    .font(AppTypography.medium(16))
                    .foregroundStyle(AppColors.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(AppColors.primaryBlue)
                    .shadow(color: AppColors.primaryBlue.opacity(0.38), radius: 4, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct UploadCheckerboard: View {
    let squareSize: CGFloat

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "F4F4F4")))
            for row in 0...rows {
                for column in 0...columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(Color(hex: "D9D9D9")))
                }
            }
        }
    }
}

private struct UploadActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum UploadCropPreset: String, CaseIterable, Identifiable {
    case individual
    case original
    case square
    case fourFive
    case nineSixteen
    case nineThree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individual:
            return "Individual"
        case .original:
            return "Original"
        case .square:
            return "Square"
        case .fourFive:
            return "4 x 5"
        case .nineSixteen:
            return "9 x 16"
        case .nineThree:
            return "9 x 3"
        }
    }

    var showsInnerMark: Bool {
        self != .individual && self != .original
    }

    func aspectRatio(imageAspect: CGFloat) -> CGFloat {
        switch self {
        case .individual:
            return 367 / 457
        case .original:
            return imageAspect
        case .square:
            return 1
        case .fourFive:
            return 4 / 5
        case .nineSixteen:
            return 9 / 16
        case .nineThree:
            return 9 / 3
        }
    }
}

private enum UploadEditTool: CaseIterable {
    case aiBG
    case blurBG
    case enhance
    case remove
    case eraser

    var option: UploadOptionItem {
        switch self {
        case .aiBG:
            return UploadOptionItem(id: "ai", title: "AI BG", iconName: "photo.on.rectangle.angled", toolKind: .aiBackground)
        case .blurBG:
            return UploadOptionItem(id: "blur", title: "Blur BG", iconName: "drop.fill", toolKind: .blurBackground)
        case .enhance:
            return UploadOptionItem(id: "enhance", title: "Enhance", iconName: "sparkles", toolKind: .enhanceQuality)
        case .remove:
            return UploadOptionItem(id: "remove", title: "Remove", iconName: "wand.and.stars", toolKind: .removeObject)
        case .eraser:
            return UploadOptionItem(id: "eraser", title: "Eraser", iconName: "eraser.fill", toolKind: .eraser)
        }
    }
}

private enum UploadBackgroundOption: String, CaseIterable {
    case none
    case white
    case black
    case blur
    case color

    var option: UploadOptionItem {
        switch self {
        case .none:
            return UploadOptionItem(id: rawValue, title: "None", iconName: "checkerboard.rectangle", toolKind: .eraser)
        case .white:
            return UploadOptionItem(id: rawValue, title: "White", iconName: "circle.fill", toolKind: .eraser)
        case .black:
            return UploadOptionItem(id: rawValue, title: "Black", iconName: "circle.fill", toolKind: .eraser)
        case .blur:
            return UploadOptionItem(id: rawValue, title: "Blur", iconName: "drop.fill", toolKind: .blurBackground)
        case .color:
            return UploadOptionItem(id: rawValue, title: "Color", iconName: "paintpalette.fill", toolKind: .aiBackground)
        }
    }
}

private struct UploadOptionItem: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let toolKind: HomeToolKind

    var icon: Image {
        Image(systemName: iconName)
    }
}

private struct UploadCropLayout {
    let size: CGSize

    var headerTop: CGFloat {
        size.height < 700 ? 8 : 16
    }

    var imageTop: CGFloat {
        size.height < 700 ? 20 : 68
    }

    var presetsTop: CGFloat {
        size.height < 700 ? 18 : 32
    }

    var bottomPadding: CGFloat {
        max(16, size.height < 700 ? 14 : 49)
    }

    var presetSpacing: CGFloat {
        size.width < 380 ? 0 : 6
    }

    var stageSize: CGSize {
        let availableWidth = min(size.width - 26, 367)
        let maxStageHeight: CGFloat = size.height < 700 ? 360 : 457
        let minStageHeight: CGFloat = size.height < 700 ? 240 : 260
        let maxHeight = min(maxStageHeight, max(minStageHeight, size.height - headerTop - imageTop - presetsTop - bottomPadding - 146))
        return CGSize(width: availableWidth, height: maxHeight)
    }

    func cropRect(for preset: UploadCropPreset, image: UIImage, in stageSize: CGSize) -> CGRect {
        if preset == .individual {
            return CGRect(origin: .zero, size: stageSize)
        }

        let aspect = max(0.1, preset.aspectRatio(imageAspect: image.safeAspectRatio))
        var width = stageSize.width
        var height = width / aspect

        if height > stageSize.height {
            height = stageSize.height
            width = height * aspect
        }

        return CGRect(
            x: (stageSize.width - width) * 0.5,
            y: (stageSize.height - height) * 0.5,
            width: max(92, width),
            height: max(92, height)
        )
    }
}

private struct UploadResultLayout {
    let size: CGSize

    private var isCompact: Bool {
        size.height < 760
    }

    var headerTop: CGFloat {
        isCompact ? 8 : 16
    }

    var imageTop: CGFloat {
        isCompact ? 14 : 27
    }

    var toolsTop: CGFloat {
        isCompact ? 16 : 28
    }

    var saveTop: CGFloat {
        isCompact ? 14 : 24
    }

    var bottomPadding: CGFloat {
        isCompact ? 6 : 8
    }

    var previewSize: CGSize {
        let maxWidth = max(140, size.width - 36)
        let toolsBlockHeight: CGFloat = 87
        let fixedHeight = headerTop + 32 + imageTop + toolsTop + toolsBlockHeight + saveTop + 54 + 42 + bottomPadding
        let maxHeight = max(220, size.height - fixedHeight)
        let compactPreviewHeight = isCompact ? min(maxHeight, 330) : maxHeight
        let figmaWidth = min(356, maxWidth)
        let figmaHeight = figmaWidth * (414 / 356)
        let height = min(414, min(figmaHeight, compactPreviewHeight))
        let width = min(figmaWidth, height * (356 / 414))
        return CGSize(width: max(140, width), height: max(220, height))
    }
}

private extension CGSize {
    func clamped(for imageSize: CGSize, stageSize: CGSize, cropRect: CGRect, scale: CGFloat) -> CGSize {
        let baseScale = max(stageSize.width / max(imageSize.width, 1), stageSize.height / max(imageSize.height, 1))
        let drawSize = CGSize(
            width: imageSize.width * baseScale * scale,
            height: imageSize.height * baseScale * scale
        )
        let baseX = (stageSize.width - drawSize.width) * 0.5
        let baseY = (stageSize.height - drawSize.height) * 0.5
        let minX = min(cropRect.maxX - baseX - drawSize.width, cropRect.minX - baseX)
        let maxX = max(cropRect.maxX - baseX - drawSize.width, cropRect.minX - baseX)
        let minY = min(cropRect.maxY - baseY - drawSize.height, cropRect.minY - baseY)
        let maxY = max(cropRect.maxY - baseY - drawSize.height, cropRect.minY - baseY)
        return CGSize(
            width: min(max(width, minX), maxX),
            height: min(max(height, minY), maxY)
        )
    }
}

private extension CGRect {
    func normalized(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return self
        }

        let minimumSide: CGFloat = 92
        var width = min(max(self.width, minimumSide), size.width)
        var height = min(max(self.height, minimumSide), size.height)
        var x = origin.x
        var y = origin.y

        if x < 0 {
            x = 0
        }
        if y < 0 {
            y = 0
        }
        if x + width > size.width {
            x = size.width - width
        }
        if y + height > size.height {
            y = size.height - height
        }

        if self == .zero {
            width = size.width
            height = size.height
            x = 0
            y = 0
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private extension UIImage {
    var safeAspectRatio: CGFloat {
        guard size.width > 0, size.height > 0 else {
            return 1
        }
        return size.width / size.height
    }

    func normalizedForEditing() -> UIImage {
        guard imageOrientation != .up || scale != 1 else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func croppedForUpload(
        stageSize: CGSize,
        cropRect: CGRect,
        scale: CGFloat,
        offset: CGSize,
        preset: UploadCropPreset
    ) -> UIImage {
        let normalized = normalizedForEditing()
        if preset == .original {
            return normalized
        }

        let imageSize = normalized.size
        let safeScale = min(max(scale, 1), 5)
        let normalizedCropRect = cropRect.normalized(in: stageSize)
        let baseScale = max(stageSize.width / max(imageSize.width, 1), stageSize.height / max(imageSize.height, 1))
        let effectiveScale = baseScale * safeScale
        let drawSize = CGSize(width: imageSize.width * effectiveScale, height: imageSize.height * effectiveScale)
        let clampedOffset = offset.clamped(for: imageSize, stageSize: stageSize, cropRect: normalizedCropRect, scale: safeScale)
        let drawOrigin = CGPoint(
            x: (stageSize.width - drawSize.width) * 0.5 + clampedOffset.width,
            y: (stageSize.height - drawSize.height) * 0.5 + clampedOffset.height
        )
        var sourceRect = CGRect(
            x: (normalizedCropRect.minX - drawOrigin.x) / effectiveScale,
            y: (normalizedCropRect.minY - drawOrigin.y) / effectiveScale,
            width: normalizedCropRect.width / effectiveScale,
            height: normalizedCropRect.height / effectiveScale
        )
        sourceRect = sourceRect.intersection(CGRect(origin: .zero, size: imageSize))

        guard sourceRect.width > 1, sourceRect.height > 1 else {
            return normalized
        }

        let outputSize = CGSize(
            width: max(1, sourceRect.width),
            height: max(1, sourceRect.height)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            normalized.draw(
                in: CGRect(
                    x: -sourceRect.minX,
                    y: -sourceRect.minY,
                    width: imageSize.width,
                    height: imageSize.height
                )
            )
        }
    }
}

#Preview("Crop") {
    UploadCropView(image: UIImage(systemName: "photo") ?? UIImage(), onBack: {}, onContinue: { _ in })
}

#Preview("Result") {
    UploadResultView(
        originalImage: UIImage(systemName: "photo") ?? UIImage(),
        resultImage: UIImage(systemName: "photo") ?? UIImage(),
        onBack: {},
        onOpenPaywall: {},
        onOpenEditor: { _, _ in },
        onProcessAnotherImage: { _ in }
    )
    .environmentObject(StoreKitManager())
}
