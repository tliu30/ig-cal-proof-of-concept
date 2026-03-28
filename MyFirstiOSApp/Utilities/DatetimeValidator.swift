// DatetimeValidator.swift
// ======================
// Validates datetime strings for the training data editor.
//
// ## Format
// Training events use the format "YYYY-MM-DD HH:mm" (e.g., "2026-03-04 19:00").
// The `datetimeEnd` field may also be empty, meaning "no end time."
//
// ## Usage
// Validation runs when the user taps "Save" — not on every keystroke — so they
// can freely type without being interrupted by errors mid-entry.

import Foundation

/// Validates datetime strings against the expected "YYYY-MM-DD HH:mm" format.
enum DatetimeValidator {
    /// A DateFormatter configured for strict "yyyy-MM-dd HH:mm" parsing.
    /// Uses POSIX locale to avoid locale-dependent parsing quirks.
    private static let formatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.isLenient = false
        return fmt
    }()

    /// Validates a datetime string.
    ///
    /// - Parameter string: The datetime string to validate.
    /// - Parameter allowEmpty: If true, an empty/whitespace-only string is valid (for optional fields).
    /// - Returns: `nil` if valid, or an error message string if invalid.
    static func validate(_ string: String, allowEmpty: Bool = false) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return allowEmpty ? nil : "Required — use format YYYY-MM-DD HH:mm"
        }

        guard formatter.date(from: trimmed) != nil else {
            return "Invalid format — expected YYYY-MM-DD HH:mm"
        }

        return nil
    }
}
