import AppKit
@preconcurrency import Vision
import CoreImage

struct OCRResult {
    var blocks: [OCRBlock]
    var text: String
    var qrCodes: [String]
}

final class OCRService {
    func recognize(image: NSImage, languages: [Language], smartParagraphs: Bool) async throws -> OCRResult {
        guard let cgImage = image.cgImageRepresentation else { throw TransError.imageUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let sorted = observations.sorted {
                    if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 {
                        return $0.boundingBox.midY > $1.boundingBox.midY
                    }
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                let blocks = sorted.compactMap { observation -> OCRBlock? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return OCRBlock(text: candidate.string, confidence: candidate.confidence)
                }
                let separator = smartParagraphs ? "\n" : " "
                let text = blocks.map(\.text).joined(separator: separator)
                let codes = self.detectQRCodes(in: cgImage)
                continuation.resume(returning: OCRResult(blocks: blocks, text: text, qrCodes: codes))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = languages.isEmpty || languages.contains(.auto)
            let requested = languages.filter { $0 != .auto }.map(\.code)
            if !requested.isEmpty { request.recognitionLanguages = requested }
            request.revision = VNRecognizeTextRequestRevision3
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private func detectQRCodes(in image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}

extension NSImage {
    var cgImageRepresentation: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
