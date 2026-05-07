import CoreGraphics
import Foundation
#if canImport(OSLog)
#endif
#if canImport(UIKit)
import UIKit
#endif

struct ObjectRemovalStroke: Identifiable, Hashable {
    let id = UUID()
    var points: [CGPoint]
    var normalizedBrushDiameter: CGFloat
}

struct ObjectRemovalEditPayload {
    let imageData: Data
    let maskData: Data
    let targetSize: CGSize
}

enum ObjectRemovalMaskRendererError: LocalizedError {
    case emptyMask
    case imageEncodingFailed
    case maskEncodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyMask:
            return "Select the object first."
        case .imageEncodingFailed:
            return "Could not prepare the image."
        case .maskEncodingFailed:
            return "Could not prepare the mask."
        }
    }
}

enum ObjectRemovalMaskRenderer {
    static func editPayload(
        image: UIImage,
        strokes: [ObjectRemovalStroke],
        maxPixelDimension: CGFloat = 1536
    ) throws -> ObjectRemovalEditPayload {
        guard !strokes.isEmpty else {
            throw ObjectRemovalMaskRendererError.emptyMask
        }

        let targetSize = scaledSize(for: image.size, maxPixelDimension: maxPixelDimension)
        let normalizedImage = renderImage(image, size: targetSize)
        guard let imageData = normalizedImage.pngData() else {
            throw ObjectRemovalMaskRendererError.imageEncodingFailed
        }

        let maskImage = renderMask(strokes: strokes, size: targetSize)
        guard let maskData = maskImage.pngData() else {
            throw ObjectRemovalMaskRendererError.maskEncodingFailed
        }
        return ObjectRemovalEditPayload(imageData: imageData, maskData: maskData, targetSize: targetSize)
    }

    private static func scaledSize(for size: CGSize, maxPixelDimension: CGFloat) -> CGSize {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let ratio = min(1, maxPixelDimension / longestSide)
        return CGSize(
            width: max(1, (size.width * ratio).rounded()),
            height: max(1, (size.height * ratio).rounded())
        )
    }

    private static func renderImage(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func renderMask(strokes: [ObjectRemovalStroke], size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            let fullRect = CGRect(origin: .zero, size: size)
            context.setFillColor(UIColor.white.cgColor)
            context.fill(fullRect)
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

                let firstPixelPoint = pixelPoint(firstPoint, size: size)
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
                    context.addLine(to: pixelPoint(point, size: size))
                }
                context.strokePath()
            }
        }
    }

    private static func pixelPoint(_ normalizedPoint: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * size.width,
            y: normalizedPoint.y * size.height
        )
    }
}
