/// EventExtractionService.swift
/// ============================
/// Extracts structured date/time events from unstructured text sources.
///
/// ## What This Does
/// Takes raw text from multiple sources — OCR output from images, image alt texts,
/// and post captions — and identifies events with start times, optional end times,
/// and descriptions. For example, given OCR text from a flyer image that says
/// "Fri - March 13th St. Slayer's Day hosted by DJ ILUVDOMRICH 7-Midnite",
/// it produces an `ExtractedEvent` with datetimeStart "2026-03-13 19:00",
/// datetimeEnd "2026-03-14 00:00", and description "St. Slayer's Day hosted by DJ ILUVDOMRICH".
///
/// ## Input Sources
/// - **ocrTexts**: Text recognized from images via Apple Vision OCR. May contain
///   artifacts, misspellings, and fragmented lines.
/// - **altTexts**: Alt text attributes from `<img>` tags in the page HTML. Often
///   contain descriptions written by the post author.
/// - **caption**: The post caption text extracted from the page.
/// - **currentDate**: Used to infer the year (since flyers rarely include the year).
///
/// ## Design
/// This is a caseless `enum` (cannot be instantiated) that acts as a pure namespace
/// for static functions — the same pattern used by `HTMLParsingService`.
///
/// ## Implementation Status
/// This is currently a stub that returns an empty array. The implementation will be
/// filled in during experimentation with different approaches (regex, NSDataDetector,
/// Apple Foundation Models, on-device LLM).

import Foundation

enum EventExtractionService {

    /// Extracts structured events from unstructured text sources.
    ///
    /// - Parameters:
    ///   - ocrTexts: Array of text strings recognized from images via OCR.
    ///   - altTexts: Array of image alt text strings from the page HTML.
    ///   - caption: The post caption text.
    ///   - currentDate: The current date, used to infer the year for dates that omit it.
    /// - Returns: Array of extracted events with start/end datetimes and descriptions.
    static func extractEvents(
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) -> [ExtractedEvent] {
        return [] // stub -- experiments replace this
    }
}
