import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import Vision
#if canImport(UIKit)
import UIKit
#endif

enum BackgroundBlurProcessorError: Error {
    case invalidImage
    case modelNotFound
    case modelOutputMissing
    case maskRenderingFailed
}

final class BackgroundBlurProcessor: @unchecked Sendable {
    static let shared = BackgroundBlurProcessor()

    private let context = CIContext(options: [
        .cacheIntermediates: false
    ])
    private let segmentationService: SegmentationService
    private let maskPostProcessor = MaskPostProcessor()
    private let blurRenderer = BlurRenderer()

    nonisolated init(segmentationService: SegmentationService = CompositeSegmentationService()) {
        self.segmentationService = segmentationService
    }

    nonisolated func blurBackground(
        image: UIImage,
        blurRadius: CGFloat
    ) async throws -> UIImage {
        return try await Task.detached(priority: .userInitiated) {
            do {
                let result = try self.renderBlurredBackground(image: image, blurRadius: blurRadius)
                return result
            } catch {
                throw error
            }
        }.value
    }

    nonisolated func foregroundMask(image: UIImage) async throws -> CIImage {
        return try await Task.detached(priority: .userInitiated) {
            do {
                let mask = try self.makeForegroundMask(image: image)
                return mask
            } catch {
                throw error
            }
        }.value
    }

    nonisolated func blurBackground(
        image: UIImage,
        blurRadius: CGFloat,
        foregroundMask: CIImage
    ) async throws -> UIImage {
        return try await Task.detached(priority: .userInitiated) {
            guard let inputImage = self.inputImage(from: image) else {
                throw BackgroundBlurProcessorError.invalidImage
            }

            let result = try self.blurRenderer.render(
                image: image,
                inputImage: inputImage,
                foregroundMask: foregroundMask.backgroundBlurMatchingExtent(inputImage.extent),
                blurRadius: blurRadius,
                context: self.context
            )
            return result
        }.value
    }

    nonisolated private func renderBlurredBackground(
        image: UIImage,
        blurRadius: CGFloat
    ) throws -> UIImage {
        guard blurRadius > 0 else {
            return image
        }

        guard let inputImage = inputImage(from: image) else {
            throw BackgroundBlurProcessorError.invalidImage
        }

        let mask = try makeForegroundMask(image: image)
        return try blurRenderer.render(
            image: image,
            inputImage: inputImage,
            foregroundMask: mask,
            blurRadius: blurRadius,
            context: context
        )
    }

    nonisolated private func makeForegroundMask(image: UIImage) throws -> CIImage {
        guard let inputImage = inputImage(from: image) else {
            throw BackgroundBlurProcessorError.invalidImage
        }

        guard let rawMask = try segmentationService.foregroundMask(for: image, context: context) else {
            throw BackgroundBlurProcessorError.maskRenderingFailed
        }
        let refinedMask = maskPostProcessor.refinedMask(
            rawMask.backgroundBlurMatchingExtent(inputImage.extent),
            extent: inputImage.extent
        )
        return refinedMask
    }

    nonisolated private func inputImage(from image: UIImage) -> CIImage? {
        CIImage(image: image)?.oriented(forExifOrientation: image.imageOrientation.backgroundBlurExifOrientation)
    }
}

protocol SegmentationService: AnyObject, Sendable {
    nonisolated func foregroundMask(for image: UIImage, context: CIContext) throws -> CIImage?
}

final class CompositeSegmentationService: SegmentationService, @unchecked Sendable {
    private let visionService = VisionForegroundSegmentationService()
    private let depthService = DepthAnythingSegmentationService()

    nonisolated init() {}

    nonisolated func foregroundMask(for image: UIImage, context: CIContext) throws -> CIImage? {

        do {
            if let visionMask = try visionService.foregroundMask(for: image, context: context) {
                return visionMask
            }
        } catch {
        }

        do {
            if let depthMask = try depthService.foregroundMask(for: image, context: context) {
                return depthMask
            }
        } catch {
        }
        return nil
    }
}

final class VisionForegroundSegmentationService: SegmentationService, @unchecked Sendable {
    nonisolated init() {}

    nonisolated func foregroundMask(for image: UIImage, context: CIContext) throws -> CIImage? {

        guard let cgImage = image.cgImage else {
            throw BackgroundBlurProcessorError.invalidImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.imageOrientation.backgroundBlurCGImagePropertyOrientation,
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
            let mask = CIImage(cvPixelBuffer: maskBuffer)
            return mask
        } catch {
            throw error
        }
    }
}

