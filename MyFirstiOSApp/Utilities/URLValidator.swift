/// URLValidator.swift
/// ==================
/// Validates and parses Instagram post URLs.
///
/// ## Why a Caseless Enum?
/// Like `AppConstants`, this is a caseless enum used purely as a namespace for static
/// methods. A caseless enum cannot be instantiated, which prevents accidental misuse.
///
/// ## Validation Rules
/// - URL must parse as a valid URL
/// - Host must be `instagram.com` (with or without `www.`)
/// - Path must contain `/p/` (the Instagram post path segment)
/// - Reels (`/reel/`, `/reels/`) and stories (`/stories/`) are explicitly rejected
///   because they require different parsing strategies

import Foundation

/// Errors that can occur when validating an Instagram URL.
/// Conforms to `Equatable` for easy test assertions. The `unsupportedContent` case
/// carries a description of what was detected (e.g., "reel", "story").
enum URLValidationError: LocalizedError, Equatable {
    case emptyInput
    case invalidURL
    case notInstagram
    case unsupportedContent(String)
    case missingPostPath

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Please enter a URL."
        case .invalidURL:
            return "That doesn't look like a valid URL."
        case .notInstagram:
            return "Only Instagram URLs are supported."
        case .unsupportedContent(let kind):
            return "Instagram \(kind) are not supported yet — only posts (/p/) are accepted."
        case .missingPostPath:
            return "This doesn't look like an Instagram post URL. Post URLs contain /p/ in the path."
        }
    }
}

/// Namespace for Instagram URL validation logic.
enum URLValidator {

    /// Validates that a string is a well-formed Instagram post URL.
    ///
    /// - Parameter string: The raw user input (may contain whitespace).
    /// - Returns: A `Result` with the parsed `URL` on success, or a `URLValidationError` on failure.
    static func validate(_ string: String) -> Result<URL, URLValidationError> {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .failure(.emptyInput)
        }

        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            return .failure(.invalidURL)
        }

        guard let host = url.host, host.contains("instagram.com") else {
            return .failure(.notInstagram)
        }

        let path = url.path.lowercased()

        // Reject known unsupported content types before checking for /p/.
        if path.contains("/reel/") || path.contains("/reels/") || path.hasPrefix("/reel") {
            return .failure(.unsupportedContent("reels"))
        }
        if path.contains("/stories/") {
            return .failure(.unsupportedContent("stories"))
        }

        // The path must contain /p/ to be a post URL.
        guard path.contains("/p/") else {
            return .failure(.missingPostPath)
        }

        return .success(url)
    }

    /// Extracts the first Instagram URL from arbitrary text.
    ///
    /// Useful for Share Extension scenarios where Instagram may send a URL
    /// embedded in a larger text string (e.g., "Check out this post: https://...").
    ///
    /// - Parameter sharedText: Arbitrary text that may contain an Instagram URL.
    /// - Returns: The first Instagram URL string found, or `nil` if none.
    static func extractURL(from sharedText: String) -> String? {
        // Match URLs that contain instagram.com/p/ with an optional path, query, and fragment.
        let pattern = #"https?://(?:www\.)?instagram\.com/p/[A-Za-z0-9_-]+[^\s]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(sharedText.startIndex..., in: sharedText)
        guard let match = regex.firstMatch(in: sharedText, range: range) else {
            return nil
        }
        guard let matchRange = Range(match.range, in: sharedText) else {
            return nil
        }
        return String(sharedText[matchRange])
    }

    /// Removes tracking query parameters from an Instagram URL.
    ///
    /// Instagram appends parameters like `igsh=` and `utm_source=` when sharing.
    /// These are not needed for content extraction and clutter the URL.
    ///
    /// - Parameter url: The Instagram URL, possibly with tracking params.
    /// - Returns: A clean URL with all query parameters removed.
    static func stripTrackingParams(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = nil
        components.query = nil
        return components.url ?? url
    }
}
