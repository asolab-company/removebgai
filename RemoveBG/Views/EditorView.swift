import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Vision
#if canImport(UIKit)
import UIKit
#endif

struct EditorView: View {
    let toolKind: HomeToolKind
    let onBack: () -> Void
    let onGoToMenu: () -> Void

    @State private var sourceImage: UIImage
    @State private var originalImage: UIImage
    @State private var previewSourceImage: UIImage
    @State private var processedPreviewImage: UIImage
    @State private var shareImage: UIImage
    @State private var brightness = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var sharpness = 0.0
    @State private var backgroundBlur = 12.0
    @State private var brushSize = 28.0
    @State private var objectRemovalStrokes: [ObjectRemovalStroke] = []
    @State private var currentObjectRemovalStroke: ObjectRemovalStroke?
    @State private var isProcessingObjectRemoval = false
    @State private var objectRemovalStatus = "Processing"
    @State private var objectRemovalProgress = 0.0
    @State private var objectRemovalTask: Task<Void, Never>?
    @State private var objectRemovalProgressTask: Task<Void, Never>?
    @State private var hasObjectRemovalResult = false
    @State private var aiBackgroundSelection: AIBackgroundSelection = .none
    @State private var aiBackgroundReferenceImage: UIImage?
    @State private var selectedAIBackgroundColorHex = "6366F1"
    @State private var selectedAIBackgroundColorOpacity = 1.0
    @State private var isAIBackgroundColorSheetPresented = false
    @State private var isBackgroundPhotoPickerPresented = false
    @State private var backgroundPhotoPickerItem: PhotosPickerItem?
    @State private var isProcessingAIBackground = false
    @State private var aiBackgroundStatus = "Processing"
    @State private var aiBackgroundProgress = 0.0
    @State private var aiBackgroundTask: Task<Void, Never>?
    @State private var aiBackgroundProgressTask: Task<Void, Never>?
    @State private var hasAIBackgroundResult = false
    @State private var previewForegroundMask: CIImage?
    @State private var imageProcessingID = UUID()
    @State private var blurRenderTask: Task<Void, Never>?
    @State private var isImageSelectionPresented = false
    @State private var isSharePresented = false
    @State private var alertMessage: String?
    @State private var isPreviewComparing = false
    @State private var isSuccessPresented = false
    @State private var successImage: UIImage?

    private let renderer = QualityImageRenderer()
    private let blurProcessor = BackgroundBlurProcessor.shared

    init(
        image: UIImage?,
        toolKind: HomeToolKind,
        onBack: @escaping () -> Void,
        onGoToMenu: @escaping () -> Void
    ) {
        let initialImage = image ?? UIImage()
        let previewImage = initialImage.qualityPreviewImage(maxPixelDimension: toolKind == .blurBackground ? 540 : 720)
        self.toolKind = toolKind
        self.onBack = onBack
        self.onGoToMenu = onGoToMenu
        _sourceImage = State(initialValue: initialImage)
        _originalImage = State(initialValue: initialImage)
        _previewSourceImage = State(initialValue: previewImage)
        _processedPreviewImage = State(initialValue: previewImage)
        _shareImage = State(initialValue: previewImage)
    }

