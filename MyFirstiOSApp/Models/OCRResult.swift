/// OCRResult.swift
/// ===============
/// Data model for the result of running OCR (Optical Character Recognition) on an image.
///
/// ## What is OCR?
/// OCR is the process of extracting machine-readable text from images. Apple's Vision
/// framework provides on-device OCR that runs locally (no network call needed) and
/// supports many languages. The quality depends on image resolution, text clarity,
/// and font style.
///
/// ## Why a Separate Model?
/// We wrap the OCR output in its own struct rather than using a plain `String` because:
/// 1. We might want to include confidence scores or bounding boxes later.
/// 2. It makes the data flow clearer — you can see at a glance that a value came from OCR.
/// 3. It conforms to `Identifiable` so SwiftUI can efficiently render lists of results.

import Foundation

/// Contains the text extracted from a single image via Apple Vision OCR.
struct OCRResult: Identifiable {
    /// Unique identifier for this OCR result.
    let id = UUID()

    /// The URL of the image that was processed.
    let imageURL: URL

    /// The locally-downloaded image data (used for display in the results view).
    let imageData: Data

    /// All recognized text lines concatenated together.
    /// Empty string if no text was found in the image.
    let recognizedText: String

    /// The confidence score from 0.0 to 1.0, averaged across all recognized text observations.
    /// A higher score means the OCR engine is more confident in its output.
    let confidence: Float
}
