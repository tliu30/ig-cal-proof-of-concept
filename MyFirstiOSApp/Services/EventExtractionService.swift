/// EventExtractionService.swift
/// ============================
/// Extracts structured date/time events from unstructured text sources using
/// Apple's on-device Foundation Models framework.
///
/// ## What This Does
/// Takes raw text from multiple sources — OCR output from images, image alt texts,
/// and post captions — and uses the on-device LLM to identify events with start times,
/// optional end times, and descriptions. For example, given OCR text from a flyer image
/// that says "Fri - March 13th St. Slayer's Day hosted by DJ ILUVDOMRICH 7-Midnite",
/// it produces an `ExtractedEvent` with datetimeStart "2026-03-13 19:00",
/// datetimeEnd "2026-03-14 00:00", and description "St. Slayer's Day hosted by DJ ILUVDOMRICH".
///
/// ## Approach: Foundation Models (Experiment C)
/// This implementation uses Apple's `FoundationModels` framework (iOS 26+) with the
/// `@Generable` macro for structured output. The on-device LLM receives a carefully
/// crafted prompt with extraction rules and produces a `GenerableEventList` directly —
/// no regex parsing or manual date extraction needed.
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
/// The public API is synchronous to preserve compatibility with the existing test suite.
/// Internally, it bridges to an async implementation via `DispatchSemaphore`. This is
/// safe because the test runner executes test bodies on a background executor, not the
/// main actor.

import Foundation
import FoundationModels
import os

/// Logger for debugging extraction issues.
private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MyFirstiOSApp",
    category: "EventExtractionService"
)

enum EventExtractionService {

    // MARK: - Public Synchronous Interface

    /// Extracts structured events from unstructured text sources.
    ///
    /// This function is synchronous to match the test suite's calling convention.
    /// Internally it bridges to the async Foundation Models API.
    ///
    /// - Parameters:
    ///   - ocrTexts: Array of text strings recognized from images via OCR.
    ///   - altTexts: Array of image alt text strings from the page HTML.
    ///   - caption: The post caption text.
    ///   - currentDate: The current date, used to infer the year for dates that omit it.
    /// - Returns: Array of extracted events sorted chronologically, or empty if
    ///   no events found, input is empty, or the model is unavailable.
    static func extractEvents(
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) -> [ExtractedEvent] {
        // Short-circuit: if all inputs are empty or whitespace-only, return immediately.
        let allText = ocrTexts.joined() + altTexts.joined() + caption
        guard !allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        // Check model availability before attempting generation.
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            logger.warning("Foundation Models unavailable: \(String(describing: availability))")
            return []
        }

        // Bridge async to sync. Safe because tests run off the main actor.
        let semaphore = DispatchSemaphore(value: 0)
        var result: [ExtractedEvent] = []

        Task.detached {
            result = await extractEventsAsync(
                ocrTexts: ocrTexts,
                altTexts: altTexts,
                caption: caption,
                currentDate: currentDate
            )
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - Private Async Implementation

    /// Async implementation that calls the Foundation Models on-device LLM.
    private static func extractEventsAsync(
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) async -> [ExtractedEvent] {
        let prompt = buildPrompt(
            ocrTexts: ocrTexts,
            altTexts: altTexts,
            caption: caption,
            currentDate: currentDate
        )

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: prompt,
                generating: GenerableEventList.self
            )

            let events = response.content.events.map { genEvent in
                ExtractedEvent(
                    datetimeStart: genEvent.datetimeStart,
                    datetimeEnd: genEvent.datetimeEnd,
                    description: genEvent.description
                )
            }

            // Sort chronologically by start datetime.
            return events.sorted { $0.datetimeStart < $1.datetimeStart }

        } catch {
            logger.error("Foundation Models extraction failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Prompt Construction

    /// Builds the extraction prompt from all input sources and the current date.
    ///
    /// The prompt has three sections:
    /// 1. System instruction with today's date
    /// 2. Extraction rules (derived from test expectations)
    /// 3. Labeled input data (OCR, alt text, caption)
    private static func buildPrompt(
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: currentDate)

        var sections: [String] = []

        // Section 1: System instruction
        sections.append("""
            You are an event extraction system. Extract structured events from \
            the following Instagram post content. Today's date is \(dateString).
            """)

        // Section 2: Extraction rules
        sections.append("""
            RULES:
            1. Format datetimeStart as "YYYY-MM-DD HH:mm" when a specific time is given \
            (e.g., "2026-03-04 19:00"), or "YYYY-MM-DD" for date-only events with no \
            specific time (e.g., multi-day festivals).
            2. Format datetimeEnd the same way. Set to nil if no end time is specified.
            3. When an event ends at midnight, set datetimeEnd to the NEXT calendar day \
            at "00:00". For example, an event on March 13 ending at midnight → \
            datetimeEnd = "2026-03-14 00:00".
            4. "Midnite", "midnight", "12AM", "12 AM" all mean 00:00 of the next day.
            5. When the year is not specified in the text, infer it from today's date \
            (\(dateString)). For example, "March 13" → "2026-03-13".
            6. Convert all times to Eastern Time (ET). If the text says "4 PM PT / 7 ET", \
            use 19:00 (7 PM ET). If only ET/EST is given, use that directly.
            7. If the caption explicitly corrects a time from the OCR (e.g., \
            "****TYPO - 8PM - 12AM***"), use the caption's corrected time.
            8. Only extract FUTURE events. If the post is a recap of a past event \
            (mentions "last night", "thank you to everyone who came", or similar \
            past-tense language about the event), return zero events.
            9. If no events with dates/times are found in the text, return an empty \
            events array. Random text without date information = no events.
            10. For events listing both "doors" and "show" times, use the doors time \
            as datetimeStart (e.g., "Doors: 6:30 p.m. Show: 7:00 p.m." → start at 18:30).
            11. Multiple performers at the same event = ONE event entry. Do not create \
            separate events for each performer.
            12. Description should be a short event title with key performers or hosts. \
            Do NOT include dates, times, prices, addresses, or registration URLs.
            13. Return events in chronological order by datetimeStart.
            14. The text may be in any language (English, Spanish, etc.) — extract events \
            regardless of language.
            15. OCR text may have artifacts, misspellings, and line breaks — interpret \
            them as best you can.
            16. Time ranges like "7-11pm" mean 7 PM to 11 PM (19:00 to 23:00). \
            "7-Midnite" means 7 PM to midnight (19:00 to next day 00:00). \
            "8-12PM" in context of a nighttime event likely means 8 PM to midnight, \
            but defer to the caption if it provides a correction.
            """)

        // Section 3: Input data
        let nonEmptyOCR = ocrTexts.enumerated()
            .filter { !$1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !nonEmptyOCR.isEmpty {
            let combined = nonEmptyOCR
                .map { "--- OCR Text \($0.offset + 1) ---\n\($0.element)" }
                .joined(separator: "\n\n")
            sections.append("OCR TEXT FROM IMAGES:\n\(combined)")
        }

        let nonEmptyAlt = altTexts.enumerated()
            .filter { !$1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !nonEmptyAlt.isEmpty {
            let combined = nonEmptyAlt
                .map { "--- Alt Text \($0.offset + 1) ---\n\($0.element)" }
                .joined(separator: "\n\n")
            sections.append("IMAGE ALT TEXTS:\n\(combined)")
        }

        if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("POST CAPTION:\n\(caption)")
        }

        return sections.joined(separator: "\n\n")
    }
}