    var body: some View {
        ZStack {
            qualityEditor
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
                        reset(with: image)
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isImageSelectionPresented = false
                            isSuccessPresented = false
                        }
                    }
                )
                .zIndex(5)
            }

            if isProcessingObjectRemoval || isProcessingAIBackground {
                ObjectRemovalProcessingView(
                    image: previewSourceImage,
                    progress: isProcessingAIBackground ? aiBackgroundProgress : objectRemovalProgress,
                    status: isProcessingAIBackground ? aiBackgroundStatus : objectRemovalStatus,
                    finalStepTitle: isProcessingAIBackground ? "Background Ready" : "Object Removed",
                    onCancel: {
                        if isProcessingAIBackground {
                            cancelAIBackground(showAlert: true)
                        } else {
                            cancelObjectRemoval(showAlert: true)
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            if isSuccessPresented {
                SuccessSavedView(
                    image: successImage ?? processedPreviewImage,
                    onProcessAnotherImage: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isImageSelectionPresented = true
                        }
                    },
                    onGoToMenu: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isSuccessPresented = false
                        }
                        onGoToMenu()
                    }
                )
                .transition(.opacity)
                .zIndex(4)
            }

            if isAIBackgroundColorSheetPresented {
                AIBackgroundColorSheet(
                    selectedHex: $selectedAIBackgroundColorHex,
                    opacity: $selectedAIBackgroundColorOpacity,
                    onContinue: {
                        aiBackgroundSelection = .color
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isAIBackgroundColorSheetPresented = false
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isAIBackgroundColorSheetPresented = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isProcessingObjectRemoval)
        .animation(.easeInOut(duration: 0.22), value: isProcessingAIBackground)
        .background(AppColors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .photosPicker(
            isPresented: $isBackgroundPhotoPickerPresented,
            selection: $backgroundPhotoPickerItem,
            matching: .images
        )
        .onChange(of: backgroundPhotoPickerItem) { _, item in
            loadAIBackgroundReference(from: item)
        }
        .sheet(isPresented: $isSharePresented) {
            ActivityView(activityItems: [shareImage])
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
        .task(id: imageProcessingID) {
            await prepareForegroundMaskIfNeeded()
        }
        .onDisappear {
            blurRenderTask?.cancel()
            cancelObjectRemoval()
            cancelAIBackground()
        }
    }

    private var qualityEditor: some View {
        Group {
            if isAIBackgroundMode {
                aiBackgroundEditor
            } else {
                standardEditor
            }
        }
        .onChange(of: brightness) { renderCurrentImage() }
        .onChange(of: contrast) { renderCurrentImage() }
        .onChange(of: saturation) { renderCurrentImage() }
        .onChange(of: sharpness) { renderCurrentImage() }
        .onChange(of: backgroundBlur) { renderCurrentImage() }
    }

    private var standardEditor: some View {
        GeometryReader { proxy in
            let layout = QualityEditorLayout(
                width: proxy.size.width,
                height: proxy.size.height,
                sliderCount: activeSliders.count,
                isBlurMode: isBlurMode
            )
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, layout.headerTop)

                imagePreview(image: processedPreviewImage, size: layout.previewSize)
                    .padding(.top, layout.imageTop)

                VStack(spacing: layout.sliderSpacing) {
                    ForEach(activeSliders) { slider in
                        qualitySlider(slider, layout: layout)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, layout.slidersTop)

                Spacer(minLength: layout.saveTop)

                primaryActionButton(
                    title: primaryActionTitle,
                    systemIcon: primaryActionIcon,
                    isLoading: isProcessingObjectRemoval
                ) {
                    primaryAction()
                }
                .padding(.horizontal, 18)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isImageSelectionPresented = true
                    }
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
                    .frame(height: layout.processHeight)
                }
                .buttonStyle(.plain)
                .disabled(isProcessingObjectRemoval)
                .padding(.horizontal, 18)
                .padding(.top, layout.processTop)
                .padding(.bottom, layout.bottomPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private var aiBackgroundEditor: some View {
        GeometryReader { proxy in
            let layout = AIBackgroundEditorLayout(width: proxy.size.width, height: proxy.size.height)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, layout.headerTop)

                imagePreview(image: processedPreviewImage, size: layout.previewSize)
                    .padding(.top, layout.imageTop)

                Spacer(minLength: layout.controlsTop)

                aiBackgroundControls
                    .padding(.horizontal, 18)

                Spacer(minLength: layout.saveTop)

                primaryActionButton(
                    title: primaryActionTitle,
                    systemIcon: primaryActionIcon,
                    isLoading: isProcessingAIBackground
                ) {
                    primaryAction()
                }
                .padding(.horizontal, 18)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isImageSelectionPresented = true
                    }
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
                    .frame(height: layout.processHeight)
                }
                .buttonStyle(.plain)
                .disabled(isProcessingAIBackground)
                .padding(.horizontal, 18)
                .padding(.top, layout.processTop)
                .padding(.bottom, layout.bottomPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Text(editorTitle)
                .font(AppTypography.bold(20))
                .foregroundStyle(AppColors.primaryText)

            Spacer()

            HStack(spacing: 10) {
                Button {
                    resetEdits()
                } label: {
                    Image(FigmaAssets.reset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    shareCurrentImage()
                } label: {
                    Image(FigmaAssets.send)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 32)
    }

    private var editorTitle: String {
        if isBlurMode {
            return "Blur Background"
        }
        if isRemoveObjectMode {
            return "Remove Object"
        }
        if isEraserMode {
            return "Eraser"
        }
        if isAIBackgroundMode {
            return "AI Background"
        }
        return "Enhance Quality"
    }

    private var isBlurMode: Bool {
        toolKind == .blurBackground
    }

    private var isRemoveObjectMode: Bool {
        toolKind == .removeObject
    }

    private var isEraserMode: Bool {
        toolKind == .eraser
    }

    private var isAIBackgroundMode: Bool {
        toolKind == .aiBackground
    }

    private var activeSliders: [EditorSlider] {
        if isBlurMode {
            return [
                EditorSlider(title: "Blur", value: $backgroundBlur, range: 0...30, valueFormat: "%.0f")
            ]
        }

        if isRemoveObjectMode || isEraserMode {
            return [
                EditorSlider(title: "Brush Size", value: $brushSize, range: 8...64, valueFormat: "%.0f")
            ]
        }

        return [
            EditorSlider(title: "Brightness", value: $brightness, range: -1...1, valueFormat: "%.2f"),
            EditorSlider(title: "Contrast", value: $contrast, range: 0...2, valueFormat: "%.2f"),
            EditorSlider(title: "Saturation", value: $saturation, range: 0...2, valueFormat: "%.2f"),
            EditorSlider(title: "Sharpness", value: $sharpness, range: 0...2, valueFormat: "%.2f")
        ]
    }

    private func imagePreview(image: UIImage, size: CGSize) -> some View {
        if isEraserMode {
            return AnyView(eraserImagePreview(image: image, size: size))
        }

        let preview = ZStack(alignment: .bottomTrailing) {
            ZStack {
                CheckerboardBackground(squareSize: 20)
                Image(uiImage: isPreviewComparing ? previewSourceImage : image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                if isRemoveObjectMode && !isPreviewComparing {
                    ObjectRemovalBrushOverlay(
                        imageSize: previewSourceImage.size,
                        previewSize: size,
                        brushSize: brushSize,
                        strokes: $objectRemovalStrokes,
                        currentStroke: $currentObjectRemovalStroke
                    )
                    .allowsHitTesting(!isProcessingObjectRemoval)
                }
            }
            .frame(width: size.width, height: size.height)
            .zoomablePreview()

            holdToCompareBadge
                .padding(.trailing, 14)
                .padding(.bottom, 14)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipped()

        if isRemoveObjectMode {
            return AnyView(preview)
        }

        return AnyView(
            preview
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .simultaneousGesture(compareDragGesture)
        )
    }

    private func eraserImagePreview(image: UIImage, size: CGSize) -> some View {
        ZStack(alignment: .bottomTrailing) {
            CheckerboardBackground(squareSize: 20)

            ZStack {
                Image(uiImage: isPreviewComparing ? previewSourceImage : image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                if !isPreviewComparing {
                    EraserBrushOverlay(
                        imageSize: previewSourceImage.size,
                        previewSize: size,
                        brushSize: brushSize,
                        strokes: $objectRemovalStrokes,
                        currentStroke: $currentObjectRemovalStroke
                    )
                }
            }
            .compositingGroup()
            .frame(width: size.width, height: size.height)
            .zoomablePreview()

            holdToCompareBadge
                .padding(.trailing, 14)
                .padding(.bottom, 14)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipped()
    }

    private var holdToCompareBadge: some View {
        Text(isPreviewComparing ? "Original" : "Hold to compare")
            .font(AppTypography.bold(12))
            .foregroundStyle(AppColors.white)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(Color(red: 54 / 255, green: 54 / 255, blue: 54 / 255).opacity(0.6))
            )
            .contentShape(Capsule())
            .gesture(compareDragGesture)
    }

    private var compareDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPreviewComparing {
                    isPreviewComparing = true
                }
            }
            .onEnded { _ in
                isPreviewComparing = false
            }
    }

    private func qualitySlider(_ slider: EditorSlider, layout: QualityEditorLayout) -> some View {
        VStack(spacing: layout.sliderLabelGap) {
            HStack {
                Text(slider.title)
                    .font(AppTypography.bold(12))
                    .foregroundStyle(AppColors.primaryText)
                Spacer()
                Text(String(format: slider.valueFormat, slider.value.wrappedValue))
                    .font(AppTypography.bold(12))
                    .foregroundStyle(AppColors.primaryBlue)
            }

            AppSlider(value: slider.value, range: slider.range)
                .frame(height: layout.sliderHeight)
        }
    }

    private var primaryActionTitle: String {
        if isAIBackgroundMode {
            return hasAIBackgroundResult ? "Save to Photos" : "Process"
        }

        if isRemoveObjectMode {
            return hasObjectRemovalResult && objectRemovalStrokes.isEmpty && currentObjectRemovalStroke == nil
                ? "Save to Photos"
                : "Remove Object"
        }
        return "Save to Photos"
    }

    private var primaryActionIcon: String {
        if isAIBackgroundMode {
            return hasAIBackgroundResult ? "square.and.arrow.down" : "sparkles"
        }

        return isRemoveObjectMode && !(hasObjectRemovalResult && objectRemovalStrokes.isEmpty && currentObjectRemovalStroke == nil)
            ? "sparkles"
            : "square.and.arrow.down"
    }

    private func primaryAction() {
        if isAIBackgroundMode {
            if hasAIBackgroundResult {
                saveToPhotos()
            } else {
                processAIBackground()
            }
            return
        }

        if isRemoveObjectMode {
            if hasObjectRemovalResult && objectRemovalStrokes.isEmpty && currentObjectRemovalStroke == nil {
                saveToPhotos()
            } else {
                processRemoveObject()
            }
            return
        }

        saveToPhotos()
    }

    private var aiBackgroundControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background")
                .font(AppTypography.semibold(16))
                .foregroundStyle(AppColors.primaryText)

            HStack(spacing: 24) {
                aiBackgroundOption(.none)
                aiBackgroundOption(.photo)
                aiBackgroundOption(.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aiBackgroundOption(_ selection: AIBackgroundSelection) -> some View {
        let isSelected = aiBackgroundSelection == selection
        let isLocked = hasAIBackgroundResult || isProcessingAIBackground

        return Button {
            guard !isLocked else {
                return
            }

            switch selection {
            case .none:
                aiBackgroundSelection = .none
            case .photo:
                aiBackgroundSelection = .photo
                isBackgroundPhotoPickerPresented = true
            case .color:
                withAnimation(.easeInOut(duration: 0.22)) {
                    isAIBackgroundColorSheetPresented = true
                }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.tertiaryText.opacity(0.2))
                        .frame(width: 40, height: 40)

                    aiBackgroundOptionIcon(selection)
                        .frame(width: 32, height: 32)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? AppColors.primaryBlue : Color.clear, lineWidth: 2)
                        .frame(width: 40, height: 40)
                }

                Text(selection.title)
                    .font(AppTypography.regular(12))
                    .foregroundStyle(isSelected ? AppColors.primaryBlue : AppColors.tertiaryText)
                    .frame(width: 48)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    @ViewBuilder
    private func aiBackgroundOptionIcon(_ selection: AIBackgroundSelection) -> some View {
        switch selection {
        case .none:
            CheckerboardBackground(squareSize: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .opacity(0.8)
        case .photo:
            if let aiBackgroundReferenceImage {
                Image(uiImage: aiBackgroundReferenceImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.tertiaryText)
            }
        case .color:
            Circle()
                .fill(Color(hex: selectedAIBackgroundColorHex).opacity(selectedAIBackgroundColorOpacity))
                .overlay(
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.white.opacity(0.9))
                )
        }
    }

    private func primaryActionButton(
        title: String,
        systemIcon: String,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColors.white.opacity(0.18))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(AppColors.white)
                                    .scaleEffect(0.58)
                            } else {
                                Image(systemName: systemIcon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColors.white)
                            }
                        }
                    )

                Text(isLoading ? "Processing" : title)
                    .font(AppTypography.medium(16))
                    .foregroundStyle(AppColors.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(AppColors.primaryBlue)
                    .shadow(color: AppColors.primaryBlue.opacity(0.38), radius: 4, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func renderCurrentImage() {
        if isBlurMode {
            renderCurrentBlurImage()
        } else if isRemoveObjectMode || isEraserMode {
            return
        } else {
            processedPreviewImage = renderer.renderQuality(
                image: previewSourceImage,
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                sharpness: sharpness
            )
        }
    }

    private func renderCurrentBlurImage() {
        blurRenderTask?.cancel()

        guard backgroundBlur > 0 else {
            processedPreviewImage = previewSourceImage
            shareImage = previewSourceImage
            return
        }

        let image = previewSourceImage
        let blurRadius = CGFloat(backgroundBlur)
        let renderID = imageProcessingID
        let mask = previewForegroundMask

        blurRenderTask = Task {
            do {
                try await Task.sleep(nanoseconds: 45_000_000)
                guard !Task.isCancelled, renderID == imageProcessingID else {
                    return
                }

                let foregroundMask: CIImage
                if let mask {
                    foregroundMask = mask
                } else {
                    foregroundMask = try await blurProcessor.foregroundMask(image: image)
                }

                guard !Task.isCancelled, renderID == imageProcessingID else {
                    return
                }

                if previewForegroundMask == nil {
                    previewForegroundMask = foregroundMask
                }
                let result = try await blurProcessor.blurBackground(
                    image: image,
                    blurRadius: blurRadius,
                    foregroundMask: foregroundMask
                )
                guard !Task.isCancelled, renderID == imageProcessingID else {
                    return
                }
                processedPreviewImage = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, renderID == imageProcessingID else {
                    return
                }
                processedPreviewImage = renderer.renderBlurBackground(
                    image: image,
                    blurRadius: backgroundBlur,
                    foregroundMask: previewForegroundMask
                )
            }
        }
    }

    private func reset(with image: UIImage) {
        blurRenderTask?.cancel()
        let previewImage = image.qualityPreviewImage(maxPixelDimension: isBlurMode ? 540 : 720)
        originalImage = image
        sourceImage = image
        previewSourceImage = previewImage
        processedPreviewImage = previewImage
        shareImage = previewImage
        previewForegroundMask = nil
        objectRemovalStrokes = []
        currentObjectRemovalStroke = nil
        cancelObjectRemoval()
        cancelAIBackground()
        hasObjectRemovalResult = false
        hasAIBackgroundResult = false
        aiBackgroundSelection = .none
        aiBackgroundReferenceImage = nil
        selectedAIBackgroundColorOpacity = 1
        backgroundPhotoPickerItem = nil
        brightness = 0
        contrast = 1
        saturation = 1
        sharpness = 0
        backgroundBlur = 12
        brushSize = 28
        imageProcessingID = UUID()
    }

    private func resetEdits() {
        blurRenderTask?.cancel()
        if isAIBackgroundMode {
            cancelAIBackground()
            let previewImage = originalImage.qualityPreviewImage()
            sourceImage = originalImage
            previewSourceImage = previewImage
            processedPreviewImage = previewImage
            shareImage = previewImage
            hasAIBackgroundResult = false
            aiBackgroundSelection = .none
            aiBackgroundReferenceImage = nil
            selectedAIBackgroundColorOpacity = 1
            backgroundPhotoPickerItem = nil
            return
        }

        if isRemoveObjectMode || isEraserMode {
            cancelObjectRemoval()
            let previewImage = originalImage.qualityPreviewImage()
            sourceImage = originalImage
            previewSourceImage = previewImage
            processedPreviewImage = previewImage
            shareImage = previewImage
            objectRemovalStrokes = []
            currentObjectRemovalStroke = nil
            hasObjectRemovalResult = false
            brushSize = 28
            return
        }

        brightness = 0
        contrast = 1
        saturation = 1
        sharpness = 0
        backgroundBlur = 0
        processedPreviewImage = previewSourceImage
        shareImage = previewSourceImage
    }

    private func renderOutputImage() async -> UIImage {
        let image = sourceImage
        let isBlurMode = isBlurMode
        let isRemoveObjectMode = isRemoveObjectMode
        let isEraserMode = isEraserMode
        let isAIBackgroundMode = isAIBackgroundMode
        let brightness = brightness
        let contrast = contrast
        let saturation = saturation
        let sharpness = sharpness
        let backgroundBlur = backgroundBlur
        let strokes = currentObjectRemovalStroke.map { objectRemovalStrokes + [$0] } ?? objectRemovalStrokes

        return await Task.detached(priority: .userInitiated) {
            let renderer = QualityImageRenderer()
            if isEraserMode {
                return renderer.renderEraser(image: image, strokes: strokes)
            }

            if isRemoveObjectMode || isAIBackgroundMode {
                return image
            }

            if isBlurMode {
                do {
                    return try await BackgroundBlurProcessor.shared.blurBackground(
                        image: image,
                        blurRadius: CGFloat(backgroundBlur)
                    )
                } catch {
                    let mask = renderer.foregroundMask(for: image)
                    return renderer.renderBlurBackground(
                        image: image,
                        blurRadius: backgroundBlur,
                        foregroundMask: mask
                    )
                }
            }

            return renderer.renderQuality(
                image: image,
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                sharpness: sharpness
            )
        }.value
    }

    private func processRemoveObject() {
        let strokes = currentObjectRemovalStroke.map { objectRemovalStrokes + [$0] } ?? objectRemovalStrokes
        guard !strokes.isEmpty else {
            alertMessage = "Brush over the object you want to remove."
            return
        }

        startObjectRemovalProgress(status: "Preparing image")
        let originalSize = sourceImage.size
        objectRemovalTask = Task {
            do {
                updateObjectRemovalProgress(0.12, status: "Preparing mask")
                let payload = try ObjectRemovalMaskRenderer.editPayload(
                    image: sourceImage,
                    strokes: strokes
                )
                updateObjectRemovalProgress(0.18, status: "Uploading image")
                let rawResult = try await OpenAIImageEditService.shared.removeObject(payload: payload)
                try Task.checkCancellation()
                updateObjectRemovalProgress(0.96, status: "Applying result")
                let result = rawResult.resizedToFill(size: originalSize)
                let previewImage = result.qualityPreviewImage()
                sourceImage = result
                previewSourceImage = previewImage
                processedPreviewImage = previewImage
                shareImage = result
                objectRemovalStrokes = []
                currentObjectRemovalStroke = nil
                hasObjectRemovalResult = true
                completeObjectRemovalProgress()
                try? await Task.sleep(nanoseconds: 260_000_000)
                isProcessingObjectRemoval = false
                objectRemovalStatus = "Processing"
                objectRemovalProgress = 0
                objectRemovalTask = nil
                objectRemovalProgressTask?.cancel()
                objectRemovalProgressTask = nil
            } catch is CancellationError {
                objectRemovalTask = nil
            } catch {
                isProcessingObjectRemoval = false
                objectRemovalStatus = "Processing"
                objectRemovalProgress = 0
                objectRemovalTask = nil
                objectRemovalProgressTask?.cancel()
                objectRemovalProgressTask = nil
                alertMessage = error.localizedDescription
            }
        }
    }

    private func loadAIBackgroundReference(from item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        Task {
            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else {
                    alertMessage = "Could not load this background photo."
                    return
                }

                aiBackgroundReferenceImage = image
                aiBackgroundSelection = .photo
                hasAIBackgroundResult = false
            } catch {
                alertMessage = "Could not load this background photo."
            }
        }
    }

    private func processAIBackground() {
        if aiBackgroundSelection == .photo, aiBackgroundReferenceImage == nil {
            alertMessage = "Choose a background photo first."
            isBackgroundPhotoPickerPresented = true
            return
        }

        startAIBackgroundProgress(status: "Preparing image")
        let originalSize = sourceImage.size
        let selection = aiBackgroundSelection
        let colorHex = selectedAIBackgroundColorHex
        let colorOpacity = selectedAIBackgroundColorOpacity
        let referenceImage = aiBackgroundReferenceImage

        aiBackgroundTask = Task {
            do {
                updateAIBackgroundProgress(0.12, status: "Preparing image")
                let payload = try AIBackgroundEditPayload.make(
                    image: sourceImage,
                    selection: selection,
                    colorHex: colorHex,
                    colorOpacity: colorOpacity,
                    referenceImage: referenceImage
                )

                updateAIBackgroundProgress(0.18, status: "Uploading image")
                let rawResult = try await OpenAIImageEditService.shared.editBackground(payload: payload)
                try Task.checkCancellation()
                updateAIBackgroundProgress(0.96, status: "Applying result")

                let result = rawResult.resizedToFill(size: originalSize)
                let previewImage = result.qualityPreviewImage()
                sourceImage = result
                previewSourceImage = previewImage
                processedPreviewImage = previewImage
                shareImage = result
                hasAIBackgroundResult = true
                completeAIBackgroundProgress()
                try? await Task.sleep(nanoseconds: 260_000_000)
                isProcessingAIBackground = false
                aiBackgroundStatus = "Processing"
                aiBackgroundProgress = 0
                aiBackgroundTask = nil
                aiBackgroundProgressTask?.cancel()
                aiBackgroundProgressTask = nil
            } catch is CancellationError {
                aiBackgroundTask = nil
            } catch {
                isProcessingAIBackground = false
                aiBackgroundStatus = "Processing"
                aiBackgroundProgress = 0
                aiBackgroundTask = nil
                aiBackgroundProgressTask?.cancel()
                aiBackgroundProgressTask = nil
                alertMessage = error.localizedDescription
            }
        }
    }

    private func startAIBackgroundProgress(status: String) {
        aiBackgroundTask?.cancel()
        aiBackgroundProgressTask?.cancel()
        isProcessingAIBackground = true
        aiBackgroundProgress = 0.04
        aiBackgroundStatus = status

        aiBackgroundProgressTask = Task {
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }

                let elapsed = Date().timeIntervalSince(start)
                let estimatedDuration = 55.0
                let simulated = min(0.92, 0.18 + elapsed / estimatedDuration * 0.74)
                if simulated > aiBackgroundProgress {
                    aiBackgroundProgress = simulated
                }

                if aiBackgroundProgress < 0.20 {
                    aiBackgroundStatus = "Uploading image"
                } else if aiBackgroundProgress < 0.86 {
                    aiBackgroundStatus = "Processing image"
                } else {
                    aiBackgroundStatus = "Finalizing result"
                }
            }
        }
    }

    private func updateAIBackgroundProgress(_ progress: Double, status: String) {
        aiBackgroundProgress = max(aiBackgroundProgress, progress)
        aiBackgroundStatus = status
    }

    private func completeAIBackgroundProgress() {
        aiBackgroundProgressTask?.cancel()
        aiBackgroundProgressTask = nil
        aiBackgroundProgress = 1
        switch aiBackgroundSelection {
        case .none:
            aiBackgroundStatus = "Background removed"
        case .photo, .color:
            aiBackgroundStatus = "Background replaced"
        }
    }

    private func cancelAIBackground(showAlert: Bool = false) {
        let hadActiveTask = aiBackgroundTask != nil || isProcessingAIBackground
        aiBackgroundTask?.cancel()
        aiBackgroundProgressTask?.cancel()
        aiBackgroundTask = nil
        aiBackgroundProgressTask = nil
        isProcessingAIBackground = false
        aiBackgroundStatus = "Processing"
        aiBackgroundProgress = 0
        if showAlert && hadActiveTask {
            alertMessage = "AI analysis cancelled."
        }
    }

    private func startObjectRemovalProgress(status: String) {
        objectRemovalTask?.cancel()
        objectRemovalProgressTask?.cancel()
        isProcessingObjectRemoval = true
        objectRemovalProgress = 0.04
        objectRemovalStatus = status

        objectRemovalProgressTask = Task {
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }

                let elapsed = Date().timeIntervalSince(start)
                let estimatedDuration = 55.0
                let simulated = min(0.92, 0.18 + elapsed / estimatedDuration * 0.74)
                if simulated > objectRemovalProgress {
                    objectRemovalProgress = simulated
                }

                if objectRemovalProgress < 0.20 {
                    objectRemovalStatus = "Uploading image"
                } else if objectRemovalProgress < 0.86 {
                    objectRemovalStatus = "Processing image"
                } else {
                    objectRemovalStatus = "Finalizing result"
                }
            }
        }
    }

    private func updateObjectRemovalProgress(_ progress: Double, status: String) {
        objectRemovalProgress = max(objectRemovalProgress, progress)
        objectRemovalStatus = status
    }

    private func completeObjectRemovalProgress() {
        objectRemovalProgressTask?.cancel()
        objectRemovalProgressTask = nil
        objectRemovalProgress = 1
        objectRemovalStatus = "Object removed"
    }

    private func cancelObjectRemoval(showAlert: Bool = false) {
        let hadActiveTask = objectRemovalTask != nil || isProcessingObjectRemoval
        objectRemovalTask?.cancel()
        objectRemovalProgressTask?.cancel()
        objectRemovalTask = nil
        objectRemovalProgressTask = nil
        isProcessingObjectRemoval = false
        objectRemovalStatus = "Processing"
        objectRemovalProgress = 0
        if showAlert && hadActiveTask {
            alertMessage = "AI analysis cancelled."
        }
    }

    private func shareCurrentImage() {
        Task {
            shareImage = await renderOutputImage()
            isSharePresented = true
        }
    }

    private func prepareForegroundMaskIfNeeded() async {
        guard isBlurMode else {
            return
        }

        let id = imageProcessingID
        let image = previewSourceImage

        do {
            let mask = try await blurProcessor.foregroundMask(image: image)
            guard id == imageProcessingID else {
                return
            }
            previewForegroundMask = mask
            renderCurrentImage()
        } catch {
            guard id == imageProcessingID else {
                return
            }
            previewForegroundMask = renderer.foregroundMask(for: image)
            renderCurrentImage()
        }
    }

    private func saveToPhotos() {
        Task {
            let outputImage = await renderOutputImage()
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                alertMessage = "Allow photo access in Settings to save the image."
                return
            }

            do {
                guard let pngData = outputImage.pngData() else {
                    alertMessage = "Could not prepare this image as PNG."
                    return
                }

                try await PHPhotoLibrary.shared().performChanges {
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = UTType.png.identifier
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .photo, data: pngData, options: options)
                }
                successImage = outputImage
                withAnimation(.easeInOut(duration: 0.22)) {
                    isSuccessPresented = true
                }
            } catch {
                alertMessage = "Could not save this image. Please try again."
            }
        }
    }
}

