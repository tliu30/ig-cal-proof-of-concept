/// ExtractedEvent.swift
/// ====================
/// Data model for a date/time event extracted from unstructured text.
///
/// ## What This Represents
/// When the app processes an Instagram post, it extracts text from both the HTML
/// (post captions, comments) and from images via OCR. This struct represents a single
/// event found in that text — for example, a concert, DJ night, or party — with its
/// start time, optional end time, and a short description.
///
/// ## How It's Used
/// `EventExtractionService.extractEvents(...)` returns an array of these structs.
/// The extraction logic takes messy, unstructured text (possibly with OCR artifacts,
/// informal time formats like "7-Midnite", and multi-line descriptions) and produces
/// clean, structured event data.
///
/// ## Equatable Conformance
/// The custom `==` implementation compares only the three data fields (`datetimeStart`,
/// `datetimeEnd`, `description`), ignoring the auto-generated `id`. This makes it easy
/// to write test assertions like `#expect(result.contains(expectedEvent))` without
/// needing to match UUIDs.

import Foundation

/// A single event extracted from post text, with start/end datetimes and a description.
struct ExtractedEvent: Identifiable, Equatable {
    /// Unique identifier for SwiftUI list rendering.
    let id = UUID()

    /// Start datetime formatted as "YYYY-MM-DD HH:mm" (e.g., "2026-03-04 19:00").
    let datetimeStart: String

    /// End datetime formatted as "YYYY-MM-DD HH:mm", or nil if unknown.
    /// When an event ends at midnight, this is the next calendar day at "00:00"
    /// (e.g., an event on March 13 ending at midnight has datetimeEnd "2026-03-14 00:00").
    let datetimeEnd: String?

    /// A short description of the event, typically the event name and performers.
    let description: String

    /// Compares two events by their data fields only, ignoring the auto-generated `id`.
    static func == (lhs: ExtractedEvent, rhs: ExtractedEvent) -> Bool {
        lhs.datetimeStart == rhs.datetimeStart
            && lhs.datetimeEnd == rhs.datetimeEnd
            && lhs.description == rhs.description
    }
}