final class DepthAnythingSegmentationService: SegmentationService, @unchecked Sendable {
    nonisolated private static let modelWidth = 518
    nonisolated private static let modelHeight = 392

    private let modelLock = NSLock()
    nonisolated(unsafe) private var cachedModel: MLModel?

    nonisolated init() {}

    nonisolated func foregroundMask(for image: UIImage, context: CIContext) throws -> CIImage? {
        guard let cgImage = orientedCGImage(from: image, context: context) else {
            throw BackgroundBlurProcessorError.invalidImage
        }

        let inputBuffer = try MLFeatureValue(
            cgImage: cgImage,
            pixelsWide: Self.modelWidth,
            pixelsHigh: Self.modelHeight,
            pixelFormatType: kCVPixelFormatType_32ARGB,
            options: nil
        ).imageBufferValue

        guard let inputBuffer else {
            throw BackgroundBlurProcessorError.invalidImage
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: inputBuffer)
        ])
        let output = try model().prediction(from: provider)

        guard let depthBuffer = output.featureValue(for: "depth")?.imageBufferValue else {
            throw BackgroundBlurProcessorError.modelOutputMissing
        }

        let mask = try depthMask(from: depthBuffer, context: context)
        return mask
    }

    nonisolated private func model() throws -> MLModel {
        modelLock.lock()
        defer { modelLock.unlock() }

        if let cachedModel {
            return cachedModel
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly

        guard
            let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16P6", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "DepthAnythingV2SmallF16P6", withExtension: "mlpackage")
        else {
            throw BackgroundBlurProcessorError.modelNotFound
        }

        let model = try MLModel(contentsOf: url, configuration: configuration)
        cachedModel = model
        return model
    }

    nonisolated private func orientedCGImage(from image: UIImage, context: CIContext) -> CGImage? {
        guard let ciImage = CIImage(image: image)?.oriented(forExifOrientation: image.imageOrientation.backgroundBlurExifOrientation) else {
            return image.cgImage
        }
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    nonisolated private func depthMask(from depthBuffer: CVPixelBuffer, context: CIContext) throws -> CIImage {
        let depthImage = CIImage(cvPixelBuffer: depthBuffer)
        let extent = depthImage.extent
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthBuffer)
        guard width > 0, height > 0 else {
            throw BackgroundBlurProcessorError.maskRenderingFailed
        }

        if pixelFormat == kCVPixelFormatType_OneComponent16Half {
            let depthValues = try halfFloatDepthValues(from: depthBuffer, width: width, height: height)
            let stats = DepthMaskStats(values: depthValues, width: width, height: height)
            let maskBytes = stats.makeForegroundAlphaMask()
            return try grayscaleMaskImage(bytes: maskBytes, width: width, height: height)
        }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            depthImage,
            toBitmap: &rgba,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let depthValues = stride(from: 0, to: rgba.count, by: 4).map { Float(rgba[$0]) }
        let stats = DepthMaskStats(values: depthValues, width: width, height: height)
        let maskBytes = stats.makeForegroundAlphaMask()

        return try grayscaleMaskImage(bytes: maskBytes, width: width, height: height)
    }

    nonisolated private func halfFloatDepthValues(
        from depthBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) throws -> [Float] {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            throw BackgroundBlurProcessorError.maskRenderingFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        var values = [Float]()
        values.reserveCapacity(width * height)

        for y in 0..<height {
            let rowPointer = baseAddress
                .advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt16.self)

            for x in 0..<width {
                values.append(Float(Float16(bitPattern: rowPointer[x])))
            }
        }

        return values
    }

    nonisolated private func grayscaleMaskImage(bytes: [UInt8], width: Int, height: Int) throws -> CIImage {
        var mutableBytes = bytes
        guard let provider = CGDataProvider(data: NSData(bytes: &mutableBytes, length: mutableBytes.count)) else {
            throw BackgroundBlurProcessorError.maskRenderingFailed
        }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw BackgroundBlurProcessorError.maskRenderingFailed
        }

        return CIImage(cgImage: cgImage)
    }
}

private struct DepthMaskStats {
    let values: [Float]
    let width: Int
    let height: Int