private struct EditorSlider: Identifiable {
    var id: String { title }
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let valueFormat: String
}

private struct QualityEditorLayout {
    let width: CGFloat
    let height: CGFloat
    let sliderCount: Int
    let isBlurMode: Bool

    private var isCompact: Bool {
        height < 700
    }

    var headerTop: CGFloat {
        isCompact ? 8 : 16
    }

    var imageTop: CGFloat {
        isCompact ? 12 : 27
    }

    var slidersTop: CGFloat {
        isCompact ? 12 : 23
    }

    var sliderSpacing: CGFloat {
        if isBlurMode {
            return 0
        }
        return isCompact ? 6 : 10
    }

    var sliderLabelGap: CGFloat {
        isCompact ? 2 : 4
    }

    var sliderHeight: CGFloat {
        isCompact ? 24 : 26
    }

    var saveTop: CGFloat {
        isCompact ? 10 : 24
    }

    var processTop: CGFloat {
        isCompact ? 0 : 4
    }

    var processHeight: CGFloat {
        isCompact ? 36 : 44
    }

    var bottomPadding: CGFloat {
        isCompact ? 6 : 12
    }

    var previewSize: CGSize {
        let previewAspect = isBlurMode ? CGFloat(1.0) : CGFloat(309.0 / 321.0)
        let labelHeight: CGFloat = 15
        let sliderRowHeight = labelHeight + sliderLabelGap + sliderHeight
        let sliderBlockHeight = sliderRowHeight * CGFloat(sliderCount) + sliderSpacing * CGFloat(max(sliderCount - 1, 0))
        let fixedHeight = headerTop + 32 + imageTop + slidersTop + sliderBlockHeight + saveTop + 54 + processTop + processHeight + bottomPadding
        let availablePreviewHeight = max(140, height - fixedHeight)
        let maxPreviewHeight: CGFloat
        if isCompact {
            maxPreviewHeight = isBlurMode ? 280 : 270
        } else {
            maxPreviewHeight = isBlurMode ? 430 : 321
        }
        let previewHeight = min(maxPreviewHeight, availablePreviewHeight)
        let availablePreviewWidth = max(140, width - 84)
        let previewWidth = min(availablePreviewWidth, previewHeight * previewAspect)
        let safePreviewWidth = max(140, previewWidth)
        let safePreviewHeight = max(140, safePreviewWidth / previewAspect)

        return CGSize(width: safePreviewWidth, height: safePreviewHeight)
    }
}

