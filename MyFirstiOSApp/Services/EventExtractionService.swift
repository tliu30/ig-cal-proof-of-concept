/// EventExtractionService.swift
/// ============================
/// Dispatch helper that routes event extraction to the correct implementation
/// based on `ExtractionMethod`. Used by the test suite's parameterized tests
/// and by the ViewModel's parallel extraction pipeline.
///
/// Each method delegates to its own service file:
/// - `.regex` → `RegexExtractionService`
/// - `.nsDataDetector` → `NSDataDetectorExtractionService`
/// - `.foundationModels` → `FoundationModelsExtractionService` (iOS 26+ only)
/// - `.llama` → `LlamaExtractionService`

import Foundation

enum EventExtractionService {

    /// Extracts structured events using the specified method.
    ///
    /// - Parameters:
    ///   - method: Which extraction algorithm to use.
    ///   - ocrTexts: Array of text strings recognized from images via OCR.
    ///   - altTexts: Array of image alt text strings from the page HTML.
    ///   - caption: The post caption text.
    ///   - currentDate: The current date, used to infer the year for dates that omit it.
    /// - Returns: Array of extracted events sorted chronologically.
    static func extractEvents(
        using method: ExtractionMethod,
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) -> [ExtractedEvent] {
        switch method {
        case .regex:
            return RegexExtractionService.extractEvents(
                ocrTexts: ocrTexts, altTexts: altTexts,
                caption: caption, currentDate: currentDate
            )
        case .nsDataDetector:
            return NSDataDetectorExtractionService.extractEvents(
                ocrTexts: ocrTexts, altTexts: altTexts,
                caption: caption, currentDate: currentDate
            )
        case .foundationModels:
            // Foundation Models requires iOS 26+ and on-device model availability.
            // Tested separately; returns empty here for the synchronous test path.
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return FoundationModelsExtractionService.extractEvents(
                    ocrTexts: ocrTexts, altTexts: altTexts,
                    caption: caption, currentDate: currentDate
                )
            }
            #endif
            return []
        case .llama:
            return LlamaExtractionService.extractEvents(
                ocrTexts: ocrTexts, altTexts: altTexts,
                caption: caption, currentDate: currentDate
            )
        }
    }
}
