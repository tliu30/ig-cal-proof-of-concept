/// EventExtractionServiceTests.swift
/// ==================================
/// Parameterized TDD test suite for all event extraction methods.
///
/// ## Test Organization
/// Tests are organized into three suites:
/// 1. Multi-event flyer extraction (6 events from a single OCR text)
/// 2. Single event extraction (1 event from OCR + caption combined)
/// 3. Edge cases (empty input, no dates)
///
/// Each test runs once per extraction method via `@Test(arguments: testableMethods)`.
/// Foundation Models is excluded (requires iOS 26+ device with model downloaded).
/// Llama is included but will return empty if the model file is not present.

import Foundation
import Testing

@testable import MyFirstiOSApp

// MARK: - Testable Methods

/// Which extraction methods to run in parameterized tests.
/// Foundation Models is excluded — requires iOS 26+ and on-device model availability.
/// Llama is included only when the ~1GB GGUF model file is present on disk.
let testableMethods: [ExtractionMethod] = {
    var methods: [ExtractionMethod] = [.regex, .nsDataDetector]
    if LlamaExtractionService.isModelAvailable {
        methods.append(.llama)
    }
    return methods
}()

// MARK: - Test Data Loading

/// Loads a text file from the test-data/ directory relative to this source file.
/// Uses #filePath to navigate from MyFirstiOSAppTests/ up to the project root.
private func loadTestData(_ filename: String) -> String {
    let thisFile = URL(fileURLWithPath: #filePath)
    let projectRoot = thisFile
        .deletingLastPathComponent() // MyFirstiOSAppTests/
        .deletingLastPathComponent() // project root
    let fileURL = projectRoot.appendingPathComponent("test-data/\(filename)")
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        fatalError("\(filename) not found at \(fileURL.path)")
    }
    return try! String(contentsOf: fileURL, encoding: .utf8)
}

/// Multi-event flyer OCR text (Test Case 1).
private let flyerOCRText = loadTestData("event-flyer-ocr.txt")

/// Single event OCR text (Test Case 2).
private let singleEventOCRText = loadTestData("event-single-ocr.txt")

/// Single event caption (Test Case 2).
private let singleEventCaption = loadTestData("event-single-caption.txt")

/// Fixed reference date: 2026-03-25. All tests use this as "today" for year inference.
private let referenceDate: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 3
    components.day = 25
    return Calendar.current.date(from: components)!
}()

// MARK: - Multi-Event Flyer Extraction Tests

@Suite("Multi-Event Flyer Extraction")
struct MultiEventFlyerTests {

    /// The expected events from the flyer, in chronological order.
    static let expectedEvents: [ExtractedEvent] = [
        ExtractedEvent(
            datetimeStart: "2026-03-04 19:00",
            datetimeEnd: "2026-03-04 23:00",
            description: "OPEN AUX W Featured Artist 1Alkebulan"
        ),
        ExtractedEvent(
            datetimeStart: "2026-03-13 19:00",
            datetimeEnd: "2026-03-14 00:00",
            description: "St. Slayer's Day hosted by DJ ILUVDOMRICH"
        ),
        ExtractedEvent(
            datetimeStart: "2026-03-18 19:00",
            datetimeEnd: "2026-03-18 23:00",
            description: "OPEN AUX W/ Special Guest TBA"
        ),
        ExtractedEvent(
            datetimeStart: "2026-03-27 19:00",
            datetimeEnd: "2026-03-28 00:00",
            description: "A Caratasrophe PreGame Vol.5 with resident DJ Caratasrophe"
        ),
        ExtractedEvent(
            datetimeStart: "2026-03-28 19:00",
            datetimeEnd: "2026-03-29 00:00",
            description: "Rythms&Release Party+JamSession Hoseted By Nelson Bandela"
        ),
        ExtractedEvent(
            datetimeStart: "2026-03-31 19:00",
            datetimeEnd: "2026-03-31 22:30",
            description: "M'KAI & friends a special evening of music featuring M'vKAI"
        ),
    ]