private struct AIBackgroundEditorLayout {
    let width: CGFloat
    let height: CGFloat

    private var isCompact: Bool {
        height < 760
    }

    var headerTop: CGFloat {
        isCompact ? 8 : 16
    }

    var imageTop: CGFloat {
        isCompact ? 14 : 27
    }

    var controlsTop: CGFloat {
        isCompact ? 16 : 56
    }

    var saveTop: CGFloat {
        isCompact ? 14 : 20
    }

    var processTop: CGFloat {
        isCompact ? 0 : 4
    }

    var processHeight: CGFloat {
        isCompact ? 36 : 44
    }

    var bottomPadding: CGFloat {
        isCompact ? 6 : 12
    }

    var previewSize: CGSize {
        let maxWidth = max(140, width - 36)
        let maxHeight = max(220, height - headerTop - 32 - imageTop - controlsTop - 83 - saveTop - 54 - processTop - processHeight - bottomPadding)
        let compactPreviewHeight = isCompact ? min(maxHeight, 330) : maxHeight
        let figmaWidth = min(356, maxWidth)
        let figmaHeight = figmaWidth * (414 / 356)
        let height = min(414, min(figmaHeight, compactPreviewHeight))
        let width = min(figmaWidth, height * (356 / 414))
        return CGSize(width: max(140, width), height: max(220, height))
    }
}

