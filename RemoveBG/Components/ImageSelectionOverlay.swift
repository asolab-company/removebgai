import AVFoundation
import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ImageSelectionOverlay: View {
    let onCancel: () -> Void
    let onImageSelected: (UIImage) -> Void

    @State private var isCameraPresented = false
    @State private var isGalleryPresented = false
    @State private var isAccessPresented = false
    @State private var isSheetHidden = false
    @State private var errorMessage: String?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let layout = ImageSelectionOverlayLayout(size: proxy.size)

            ZStack(alignment: .bottom) {
                if !isSheetHidden {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture(perform: onCancel)
                        .transition(.opacity)

                    selectionSheet(layout: layout)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .transition(.opacity)
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraImagePicker(
                onCancel: onCancel,
                onImageSelected: onImageSelected
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isGalleryPresented) {
            GalleryImagePicker(
                onCancel: onCancel,
                onImageSelected: onImageSelected
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isAccessPresented) {
            AccessView {
                isAccessPresented = false
                onCancel()
            }
        }
        .alert("Select Image", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func selectionSheet(layout: ImageSelectionOverlayLayout) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text("Select Image")
                .font(AppTypography.bold(20))
                .foregroundStyle(AppColors.primaryText)
                .padding(.top, 43)

            Text("Choose how you want to import your photo")
                .font(AppTypography.medium(14))
                .foregroundStyle(AppColors.primaryText)
                .padding(.top, 8)

            HStack(spacing: layout.optionSpacing) {
                importOption(
                    icon: FigmaAssets.camera,
                    title: "Camera",
                    subtitle: "Take a new photo",
                    width: layout.optionWidth
                ) {
                    openCamera()
                }

                importOption(
                    icon: FigmaAssets.gallery,
                    title: "Gallery",
                    subtitle: "Choose from library",
                    width: layout.optionWidth
                ) {
                    openGallery()
                }
            }
            .padding(.top, 35)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(AppTypography.medium(16))
                    .foregroundStyle(AppColors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 28)

            Spacer(minLength: 34)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 374)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(AppColors.card)
        )
        .ignoresSafeArea(edges: .bottom)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = max(value.translation.height, 0)
                }
                .onEnded { value in
                    if value.translation.height > 90 || value.predictedEndTranslation.height > 180 {
                        onCancel()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private func importOption(
        icon: String,
        title: String,
        subtitle: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            importOptionContent(icon: icon, title: title, subtitle: subtitle, width: width)
        }
        .buttonStyle(.plain)
    }

    private func importOptionContent(
        icon: String,
        title: String,
        subtitle: String,
        width: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(AppColors.primaryBlue)
                    .shadow(color: AppColors.primaryBlue.opacity(0.38), radius: 4, y: 4)

                importOptionIcon(icon)
            }
            .frame(width: 54, height: 54)

            Text(title)
                .font(AppTypography.bold(14))
                .foregroundStyle(AppColors.primaryText)
                .padding(.top, 16)

            Text(subtitle)
                .font(AppTypography.regular(12))
                .foregroundStyle(AppColors.tertiaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(width: width)
    }

    @ViewBuilder
    private func importOptionIcon(_ icon: String) -> some View {
        if icon == FigmaAssets.camera {
            Image(systemName: "camera.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.white)
        } else if icon == FigmaAssets.gallery {
            Image(systemName: "photo.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.white)
        } else {
            RemoteAssetImage(url: icon, contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }

    private func openCamera() {
        #if canImport(UIKit)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "Camera is not available on this device."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hideSheetAndPresentCamera()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    hideSheetAndPresentCamera()
                } else {
                    hideSheetAndPresentAccess()
                }
            }
        case .denied, .restricted:
            hideSheetAndPresentAccess()
        @unknown default:
            hideSheetAndPresentAccess()
        }
        #else
        errorMessage = "Camera is not available on this device."
        #endif
    }

    private func openGallery() {
        isSheetHidden = true
        isGalleryPresented = true
    }

    private func hideSheetAndPresentCamera() {
        isSheetHidden = true
        isCameraPresented = true
    }

    private func hideSheetAndPresentAccess() {
        isSheetHidden = true
        isAccessPresented = true
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }
}

private struct ImageSelectionOverlayLayout {
    let size: CGSize

    private var isCompactWidth: Bool {
        size.width <= 340
    }

    var optionSpacing: CGFloat {
        isCompactWidth ? 34 : 70
    }

    var optionWidth: CGFloat {
        isCompactWidth ? 124 : 108
    }
}

#if canImport(UIKit)
private struct CameraImagePicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageSelected(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
            parent.onCancel()
        }
    }
}

private struct GalleryImagePicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: GalleryImagePicker

        init(parent: GalleryImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let provider = results.first?.itemProvider else {
                parent.onCancel()
                return
            }

            guard provider.canLoadObject(ofClass: UIImage.self) else {
                parent.onCancel()
                return
            }

            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self.parent.onImageSelected(image)
                    } else {
                        self.parent.onCancel()
                    }
                }
            }
        }
    }
}
#endif

#Preview {
    ImageSelectionOverlay(
        onCancel: {},
        onImageSelected: { _ in }
    )
}