    nonisolated func makeForegroundAlphaMask() -> [UInt8] {
        let parameters = maskParameters()
        let maskBytes = makeForegroundAlphaMask(using: parameters)
        let coverage = coverageSummary(maskBytes: maskBytes)

        guard coverage.visible <= 0.88, coverage.strong >= 0.03 else {
            let tightenedParameters = parameters.tightened()
            let tightenedMaskBytes = makeForegroundAlphaMask(using: tightenedParameters)
            return tightenedMaskBytes
        }

        return maskBytes
    }

    nonisolated private func makeForegroundAlphaMask(using parameters: DepthMaskParameters) -> [UInt8] {
        values.map { value in
            let alpha: Float
            if parameters.nearIsBright {
                alpha = smoothstep(edge0: parameters.threshold - parameters.feather, edge1: parameters.threshold + parameters.feather, x: value)
            } else {
                alpha = 1 - smoothstep(edge0: parameters.threshold - parameters.feather, edge1: parameters.threshold + parameters.feather, x: value)
            }
            return UInt8(max(0, min(255, alpha * 255)).rounded())
        }
    }

    nonisolated func debugSummary(maskBytes: [UInt8]) -> String {
        let parameters = maskParameters()
        let depthAvg = values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
        let coverage = coverageSummary(maskBytes: maskBytes)

        return "depthMin=\(parameters.depthMin) depthMax=\(parameters.depthMax) depthRange=\(parameters.depthRange) depthAvg=\(depthAvg) centerAvg=\(parameters.centerAverage) borderAvg=\(parameters.borderAverage) nearIsBright=\(parameters.nearIsBright) threshold=\(parameters.threshold) feather=\(parameters.feather) coverage=\(coverage.visible) strongCoverage=\(coverage.strong)"
    }

    nonisolated private func maskParameters() -> DepthMaskParameters {
        let depthMin = values.min() ?? 0
        let depthMax = values.max() ?? 1
        let depthRange = max(0.0001, depthMax - depthMin)
        let centerAverage = average(insetX: 0.32, insetY: 0.28)
        let borderAverage = borderAverage(border: 0.14)
        let nearIsBright = centerAverage >= borderAverage
        let difference = abs(centerAverage - borderAverage)
        let sortedValues = values.sorted()
        let percentileThreshold = percentile(nearIsBright ? 0.70 : 0.30, sortedValues: sortedValues)
        let midpointThreshold = (centerAverage + borderAverage) * 0.5
        let threshold = difference > depthRange * 0.08 ? midpointThreshold : percentileThreshold
        let featherCandidate = max(difference * 0.22, depthRange * 0.035)
        let feather = max(depthRange * 0.018, min(depthRange * 0.09, featherCandidate))

        return DepthMaskParameters(
            depthMin: depthMin,
            depthMax: depthMax,
            depthRange: depthRange,
            centerAverage: centerAverage,
            borderAverage: borderAverage,
            nearIsBright: nearIsBright,
            threshold: threshold,
            feather: feather
        )
    }

    nonisolated private func coverageSummary(maskBytes: [UInt8]) -> (visible: Float, strong: Float) {
        guard !maskBytes.isEmpty else {
            return (0, 0)
        }

        let visiblePixels = maskBytes.filter { $0 > 16 }.count
        let strongPixels = maskBytes.filter { $0 > 180 }.count
        return (
            Float(visiblePixels) / Float(maskBytes.count),
            Float(strongPixels) / Float(maskBytes.count)
        )
    }

    nonisolated private func average(insetX: CGFloat, insetY: CGFloat) -> Float {
        let minX = Int(CGFloat(width) * insetX)
        let maxX = Int(CGFloat(width) * (1 - insetX))
        let minY = Int(CGFloat(height) * insetY)
        let maxY = Int(CGFloat(height) * (1 - insetY))
        return average(xRange: minX..<max(minX + 1, maxX), yRange: minY..<max(minY + 1, maxY))
    }

    nonisolated private func borderAverage(border: CGFloat) -> Float {
        let borderX = max(1, Int(CGFloat(width) * border))
        let borderY = max(1, Int(CGFloat(height) * border))
        var total: Float = 0
        var count: Float = 0

        for y in 0..<height {
            for x in 0..<width where x < borderX || x >= width - borderX || y < borderY || y >= height - borderY {
                total += values[y * width + x]
                count += 1
            }
        }

        return count > 0 ? total / count : 0
    }