private struct ObjectRemovalProcessingView: View {
    let image: UIImage
    let progress: Double
    let status: String
    let finalStepTitle: String
    let onCancel: () -> Void

    private var percent: Int {
        Int((min(max(progress, 0), 1) * 100).rounded())
    }

    var body: some View {
        GeometryReader { proxy in
            let heightScale = min(max(proxy.size.height / 852, 0.86), 1.08)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                Spacer()
                    .frame(height: 51 * heightScale)

                imageStage

                Spacer()
                    .frame(height: 53 * heightScale)

                Text("Analyzing image...")
                    .font(AppTypography.bold(16))
                    .foregroundStyle(AppColors.primaryText)

                Text("AI Processing")
                    .font(AppTypography.regular(14))
                    .foregroundStyle(AppColors.tertiaryText)
                    .padding(.top, 4)

                Text("\(percent)%")
                    .font(AppTypography.regular(14))
                    .foregroundStyle(AppColors.primaryText)
                    .padding(.top, 8)

                Spacer()
                    .frame(height: 65 * heightScale)

                processingSteps
                    .padding(.horizontal, 33)

                Spacer(minLength: 30)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AppTypography.medium(16))
                        .foregroundStyle(AppColors.tertiaryText)
                        .frame(width: 356, height: 54)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 62 * heightScale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Text("Progressing")
                .font(AppTypography.bold(20))
                .foregroundStyle(AppColors.primaryText)

            Spacer()
        }
        .frame(height: 32)
    }

    private var imageStage: some View {
        ZStack {
            ProcessingCornerGuides()
                .stroke(AppColors.tertiaryText.opacity(0.32), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 282, height: 282)

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(width: 282, height: 282)
    }

    private var processingSteps: some View {
        ZStack {
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: 24)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "D9D9D9"), Color(hex: "737373").opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                Spacer()
                    .frame(width: 24)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "D9D9D9"), Color(hex: "737373").opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                Spacer()
                    .frame(width: 24)
            }
            .padding(.bottom, 23)

            HStack(alignment: .top) {
                step(title: "Image Uploaded", state: .done)

                Spacer()

                step(title: "AI Processing", state: progress >= 0.92 ? .done : .done)

                Spacer()

                step(title: finalStepTitle, state: progress >= 1 ? .done : .loading)
            }
        }
        .frame(height: 55)
    }

    private func step(title: String, state: ProcessingStepState) -> some View {
        VStack(spacing: 8) {
            switch state {
            case .done:
                ZStack {
                    Circle()
                        .fill(AppColors.primaryBlue)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.white)
                }
                    .frame(width: 24, height: 24)
            case .loading:
                ProgressView()
                    .tint(AppColors.tertiaryText)
                    .frame(width: 24, height: 24)
            }

            Text(title)
                .font(AppTypography.regular(10))
                .foregroundStyle(state == .loading ? AppColors.tertiaryText : AppColors.primaryBlue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 94)
        }
    }
}

private enum ProcessingStepState {
    case done
    case loading
}

private struct AIBackgroundColorSheet: View {
    @Binding var selectedHex: String
    @Binding var opacity: Double
    let onContinue: () -> Void
    let onCancel: () -> Void

    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var hexText: String

    private let swatches = [
        "EF4444", "F97316", "FACC15", "4ADE80", "2DD4BF", "3B82F6", "6366F1",
        "EC4899", "F43F5E", "D946EF", "8B5CF6", "0EA5E9", "10B981", "84CC16"
    ]

