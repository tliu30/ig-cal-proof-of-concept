// TrainingData.swift
// ==================
// Data models for user-corrected training examples used to improve event extraction.
//
// ## Purpose
// When the app extracts events from an Instagram post, the four algorithms (Regex,
// NSDataDetector, Foundation Models, Llama) may produce imperfect results. The user
// can manually correct these results and save them as "training examples" — ground-truth
// data that can later be used to evaluate and improve the algorithms.
//
// ## Structure
// A `TrainingExample` represents one Instagram post's corrected events:
// - `url`: The Instagram post URL
// - `createdAt`: When the example was saved
// - `events`: An array of `TrainingEvent` objects with corrected datetime/description fields
//
// Both structs conform to `Codable` for JSON serialization (persistence and export).

import Foundation

/// A single corrected event within a training example.
///
/// All properties are `var` because the user edits them in the UI before saving.
/// An empty `datetimeEnd` string represents "no end time" (maps to null in export).
struct TrainingEvent: Codable, Identifiable {
    /// Unique identifier for SwiftUI list rendering.
    var id = UUID()

    /// Start datetime in "YYYY-MM-DD HH:mm" format (e.g., "2026-03-04 19:00").
    var datetimeStart: String

    /// End datetime in "YYYY-MM-DD HH:mm" format, or empty string if unknown.
    var datetimeEnd: String

    /// Short event description (e.g., event name, performers).
    var description: String
}

/// A complete training example: one Instagram post's URL and its corrected events.
struct TrainingExample: Codable, Identifiable {
    /// Unique identifier for this example.
    var id = UUID()

    /// The Instagram post URL that was analyzed.
    var url: String

    /// When this training example was saved.
    var createdAt: Date

    /// The user-corrected list of events extracted from this post.
    var events: [TrainingEvent]
}
