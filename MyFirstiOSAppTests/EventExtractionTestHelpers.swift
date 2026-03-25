/// EventExtractionTestHelpers.swift
/// ================================
/// Shared helper functions for fuzzy description matching in event extraction tests.
///
/// ## Why Fuzzy Matching?
/// Event descriptions are extracted from messy OCR text and Instagram captions.
/// Different implementations may produce slightly different phrasing for the same event.
/// Instead of requiring exact string equality, we check that at least 50% of the
/// expected description's words appear in the actual description (case-insensitive).
///
/// ## Usage
/// - `descriptionWordOverlap(actual:expected:)` — returns the fraction of expected words found
/// - `eventMatches(_:expected:)` — checks datetimeStart/End exactly, description fuzzily
/// - `resultsContain(_:expected:)` — checks if any result event fuzzy-matches an expected event

import Foundation

@testable import MyFirstiOSApp

/// Computes the fraction of words in `expected` that appear in `actual`.
/// Both strings are lowercased and split on whitespace before comparison.
/// Returns 1.0 if `expected` is empty.
func descriptionWordOverlap(actual: String, expected: String) -> Double {
    let actualWords = Set(actual.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    let expectedWords = expected.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    guard !expectedWords.isEmpty else { return 1.0 }
    let matchCount = expectedWords.filter { actualWords.contains($0) }.count
    return Double(matchCount) / Double(expectedWords.count)
}

/// Checks if a result event matches an expected event:
/// `datetimeStart` and `datetimeEnd` must match exactly;
/// `description` must have at least `descriptionThreshold` word overlap (default 50%).
func eventMatches(
    _ result: ExtractedEvent,
    expected: ExtractedEvent,
    descriptionThreshold: Double = 0.5
) -> Bool {
    result.datetimeStart == expected.datetimeStart
        && result.datetimeEnd == expected.datetimeEnd
        && descriptionWordOverlap(actual: result.description, expected: expected.description) >= descriptionThreshold
}

/// Returns true if any event in `results` fuzzy-matches the `expected` event.
func resultsContain(
    _ results: [ExtractedEvent],
    expected: ExtractedEvent,
    descriptionThreshold: Double = 0.5
) -> Bool {
    results.contains { eventMatches($0, expected: expected, descriptionThreshold: descriptionThreshold) }
}