    init(
        selectedHex: Binding<String>,
        opacity: Binding<Double>,
        onContinue: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _selectedHex = selectedHex
        _opacity = opacity
        self.onContinue = onContinue
        self.onCancel = onCancel

        let hsb = UIColor.hsbValues(hex: selectedHex.wrappedValue)
        _hue = State(initialValue: hsb.hue)
        _saturation = State(initialValue: hsb.saturation)
        _brightness = State(initialValue: hsb.brightness)
        _hexText = State(initialValue: selectedHex.wrappedValue.uppercased())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.black.opacity(0.18)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                Capsule()
                    .fill(AppColors.black.opacity(0.3))
                    .frame(width: 36, height: 6)
                    .padding(.top, 10)

                colorSpace
                    .padding(.horizontal, 23)
                    .padding(.top, 40)

                hueSlider
                    .padding(.horizontal, 23)
                    .padding(.top, 24)

                opacitySlider
                    .padding(.horizontal, 23)
                    .padding(.top, 24)

                HStack(spacing: 8) {
                    colorField("Hex")
                        .frame(width: 69)
                    hexInputField
                        .frame(width: 86)
                    opacityInputField
                        .frame(width: 62)
                    Spacer()
                }
                .padding(.horizontal, 23)
                .padding(.top, 16)

                HStack {
                    Text("Saved colors:")
                        .font(AppTypography.medium(16))
                        .foregroundStyle(AppColors.primaryText)
                    Spacer()
                    Text("+ Add")
                        .font(AppTypography.medium(16))
                        .foregroundStyle(AppColors.tertiaryText)
                }
                .padding(.horizontal, 23)
                .padding(.top, 16)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 7), spacing: 12) {
                    ForEach(swatches, id: \.self) { hex in
                        Button {
                            applyHex(hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(AppColors.white, lineWidth: selectedHex == hex ? 3 : 0)
                                )
                                .shadow(color: selectedHex == hex ? AppColors.black.opacity(0.25) : .clear, radius: 0, x: 0, y: 0)
                                .overlay(
                                    Circle()
                                        .stroke(selectedHex == hex ? AppColors.black.opacity(0.25) : .clear, lineWidth: 3)
                                        .frame(width: 44, height: 44)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 23)
                .padding(.top, 12)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(AppTypography.medium(16))
                        .foregroundStyle(AppColors.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(AppColors.primaryBlue)
                                .shadow(color: AppColors.primaryBlue.opacity(0.38), radius: 4, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.top, 24)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AppTypography.medium(16))
                        .foregroundStyle(AppColors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                    .fill(AppColors.white)
            )
        }
        .ignoresSafeArea()
    }

    private var colorSpace: some View {
        GeometryReader { proxy in
            let size = proxy.size

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hue: hue, saturation: 1, brightness: 1))
                .overlay(
                    LinearGradient(
                        colors: [AppColors.white, AppColors.white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [Color.clear, AppColors.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .topLeading) {
                    Circle()
                        .stroke(AppColors.white, lineWidth: 3)
                        .shadow(color: AppColors.black.opacity(0.25), radius: 3)
                        .frame(width: 22, height: 22)
                        .offset(
                            x: max(0, min(size.width, saturation * size.width)) - 11,
                            y: max(0, min(size.height, (1 - brightness) * size.height)) - 11
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateSaturationBrightness(location: value.location, size: size)
                        }
                )
        }
        .frame(height: 228)
    }

    private var hueSlider: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            RoundedRectangle(cornerRadius: 150, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 12)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Color(hue: hue, saturation: 1, brightness: 1))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(AppColors.white, lineWidth: 3))
                        .shadow(color: AppColors.black.opacity(0.18), radius: 2, y: 1)
                        .offset(x: max(0, min(width - 18, hue * width - 9)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateHue(location: value.location, width: width)
                        }
                )
        }
        .frame(height: 18)
    }

    private var opacitySlider: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            RoundedRectangle(cornerRadius: 150, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: selectedHex).opacity(0.05), Color(hex: selectedHex)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 12)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Color(hex: selectedHex).opacity(opacity))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(AppColors.white, lineWidth: 3))
                        .shadow(color: AppColors.black.opacity(0.18), radius: 2, y: 1)
                        .offset(x: max(0, min(width - 18, opacity * width - 9)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateOpacity(location: value.location, width: width)
                        }
                )
        }
        .frame(height: 18)
    }

    private var hexInputField: some View {
        HStack(spacing: 2) {
            Text("#")
                .foregroundStyle(Color(hex: "9CA3AF"))

            TextField("", text: $hexText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .onChange(of: hexText) { _, value in
                    let sanitized = sanitizedHex(value)
                    guard sanitized == value else {
                        hexText = sanitized
                        return
                    }

                    if sanitized.count == 6 {
                        applyHex(sanitized)
                    }
                }
        }
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(Color(hex: "374151"))
        .padding(.horizontal, 6)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fieldBackground)
    }

    private var opacityInputField: some View {
        TextField("", text: Binding(
            get: { "\(Int((opacity * 100).rounded()))%" },
            set: { value in
                let digits = value.filter(\.isNumber)
                guard let percent = Double(digits) else {
                    return
                }
                opacity = min(max(percent, 0), 100) / 100
            }
        ))
        .keyboardType(.numberPad)
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(Color(hex: "374151"))
        .padding(.horizontal, 6)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fieldBackground)
    }

    private func colorField(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color(hex: "374151"))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fieldBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppColors.white)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
            )
            .shadow(color: Color(hex: "1F2937").opacity(0.08), radius: 2, y: 1)
    }

    private func updateSaturationBrightness(location: CGPoint, size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        saturation = min(max(location.x / size.width, 0), 1)
        brightness = 1 - min(max(location.y / size.height, 0), 1)
        updateHexFromHSB()
    }

    private func updateHue(location: CGPoint, width: CGFloat) {
        guard width > 0 else {
            return
        }

        hue = min(max(location.x / width, 0), 1)
        updateHexFromHSB()
    }

    private func updateOpacity(location: CGPoint, width: CGFloat) {
        guard width > 0 else {
            return
        }

        opacity = min(max(location.x / width, 0), 1)
    }

    private func updateHexFromHSB() {
        let hex = UIColor.hexString(hue: hue, saturation: saturation, brightness: brightness)
        selectedHex = hex
        hexText = hex
    }

    private func applyHex(_ hex: String) {
        let sanitized = sanitizedHex(hex)
        guard sanitized.count == 6 else {
            return
        }

        selectedHex = sanitized
        hexText = sanitized
        let hsb = UIColor.hsbValues(hex: sanitized)
        hue = hsb.hue
        saturation = hsb.saturation
        brightness = hsb.brightness
    }

    private func sanitizedHex(_ value: String) -> String {
        String(value
            .uppercased()
            .filter { $0.isNumber || ("A"..."F").contains(String($0)) }
            .prefix(6))
    }
}

private extension UIColor {
    static func hsbValues(hex: String) -> (hue: Double, saturation: Double, brightness: Double) {
        let cleaned = String(hex
            .uppercased()
            .filter { $0.isNumber || ("A"..."F").contains(String($0)) }
            .prefix(6))

        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255
        let color = UIColor(red: red, green: green, blue: blue, alpha: 1)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return (Double(hue), Double(saturation), Double(brightness))
    }

