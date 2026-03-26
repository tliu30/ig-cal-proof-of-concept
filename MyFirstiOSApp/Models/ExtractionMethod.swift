/// ExtractionMethod.swift
/// =====================
/// Defines the four event extraction algorithms and their UI/state types.
///
/// ## ExtractionMethod
/// Each case represents a different approach to extracting structured events
/// from unstructured text (OCR output, alt text, captions). All four run in
/// parallel after OCR completes; results are displayed in separate tabs.
///
/// ## ExtractionState
/// Tracks per-method progress so each tab can independently show a spinner,
/// results, or an error/skip message.
///
/// ## ExtractionInputs
/// Bundles the text signals that all extraction services consume. Built once
/// after OCR and HTML parsing, then shared across all four methods.

import Foundation

/// Identifies which extraction algorithm produced a set of results.
enum ExtractionMethod: String, CaseIterable, Identifiable {
    case regex = "Regex"
    case nsDataDetector = "NSDataDetector"
    case foundationModels = "Foundation Models"
    case llama = "Llama LLM"

    var id: String { rawValue }

    /// Short label for tab display.
    var tabLabel: String { rawValue }

    /// SF Symbol icon for each method.
    var icon: String {
        switch self {
        case .regex: return "textformat.abc"
        case .nsDataDetector: return "calendar.badge.clock"
        case .foundationModels: return "cpu"
        case .llama: return "brain.head.profile"
        }
    }
}

/// Represents the loading/result state for one extraction method.
enum ExtractionState {
    case idle
    case running
    case completed([ExtractedEvent])
    case failed(String)
    case skipped(String)
}

/// Bundles the inputs that all extraction services need.
struct ExtractionInputs {
    let ocrTexts: [String]
    let altTexts: [String]
    let caption: String
    let currentDate: Date
}
