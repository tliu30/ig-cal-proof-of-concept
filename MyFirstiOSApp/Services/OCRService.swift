/// OCRService.swift
/// ================
/// Provides on-device text recognition (OCR) using Apple's Vision framework.
///
/// ## How Apple Vision OCR Works
/// The Vision framework provides a pipeline-based API for image analysis:
///
/// 1. **Create a request**: `VNRecognizeTextRequest` describes *what* you want
///    (text recognition) and *how* (fast vs. accurate, which languages, etc.).
///
/// 2. **Create a handler**: `VNImageRequestHandler` takes an image (as `CGImage`,
///    `Data`, `URL`, etc.) and is responsible for running requests against that image.
///
/// 3. **Perform the request**: Calling `handler.perform([request])` runs the OCR
///    synchronously on the current thread. This is CPU-intensive, so it must NOT
///    run on the main thread (that would freeze the UI).
///
/// 4. **Read results**: After `perform()` returns, the request's `results` property
///    contains an array of `VNRecognizedTextObservation` objects — one per detected
///    text region. Each observation has a `topCandidates(_:)` method that returns
///    the most likely text strings for that region, ranked by confidence.
///
/// ## Thread Safety
/// This service is implemented as a Swift `actor`, which is a reference type that
/// serializes access to its mutable state. In practice, you can think of it like a
/// class where every method call is automatically queued — only one caller can execute
/// a method at a time, preventing data races. Callers use `await` to wait their turn.
/// For this particular service, we don't have mutable state, but the `actor` keyword
/// also signals to Swift's concurrency system that work here may be long-running and
/// should not block the main thread.

import Vision
import UIKit

/// Actor that performs OCR on image data using Apple Vision.
///
/// Usage:
/// ```swift
/// let service = OCRService()
/// let result = await service.recognizeText(in: imageData, from: imageURL)
/// print(result.recognizedText)
/// ```
actor OCRService {

    /// Recognizes text in the given image data.
    ///
    /// - Parameters:
    ///   - imageData: Raw image bytes (JPEG, PNG, etc.) to analyze.
    ///   - imageURL: The source URL of the image (stored in the result for reference).
    /// - Returns: An `OCRResult` containing the recognized text and confidence score.
    func recognizeText(in imageData: Data, from imageURL: URL) -> OCRResult {
        // Step 1: Convert raw bytes into a UIImage, then into a CGImage.
        // Vision requires a CGImage (Core Graphics image) — UIImage is a higher-level
        // wrapper that can be backed by various image sources; .cgImage extracts the
        // underlying bitmap.
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return OCRResult(
                imageURL: imageURL,
                imageData: imageData,
                recognizedText: "[Could not decode image]",
                confidence: 0
            )
        }

        // Step 2: Create the text recognition request.
        // `.accurate` recognition level is slower but produces better results than `.fast`.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true

        // Step 3: Create a handler for this specific image and perform the request.
        // `perform()` is synchronous and CPU-intensive, but since we're inside an actor,
        // this won't block the main thread — callers await the result.
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return OCRResult(
                imageURL: imageURL,
                imageData: imageData,
                recognizedText: "[OCR failed: \(error.localizedDescription)]",
                confidence: 0
            )
        }

        // Step 4: Extract recognized text from the results.
        // Each `VNRecognizedTextObservation` represents a detected text region in the image.
        // `topCandidates(1)` returns the single most-likely interpretation for that region.
        guard let observations = request.results, !observations.isEmpty else {
            return OCRResult(
                imageURL: imageURL,
                imageData: imageData,
                recognizedText: "",
                confidence: 0
            )
        }

        var textLines: [String] = []
        var totalConfidence: Float = 0

        for observation in observations {
            if let topCandidate = observation.topCandidates(1).first {
                textLines.append(topCandidate.string)
                totalConfidence += topCandidate.confidence
            }
        }

        let averageConfidence = totalConfidence / Float(observations.count)
        let fullText = textLines.joined(separator: "\n")

        return OCRResult(
            imageURL: imageURL,
            imageData: imageData,
            recognizedText: fullText,
            confidence: averageConfidence
        )
    }
}