    @Test("Extracts exactly 6 events from flyer", arguments: testableMethods)
    func extractsCorrectCount(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [flyerOCRText],
            altTexts: [],
            caption: "",
            currentDate: referenceDate
        )
        #expect(results.count == 6, "Expected 6 events, got \(results.count)")
    }

    @Test("Each expected event is present in the results", arguments: testableMethods)
    func containsAllExpectedEvents(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [flyerOCRText],
            altTexts: [],
            caption: "",
            currentDate: referenceDate
        )
        for expected in Self.expectedEvents {
            #expect(
                resultsContain(results, expected: expected),
                "Missing event: \(expected.datetimeStart) — \(expected.description)"
            )
        }
    }

    @Test("Midnight end times are on the next calendar day", arguments: testableMethods)
    func midnightEndTimesAreNextDay(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [flyerOCRText],
            altTexts: [],
            caption: "",
            currentDate: referenceDate
        )
        // St. Slayer's Day on March 13 ends at midnight = March 14 00:00
        let stSlayers = results.first { $0.description.contains("Slayer") }
        #expect(stSlayers != nil, "St. Slayer's Day event not found")
        #expect(stSlayers?.datetimeEnd == "2026-03-14 00:00")

        // Caratasrophe PreGame on March 27 ends at midnight = March 28 00:00
        let caratasrophe = results.first { $0.description.contains("Caratasrophe") }
        #expect(caratasrophe != nil, "Caratasrophe event not found")
        #expect(caratasrophe?.datetimeEnd == "2026-03-28 00:00")
    }

    @Test("M'KAI event ends at 22:30, not midnight", arguments: testableMethods)
    func mkaiEventEndsAt2230(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [flyerOCRText],
            altTexts: [],
            caption: "",
            currentDate: referenceDate
        )
        let mkai = results.first { $0.description.contains("M'KAI") }
        #expect(mkai != nil, "M'KAI event not found")
        #expect(mkai?.datetimeEnd == "2026-03-31 22:30")
    }

    @Test("All events have year 2026", arguments: testableMethods)
    func allEventsHave2026(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [flyerOCRText],
            altTexts: [],
            caption: "",
            currentDate: referenceDate
        )
        for event in results {
            #expect(event.datetimeStart.hasPrefix("2026-"), "Event year is not 2026: \(event.datetimeStart)")
        }
    }
}

// MARK: - Single Event with Caption Tests

@Suite("Single Event with Caption Extraction")
struct SingleEventTests {

    @Test("Extracts exactly 1 event", arguments: testableMethods)
    func extractsOneEvent(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [singleEventOCRText],
            altTexts: [],
            caption: singleEventCaption,
            currentDate: referenceDate
        )
        #expect(results.count == 1, "Expected 1 event, got \(results.count)")
    }

    @Test("Event date is March 27, 2026 at 22:00", arguments: testableMethods)
    func correctDateAndTime(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [singleEventOCRText],
            altTexts: [],
            caption: singleEventCaption,
            currentDate: referenceDate
        )
        let event = results.first
        #expect(event != nil, "No event extracted")
        #expect(event?.datetimeStart == "2026-03-27 22:00")
    }

    @Test("End time is nil", arguments: testableMethods)
    func endTimeIsNil(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [singleEventOCRText],
            altTexts: [],
            caption: singleEventCaption,
            currentDate: referenceDate
        )
        let event = results.first
        #expect(event != nil, "No event extracted")
        #expect(event?.datetimeEnd == nil, "End time should be nil, got \(event?.datetimeEnd ?? "nil")")
    }

    @Test("Description comes from caption first sentence", arguments: testableMethods)
    func descriptionFromCaption(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [singleEventOCRText],
            altTexts: [],
            caption: singleEventCaption,
            currentDate: referenceDate
        )
        let event = results.first
        #expect(event != nil, "No event extracted")
        let overlap = descriptionWordOverlap(
            actual: event?.description ?? "",
            expected: "4 YEARS STRONG, SAZONAO RETURNS THIS FRIDAY TO @friendsandloversbk!"
        )
        #expect(overlap >= 0.5, "Description word overlap too low (\(overlap)): \(event?.description ?? "nil")")
    }
}

// MARK: - Edge Cases

@Suite("Event Extraction Edge Cases")
struct EventExtractionEdgeCaseTests {

    @Test("Empty input returns empty array", arguments: testableMethods)
    func emptyInput(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: [],
            altTexts: [],
            caption: "",
            currentDate: referenceDate
        )
        #expect(results.isEmpty, "Expected empty results for empty input")
    }

    @Test("Text with no dates returns empty array", arguments: testableMethods)
    func noDatesInText(method: ExtractionMethod) {
        let results = EventExtractionService.extractEvents(
            using: method,
            ocrTexts: ["Just some random text with no dates or times mentioned anywhere"],
            altTexts: ["A photo of a sunset"],
            caption: "Beautiful evening at the park",
            currentDate: referenceDate
        )
        #expect(results.isEmpty, "Expected empty results when no dates found")
    }
}