    static func hexString(hue: Double, saturation: Double, brightness: Double) -> String {
        let color = UIColor(
            hue: CGFloat(min(max(hue, 0), 1)),
            saturation: CGFloat(min(max(saturation, 0), 1)),
            brightness: CGFloat(min(max(brightness, 0), 1)),
            alpha: 1
        )

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

private struct ProcessingCornerGuides: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner: CGFloat = 24
        let length: CGFloat = 64

        func addCorner(x: CGFloat, y: CGFloat, horizontalSign: CGFloat, verticalSign: CGFloat) {
            let horizontalEnd = CGPoint(x: x + horizontalSign * length, y: y)
            let verticalEnd = CGPoint(x: x, y: y + verticalSign * length)

            path.move(to: CGPoint(x: x + horizontalSign * corner, y: y))
            path.addLine(to: horizontalEnd)
            path.move(to: CGPoint(x: x, y: y + verticalSign * corner))
            path.addLine(to: verticalEnd)
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

private struct ObjectRemovalBrushOverlay: View {
    let imageSize: CGSize
    let previewSize: CGSize
    let brushSize: CGFloat
    @Binding var strokes: [ObjectRemovalStroke]
    @Binding var currentStroke: ObjectRemovalStroke?

    var body: some View {
        Canvas { context, size in
            draw(strokes, in: context, size: size)
            if let currentStroke {
                draw([currentStroke], in: context, size: size)
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let point = normalizedImagePoint(from: value.location, canvasSize: previewSize) else {
                        return
                    }

                    if currentStroke == nil {
                        let displayedSize = displayedImageSize(in: previewSize)
                        currentStroke = ObjectRemovalStroke(
                            points: [point],
                            normalizedBrushDiameter: brushSize / max(1, min(displayedSize.width, displayedSize.height))
                        )
                    } else {
                        var updatedStroke = currentStroke
                        updatedStroke?.points.append(point)
                        currentStroke = updatedStroke
                    }
                }
                .onEnded { _ in
                    if let currentStroke, !currentStroke.points.isEmpty {
                        strokes.append(currentStroke)
                    }
                    currentStroke = nil
                }
        )
    }

    private func draw(
        _ strokes: [ObjectRemovalStroke],
        in context: GraphicsContext,
        size: CGSize
    ) {
        let displayedSize = displayedImageSize(in: size)
        for stroke in strokes {
            let lineWidth = max(2, stroke.normalizedBrushDiameter * min(displayedSize.width, displayedSize.height))
            guard let firstPoint = stroke.points.first else {
                continue
            }

            if stroke.points.count == 1 {
                let point = displayPoint(from: firstPoint, canvasSize: size)
                let radius = lineWidth * 0.5
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(AppColors.primaryBlue.opacity(0.55))
                )
                continue
            }

            var path = Path()
            path.move(to: displayPoint(from: firstPoint, canvasSize: size))
            stroke.points.dropFirst().forEach { point in
                path.addLine(to: displayPoint(from: point, canvasSize: size))
            }

            context.stroke(
                path,
                with: .color(AppColors.primaryBlue.opacity(0.55)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func normalizedImagePoint(from location: CGPoint, canvasSize: CGSize) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (canvasSize.width - displayedSize.width) * 0.5,
            y: (canvasSize.height - displayedSize.height) * 0.5
        )
        let x = (location.x - origin.x) / displayedSize.width
        let y = (location.y - origin.y) / displayedSize.height

        guard x >= 0, x <= 1, y >= 0, y <= 1 else {
            return nil
        }

        return CGPoint(x: x, y: y)
    }

    private func displayPoint(from normalizedPoint: CGPoint, canvasSize: CGSize) -> CGPoint {
        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (canvasSize.width - displayedSize.width) * 0.5,
            y: (canvasSize.height - displayedSize.height) * 0.5
        )

        return CGPoint(
            x: origin.x + normalizedPoint.x * displayedSize.width,
            y: origin.y + normalizedPoint.y * displayedSize.height
        )
    }

    private func displayedImageSize(in canvasSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else {
            return canvasSize
        }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct EraserBrushOverlay: View {
    let imageSize: CGSize
    let previewSize: CGSize
    let brushSize: CGFloat
    @Binding var strokes: [ObjectRemovalStroke]
    @Binding var currentStroke: ObjectRemovalStroke?

    var body: some View {
        Canvas { context, size in
            draw(strokes, in: context, size: size)
            if let currentStroke {
                draw([currentStroke], in: context, size: size)
            }
        }
        .blendMode(.destinationOut)
        .frame(width: previewSize.width, height: previewSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let point = normalizedImagePoint(from: value.location, canvasSize: previewSize) else {
                        return
                    }

                    if currentStroke == nil {
                        let displayedSize = displayedImageSize(in: previewSize)
                        currentStroke = ObjectRemovalStroke(
                            points: [point],
                            normalizedBrushDiameter: brushSize / max(1, min(displayedSize.width, displayedSize.height))
                        )
                    } else {
                        var updatedStroke = currentStroke
                        updatedStroke?.points.append(point)
                        currentStroke = updatedStroke
                    }
                }
                .onEnded { _ in
                    if let currentStroke, !currentStroke.points.isEmpty {
                        strokes.append(currentStroke)
                    }
                    currentStroke = nil
                }
        )
    }

    private func draw(
        _ strokes: [ObjectRemovalStroke],
        in context: GraphicsContext,
        size: CGSize
    ) {
        let displayedSize = displayedImageSize(in: size)
        for stroke in strokes {
            let lineWidth = max(2, stroke.normalizedBrushDiameter * min(displayedSize.width, displayedSize.height))
            guard let firstPoint = stroke.points.first else {
                continue
            }

            if stroke.points.count == 1 {
                let point = displayPoint(from: firstPoint, canvasSize: size)
                let radius = lineWidth * 0.5
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(.white)
                )
                continue
            }

            var path = Path()
            path.move(to: displayPoint(from: firstPoint, canvasSize: size))
            stroke.points.dropFirst().forEach { point in
                path.addLine(to: displayPoint(from: point, canvasSize: size))
            }

            context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func normalizedImagePoint(from location: CGPoint, canvasSize: CGSize) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (canvasSize.width - displayedSize.width) * 0.5,
            y: (canvasSize.height - displayedSize.height) * 0.5
        )
        let x = (location.x - origin.x) / displayedSize.width
        let y = (location.y - origin.y) / displayedSize.height

        guard x >= 0, x <= 1, y >= 0, y <= 1 else {
            return nil
        }

        return CGPoint(x: x, y: y)
    }

    private func displayPoint(from normalizedPoint: CGPoint, canvasSize: CGSize) -> CGPoint {
        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (canvasSize.width - displayedSize.width) * 0.5,
            y: (canvasSize.height - displayedSize.height) * 0.5
        )

        return CGPoint(
            x: origin.x + normalizedPoint.x * displayedSize.width,
            y: origin.y + normalizedPoint.y * displayedSize.height
        )
    }

    private func displayedImageSize(in canvasSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else {
            return canvasSize
        }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct QualityImageRenderer {
    private let context = CIContext()

    nonisolated init() {}

    nonisolated func renderQuality(
        image: UIImage,
        brightness: Double,
        contrast: Double,
        saturation: Double,
        sharpness: Double
    ) -> UIImage {
        guard let inputImage = CIImage(image: image)?.oriented(forExifOrientation: image.imageOrientation.exifOrientation) else {
            return image
        }

        let colorFilter = CIFilter.colorControls()
        colorFilter.inputImage = inputImage
        colorFilter.brightness = Float(brightness)
        colorFilter.contrast = Float(contrast)
        colorFilter.saturation = Float(saturation)

        let sharpenFilter = CIFilter.sharpenLuminance()
        sharpenFilter.inputImage = colorFilter.outputImage
        sharpenFilter.sharpness = Float(sharpness)

        guard
            let outputImage = sharpenFilter.outputImage,
            let cgImage = context.createCGImage(outputImage, from: inputImage.extent)
        else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    nonisolated func renderBlurBackground(
        image: UIImage,
        blurRadius: Double,
        foregroundMask: CIImage?
    ) -> UIImage {
        guard blurRadius > 0 else {
            return image
        }

        guard let inputImage = CIImage(image: image)?.oriented(forExifOrientation: image.imageOrientation.exifOrientation) else {
            return image
        }

        let mask = foregroundMask ?? fallbackForegroundMask(for: inputImage.extent)

        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = inputImage.clampedToExtent()
        blurFilter.radius = Float(blurRadius)

        guard let blurredImage = blurFilter.outputImage?.cropped(to: inputImage.extent) else {
            return image
        }

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = inputImage
        blendFilter.backgroundImage = blurredImage
        blendFilter.maskImage = mask.matchingExtent(inputImage.extent)

        guard
            let outputImage = blendFilter.outputImage,
            let cgImage = context.createCGImage(outputImage, from: inputImage.extent)
        else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    nonisolated func renderEraser(image: UIImage, strokes: [ObjectRemovalStroke]) -> UIImage {
        guard !strokes.isEmpty else {
            return image
        }

        let normalizedImage = image.normalizedForTransparentEditing()
        let size = normalizedImage.size
        guard size.width > 0, size.height > 0 else {
            return normalizedImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = normalizedImage.scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            normalizedImage.draw(in: CGRect(origin: .zero, size: size))

            let context = rendererContext.cgContext
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setBlendMode(.clear)
            context.setStrokeColor(UIColor.clear.cgColor)
            context.setFillColor(UIColor.clear.cgColor)

            for stroke in strokes {
                let lineWidth = max(2, stroke.normalizedBrushDiameter * min(size.width, size.height))
                context.setLineWidth(lineWidth)

                guard let firstPoint = stroke.points.first else {
                    continue
                }

                let firstPixelPoint = CGPoint(x: firstPoint.x * size.width, y: firstPoint.y * size.height)
                if stroke.points.count == 1 {
                    let radius = lineWidth * 0.5
                    context.fillEllipse(in: CGRect(
                        x: firstPixelPoint.x - radius,
                        y: firstPixelPoint.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                    continue
                }

                context.beginPath()
                context.move(to: firstPixelPoint)
                stroke.points.dropFirst().forEach { point in
                    context.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                context.strokePath()
            }
        }
    }

    nonisolated func foregroundMask(for image: UIImage) -> CIImage? {
        let targetExtent = image.pixelExtent

        if let instanceMask = foregroundInstanceMask(for: image),
           isUsableMask(instanceMask, targetExtent: targetExtent) {
            return instanceMask
        }

        if let personMask = personSegmentationMask(for: image),
           isUsableMask(personMask, targetExtent: targetExtent) {
            return personMask
        }

        if let saliencyMask = saliencyMask(for: image),
           isUsableMask(saliencyMask, targetExtent: targetExtent) {
            return saliencyMask
        }

        if let animalMask = animalMask(for: image) {
            return animalMask
        }

        return nil
    }

    nonisolated private func foregroundInstanceMask(for image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.imageOrientation.cgImagePropertyOrientation,
            options: [:]
        )

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                return nil
            }
            guard !observation.allInstances.isEmpty else {
                return nil
            }

            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            return CIImage(cvPixelBuffer: maskBuffer)
        } catch {
            return nil
        }
    }

    nonisolated private func personSegmentationMask(for image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.imageOrientation.cgImagePropertyOrientation,
            options: [:]
        )

        do {
            try handler.perform([request])
            guard let maskBuffer = request.results?.first?.pixelBuffer else {
                return nil
            }
            return CIImage(cvPixelBuffer: maskBuffer)
        } catch {
            return nil
        }
    }

    nonisolated private func animalMask(for image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.imageOrientation.cgImagePropertyOrientation,
            options: [:]
        )

        do {
            try handler.perform([request])
            guard
                let observation = request.results?
                    .filter({ observation in
                        guard let label = observation.labels.first else {
                            return false
                        }
                        return label.confidence >= 0.35 && (label.identifier == "Dog" || label.identifier == "Cat")
                    })
                    .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
            else {
                return nil
            }

            let extent = image.pixelExtent
            var subjectRect = VNImageRectForNormalizedRect(
                observation.boundingBox,
                Int(extent.width),
                Int(extent.height)
            )
            subjectRect = subjectRect.insetBy(dx: -subjectRect.width * 0.14, dy: -subjectRect.height * 0.12)
                .intersection(extent)

            return roundedRectMask(rect: subjectRect, extent: extent)
        } catch {
            return nil
        }
    }

    nonisolated private func saliencyMask(for image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.imageOrientation.cgImagePropertyOrientation,
            options: [:]
        )
        let objectnessRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attentionRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        do {
            try handler.perform([objectnessRequest, attentionRequest])

            let extent = image.pixelExtent
            let objectRects = saliencyRects(
                from: objectnessRequest.results,
                extent: extent,
                expansion: 0.16
            )
            if !objectRects.isEmpty {
                return roundedRectsMask(rects: objectRects, extent: extent)
            }

            let attentionRects = saliencyRects(
                from: attentionRequest.results,
                extent: extent,
                expansion: 0.2
            )
            if !attentionRects.isEmpty {
                return roundedRectsMask(rects: attentionRects, extent: extent)
            }

            if let heatMap = objectnessRequest.results?.first?.pixelBuffer {
                return CIImage(cvPixelBuffer: heatMap)
            }

            if let heatMap = attentionRequest.results?.first?.pixelBuffer {
                return CIImage(cvPixelBuffer: heatMap)
            }

            return nil
        } catch {
            return nil
        }
    }

    nonisolated private func saliencyRects(
        from observations: [VNSaliencyImageObservation]?,
        extent: CGRect,
        expansion: CGFloat
    ) -> [CGRect] {
        observations?
            .flatMap { $0.salientObjects ?? [] }
            .map { observation in
                let rect = VNImageRectForNormalizedRect(
                    observation.boundingBox,
                    Int(extent.width),
                    Int(extent.height)
                )
                return rect.insetBy(dx: -rect.width * expansion, dy: -rect.height * expansion)
                    .intersection(extent)
            }
            .filter { rect in
                let coverage = rect.width * rect.height / max(1, extent.width * extent.height)
                return rect.width > 8 && rect.height > 8 && coverage > 0.015 && coverage < 0.92
            } ?? []
    }

    nonisolated private func roundedRectMask(rect: CGRect, extent: CGRect) -> CIImage? {
        roundedRectsMask(rects: [rect], extent: extent)
    }

    nonisolated private func roundedRectsMask(rects: [CGRect], extent: CGRect) -> CIImage? {
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        let validRects = rects.filter { $0.width > 1 && $0.height > 1 && !$0.isNull && !$0.isInfinite }
        guard width > 0, height > 0, !validRects.isEmpty else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        bitmapContext.setFillColor(gray: 0, alpha: 1)
        bitmapContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

        bitmapContext.setFillColor(gray: 1, alpha: 1)
        validRects.forEach { rect in
            let radius = min(rect.width, rect.height) * 0.32
            bitmapContext.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            ))
        }
        bitmapContext.fillPath()

        guard let cgMask = bitmapContext.makeImage() else {
            return nil
        }

        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = CIImage(cgImage: cgMask).cropped(to: extent)
        blurFilter.radius = 8

        return blurFilter.outputImage?.cropped(to: extent)
    }

    nonisolated private func isUsableMask(_ mask: CIImage, targetExtent: CGRect) -> Bool {
        guard targetExtent.width > 0, targetExtent.height > 0 else {
            return false
        }

        let areaFilter = CIFilter.areaAverage()
        areaFilter.inputImage = mask.matchingExtent(targetExtent)
        areaFilter.extent = targetExtent

        guard let outputImage = areaFilter.outputImage else {
            return false
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let coverage = CGFloat(bitmap[0]) / 255
        return coverage > 0.035 && coverage < 0.9
    }

    nonisolated private func fallbackForegroundMask(for extent: CGRect) -> CIImage {
        let shortestSide = min(extent.width, extent.height)
        guard shortestSide > 0 else {
            return CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        }

        let filter = CIFilter.radialGradient()
        filter.center = CGPoint(x: extent.midX, y: extent.midY - shortestSide * 0.04)
        filter.radius0 = Float(shortestSide * 0.42)
        filter.radius1 = Float(shortestSide * 0.66)
        filter.color0 = CIColor(red: 1, green: 1, blue: 1)
        filter.color1 = CIColor(red: 0, green: 0, blue: 0)

        return filter.outputImage?.cropped(to: extent)
            ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
    }
}

private extension CIImage {
    nonisolated func matchingExtent(_ targetExtent: CGRect) -> CIImage {
        guard extent.width > 0, extent.height > 0 else {
            return self
        }

        let scaleX = targetExtent.width / extent.width
        let scaleY = targetExtent.height / extent.height
        return transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: targetExtent)
    }
}

private struct CheckerboardBackground: View {
    let squareSize: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let columns = Int(ceil(size.width / squareSize))
                let rows = Int(ceil(size.height / squareSize))

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
            .background(Color(hex: "F4F4F4"))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
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

private extension UIImage.Orientation {
    nonisolated var exifOrientation: Int32 {
        switch self {
        case .up:
            return 1
        case .down:
            return 3
        case .left:
            return 8
        case .right:
            return 6
        case .upMirrored:
            return 2
        case .downMirrored:
            return 4
        case .leftMirrored:
            return 5
        case .rightMirrored:
            return 7
        @unknown default:
            return 1
        }
    }