    nonisolated private func average(xRange: Range<Int>, yRange: Range<Int>) -> Float {
        var total: Float = 0
        var count: Float = 0

        for y in yRange.clamped(to: 0..<height) {
            for x in xRange.clamped(to: 0..<width) {
                total += values[y * width + x]
                count += 1
            }
        }

        return count > 0 ? total / count : 0
    }

    nonisolated private func percentile(_ value: CGFloat, sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else {
            return 0
        }
        let index = Int((CGFloat(sortedValues.count - 1) * value).rounded())
        return sortedValues[max(0, min(sortedValues.count - 1, index))]
    }

    nonisolated private func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        guard edge0 != edge1 else {
            return x >= edge1 ? 1 : 0
        }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

private struct DepthMaskParameters {
    let depthMin: Float
    let depthMax: Float
    let depthRange: Float
    let centerAverage: Float
    let borderAverage: Float
    let nearIsBright: Bool
    let threshold: Float
    let feather: Float

    nonisolated func tightened() -> DepthMaskParameters {
        let thresholdShift = depthRange * 0.10
        let tightenedThreshold = nearIsBright
            ? min(depthMax, threshold + thresholdShift)
            : max(depthMin, threshold - thresholdShift)
        let tightenedFeather = max(depthRange * 0.012, min(feather, depthRange * 0.035))

        return DepthMaskParameters(
            depthMin: depthMin,
            depthMax: depthMax,
            depthRange: depthRange,
            centerAverage: centerAverage,
            borderAverage: borderAverage,
            nearIsBright: nearIsBright,
            threshold: tightenedThreshold,
            feather: tightenedFeather
        )
    }
}

private struct MaskPostProcessor: Sendable {
    nonisolated func refinedMask(_ mask: CIImage, extent: CGRect) -> CIImage {
        let cleanedMask = morphology(mask, filterName: "CIMorphologyMaximum", radius: 1.0, extent: extent)
        let protectedForeground = morphology(cleanedMask, filterName: "CIMorphologyMinimum", radius: 1.0, extent: extent)
        let softenedMask = gaussianBlur(protectedForeground, radius: 1.35, extent: extent)
        let refinedMask = colorControls(softenedMask, contrast: 1.32, brightness: 0.02)
        return refinedMask.cropped(to: extent)
    }

    nonisolated private func morphology(_ image: CIImage, filterName: String, radius: CGFloat, extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: filterName) else {
            return image
        }
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage?.cropped(to: extent) ?? image
    }

    nonisolated private func gaussianBlur(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = image.clampedToExtent()
        filter.radius = Float(radius)
        return filter.outputImage?.cropped(to: extent) ?? image
    }

    nonisolated private func colorControls(_ image: CIImage, contrast: Float, brightness: Float) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = contrast
        filter.brightness = brightness
        filter.saturation = 0
        return filter.outputImage ?? image
    }
}

private struct BlurRenderer: Sendable {
    nonisolated func render(
        image: UIImage,
        inputImage: CIImage,
        foregroundMask: CIImage,
        blurRadius: CGFloat,
        context: CIContext
    ) throws -> UIImage {
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = inputImage.clampedToExtent()
        blurFilter.radius = Float(blurRadius)

        guard let blurredImage = blurFilter.outputImage?.cropped(to: inputImage.extent) else {
            throw BackgroundBlurProcessorError.maskRenderingFailed
        }

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = inputImage
        blendFilter.backgroundImage = blurredImage
        blendFilter.maskImage = foregroundMask

        guard
            let outputImage = blendFilter.outputImage,
            let cgImage = context.createCGImage(outputImage, from: inputImage.extent)
        else {
            throw BackgroundBlurProcessorError.maskRenderingFailed
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
}

private extension Range where Bound == Int {
    nonisolated func clamped(to limits: Range<Int>) -> Range<Int> {
        Swift.max(lowerBound, limits.lowerBound)..<Swift.min(upperBound, limits.upperBound)
    }
}

private extension CIImage {
    nonisolated func backgroundBlurMatchingExtent(_ targetExtent: CGRect) -> CIImage {
        guard extent.width > 0, extent.height > 0 else {
            return self
        }

        let scaleX = targetExtent.width / extent.width
        let scaleY = targetExtent.height / extent.height
        return transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: targetExtent)
    }
}

private extension UIImage.Orientation {
    nonisolated var backgroundBlurExifOrientation: Int32 {
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

    nonisolated var backgroundBlurCGImagePropertyOrientation: CGImagePropertyOrientation {
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
