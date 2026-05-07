import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum OpenAIImageEditConfig {
    nonisolated static let model = "gpt-image-1.5"
}

enum OpenAIImageEditError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestTimedOut
    case networkError(String)
    case apiError(String)
    case imageDecodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing."
        case .invalidResponse:
            return "OpenAI returned an invalid response."
        case .requestTimedOut:
            return "OpenAI is taking too long to process this image. Try again, or use a smaller selected area."
        case .networkError(let message):
            return message
        case .apiError(let message):
            return message
        case .imageDecodingFailed:
            return "Could not decode the edited image."
        }
    }
}

enum AIBackgroundSelection: String {
    case none
    case photo
    case color

    var title: String {
        switch self {
        case .none:
            return "None"
        case .photo:
            return "Photo"
        case .color:
            return "Color"
        }
    }

    nonisolated var logName: String {
        rawValue
    }
}

struct AIBackgroundEditPayload {
    enum Mode {
        case none
        case photo
        case color(hex: String, opacity: Double)

        nonisolated var logName: String {
            switch self {
            case .none:
                return "none"
            case .photo:
                return "photo"
            case .color:
                return "color"
            }
        }
    }

    let imageData: Data
    let referenceImageData: Data?
    let targetSize: CGSize
    let mode: Mode

    static func make(
        image: UIImage,
        selection: AIBackgroundSelection,
        colorHex: String,
        colorOpacity: Double,
        referenceImage: UIImage?,
        maxPixelDimension: CGFloat = 1536
    ) throws -> AIBackgroundEditPayload {
        let targetSize = scaledSize(for: image.size, maxPixelDimension: maxPixelDimension)
        let normalizedImage = renderImage(image, size: targetSize, opaque: false)
        guard let imageData = normalizedImage.pngData() else {
            throw ObjectRemovalMaskRendererError.imageEncodingFailed
        }

        let mode: Mode
        let referenceData: Data?
        switch selection {
        case .none:
            mode = .none
            referenceData = nil
        case .photo:
            guard let referenceImage else {
                throw OpenAIImageEditError.apiError("Choose a background photo first.")
            }
            let referenceSize = scaledSize(for: referenceImage.size, maxPixelDimension: maxPixelDimension)
            let normalizedReference = renderImage(referenceImage, size: referenceSize, opaque: true)
            guard let data = normalizedReference.jpegData(compressionQuality: 0.92) else {
                throw ObjectRemovalMaskRendererError.imageEncodingFailed
            }
            mode = .photo
            referenceData = data
        case .color:
            mode = .color(hex: colorHex, opacity: colorOpacity)
            referenceData = nil
        }

        return AIBackgroundEditPayload(
            imageData: imageData,
            referenceImageData: referenceData,
            targetSize: targetSize,
            mode: mode
        )
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

    private static func renderImage(_ image: UIImage, size: CGSize, opaque: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

final class OpenAIImageEditService: @unchecked Sendable {
    static let shared = OpenAIImageEditService()

    private let endpoint = URL(string: "https://api.openai.com/v1/images/edits")!
    private let session: URLSession

    nonisolated init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 240
            configuration.timeoutIntervalForResource = 360
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    nonisolated func removeObject(payload: ObjectRemovalEditPayload) async throws -> UIImage {
        let apiKey = try await OpenAIAPIKeyManager.shared.apiKey()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenAIImageEditError.missingAPIKey
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = multipartBody(
            boundary: boundary,
            imageData: payload.imageData,
            maskData: payload.maskData
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let urlError = error as? URLError {
                if urlError.code == .cancelled {
                    throw CancellationError()
                }
                if urlError.code == .timedOut {
                    throw OpenAIImageEditError.requestTimedOut
                }
            }
            throw OpenAIImageEditError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIImageEditError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = apiError?.error.message ?? "OpenAI request failed with status \(httpResponse.statusCode)."
            throw OpenAIImageEditError.apiError(message)
        }
        let decodedResponse = try JSONDecoder().decode(OpenAIImagesResponse.self, from: data)
        guard
            let base64Image = decodedResponse.data.first?.b64Json,
            let imageData = Data(base64Encoded: base64Image),
            let image = UIImage(data: imageData)
        else {
            throw OpenAIImageEditError.imageDecodingFailed
        }
        return image
    }

    nonisolated func editBackground(payload: AIBackgroundEditPayload) async throws -> UIImage {
        let apiKey = try await OpenAIAPIKeyManager.shared.apiKey()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenAIImageEditError.missingAPIKey
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = backgroundMultipartBody(boundary: boundary, payload: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let urlError = error as? URLError {
                if urlError.code == .cancelled {
                    throw CancellationError()
                }
                if urlError.code == .timedOut {
                    throw OpenAIImageEditError.requestTimedOut
                }
            }
            throw OpenAIImageEditError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIImageEditError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = apiError?.error.message ?? "OpenAI request failed with status \(httpResponse.statusCode)."
            throw OpenAIImageEditError.apiError(message)
        }
        let decodedResponse = try JSONDecoder().decode(OpenAIImagesResponse.self, from: data)
        guard
            let base64Image = decodedResponse.data.first?.b64Json,
            let imageData = Data(base64Encoded: base64Image),
            let image = UIImage(data: imageData)
        else {
            throw OpenAIImageEditError.imageDecodingFailed
        }
        return image
    }

    nonisolated private func multipartBody(
        boundary: String,
        imageData: Data,
        maskData: Data
    ) -> Data {
        var body = Data()

        body.appendFormField(name: "model", value: OpenAIImageEditConfig.model, boundary: boundary)
        body.appendFormField(
            name: "prompt",
            value: "The transparent area of the mask is the only area to edit. Remove the object, body part, or unwanted content inside that transparent masked area completely, then realistically inpaint the background behind it. Keep every opaque/unmasked pixel visually unchanged. Do not zoom, crop, reframe, enlarge the subject, change the camera angle, change composition, or add new objects.",
            boundary: boundary
        )
        body.appendFormField(name: "quality", value: "high", boundary: boundary)
        body.appendFormField(name: "output_format", value: "png", boundary: boundary)
        body.appendFormField(name: "input_fidelity", value: "high", boundary: boundary)
        body.appendFileField(
            name: "image[]",
            filename: "image.png",
            mimeType: "image/png",
            data: imageData,
            boundary: boundary
        )
        body.appendFileField(
            name: "mask",
            filename: "mask.png",
            mimeType: "image/png",
            data: maskData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")

        return body
    }

    nonisolated private func backgroundMultipartBody(
        boundary: String,
        payload: AIBackgroundEditPayload
    ) -> Data {
        var body = Data()

        body.appendFormField(name: "model", value: OpenAIImageEditConfig.model, boundary: boundary)
        body.appendFormField(name: "prompt", value: backgroundPrompt(for: payload.mode), boundary: boundary)
        body.appendFormField(name: "quality", value: "high", boundary: boundary)
        body.appendFormField(name: "output_format", value: "png", boundary: boundary)
        body.appendFormField(name: "input_fidelity", value: "high", boundary: boundary)

        if case .none = payload.mode {
            body.appendFormField(name: "background", value: "transparent", boundary: boundary)
        }

        body.appendFileField(
            name: "image[]",
            filename: "subject.png",
            mimeType: "image/png",
            data: payload.imageData,
            boundary: boundary
        )

        if let referenceImageData = payload.referenceImageData {
            body.appendFileField(
                name: "image[]",
                filename: "background.jpg",
                mimeType: "image/jpeg",
                data: referenceImageData,
                boundary: boundary
            )
        }

        body.append("--\(boundary)--\r\n")
        return body
    }

    nonisolated private func backgroundPrompt(for mode: AIBackgroundEditPayload.Mode) -> String {
        switch mode {
        case .none:
            return "Remove the entire background from the first input image and output a PNG with a fully transparent background. Keep the main foreground subject completely sharp and unchanged, including hair, fur, edges, clothing, product details, and original colors. Do not crop, zoom, reframe, alter the subject, add new objects, or change the camera angle."
        case .photo:
            return "Use the first input image as the foreground subject photo and the second input image as the new background reference. Replace only the original background with the second image, fitting it naturally behind the subject. Keep the foreground subject sharp and unchanged, preserve realistic edges, lighting, shadows, and composition. Do not crop, zoom, reframe, alter the subject, or add unrelated objects."
        case .color(let hex, let opacity):
            let percent = Int((min(max(opacity, 0), 1) * 100).rounded())
            return "Replace only the original background in the input image with a clean #\(hex) color at \(percent)% opacity. Keep the foreground subject fully sharp and unchanged, with smooth realistic edges and no halo artifacts. Do not crop, zoom, reframe, alter the subject, add texture, gradients, or new objects."
        }
    }
}

private nonisolated struct OpenAIImagesResponse: Decodable {
    let data: [OpenAIImageData]
}

private nonisolated struct OpenAIImageData: Decodable {
    let b64Json: String?

    enum CodingKeys: String, CodingKey {
        case b64Json = "b64_json"
    }
}

private nonisolated struct OpenAIErrorResponse: Decodable {
    let error: OpenAIAPIError
}

private nonisolated struct OpenAIAPIError: Decodable {
    let message: String
}

private extension Data {
    nonisolated mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    nonisolated mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    nonisolated mutating func appendFileField(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
}