    nonisolated var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        case .upMirrored:
            return .upMirrored
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}

private extension UIImage {
    nonisolated var pixelExtent: CGRect {
        if let cgImage {
            return CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        }

        return CGRect(origin: .zero, size: size)
    }

    func qualityPreviewImage(maxPixelDimension: CGFloat = 720) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else {
            return self
        }

        let ratio = min(1, maxPixelDimension / longestSide)
        let previewSize = CGSize(
            width: max(1, size.width * ratio),
            height: max(1, size.height * ratio)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: previewSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: previewSize))
        }
    }

    func resizedToFill(size targetSize: CGSize) -> UIImage {
        guard targetSize.width > 0, targetSize.height > 0, size.width > 0, size.height > 0 else {
            return self
        }

        let scale = max(targetSize.width / size.width, targetSize.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(
            x: (targetSize.width - drawSize.width) * 0.5,
            y: (targetSize.height - drawSize.height) * 0.5
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    nonisolated func normalizedForTransparentEditing() -> UIImage {
        guard imageOrientation != .up || scale != 1 else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    nonisolated var hasAlphaChannel: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else {
            return true
        }

        switch alphaInfo {
        case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return true
        }
    }

    nonisolated var transparentPixelSampleCount: Int {
        guard let cgImage else {
            return 0
        }

        let width = min(cgImage.width, 96)
        let height = min(cgImage.height, 96)
        guard width > 0, height > 0 else {
            return 0
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var transparentCount = 0
        var index = 3
        while index < pixels.count {
            if pixels[index] < 250 {
                transparentCount += 1
            }
            index += 4
        }
        return transparentCount
    }
}

#Preview {
    EditorView(image: UIImage(systemName: "photo"), toolKind: .enhanceQuality, onBack: {}, onGoToMenu: {})
}
