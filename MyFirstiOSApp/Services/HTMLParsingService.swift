/// HTMLParsingService.swift
/// ========================
/// Provides HTML parsing utilities for cleaning and extracting content from Instagram
/// page source HTML, using SwiftSoup for DOM-based manipulation.
///
/// ## Why SwiftSoup?
/// SwiftSoup is a pure-Swift port of Java's jsoup library. It parses real-world
/// (often messy) HTML into a DOM tree and supports CSS selector queries — the same
/// selectors you would use in JavaScript's `document.querySelector()`. Because it
/// operates on the DOM tree rather than raw text, operations like "remove all
/// `<script>` tags" will never accidentally delete a `<span>` whose text content
/// happens to mention the word "script".
///
/// ## Three Levels of Parsing
///
/// 1. **Preprocessing** — strips `<head>`, `<script>`, and `<link>` elements to
///    reduce a ~1 MB Instagram page dump to ~100 KB of meaningful body content.
///
/// 2. **Image extraction** — pulls `src` URLs and `alt` text from every `<img>` tag.
///
/// 3. **Caption extraction** — collects visible text from `<span>` elements that are
///    long enough (>20 characters) to be actual post captions rather than UI labels.
///
/// ## Usage
///
/// ```swift
/// let cleaned = try HTMLParsingService.preprocessHTML(rawHTML)
/// let urls    = try HTMLParsingService.extractImageURLs(from: cleaned)
/// let alts    = try HTMLParsingService.extractImageAltTexts(from: cleaned)
/// let caps    = try HTMLParsingService.extractCaptions(from: cleaned)
/// ```
///
/// ## Design
/// This is a caseless `enum` (cannot be instantiated) that acts as a pure namespace
/// for static functions — the same pattern used by `AppConstants`.

import Foundation
import SwiftSoup

enum HTMLParsingService {

    // MARK: - Preprocessing

    /// Removes the `<head>` element (and everything inside it), all `<script>` tags,
    /// and all `<link>` tags from the given HTML string.
    ///
    /// - Parameter html: Raw HTML string (e.g., from `document.documentElement.outerHTML`).
    /// - Returns: Cleaned HTML string with only body content remaining.
    /// - Throws: `SwiftSoup.Exception` if the HTML cannot be parsed.
    ///
    /// ### How It Works
    /// SwiftSoup parses the HTML into a tree of `Element` nodes. The CSS selector
    /// `"script"` matches every `<script>` element regardless of its attributes
    /// (`type`, `src`, `nonce`, etc.). Calling `.remove()` on the selection detaches
    /// those nodes from the tree. Finally, `.outerHtml()` serializes the cleaned
    /// tree back to an HTML string.
    static func preprocessHTML(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)

        // Remove <head> and all its children (stylesheets, meta tags, head-level scripts)
        try doc.select("head").remove()

        // Remove any <script> tags remaining in <body>
        try doc.select("script").remove()

        // Remove any <link> tags remaining in <body> (preload hints, etc.)
        try doc.select("link").remove()

        return try doc.outerHtml()
    }

    // MARK: - Image Extraction

    /// Extracts the `src` attribute from every `<img>` tag in the HTML.
    ///
    /// - Parameter html: HTML string to search.
    /// - Returns: Array of image URL strings. HTML entities like `&amp;` are
    ///   automatically decoded to `&` by SwiftSoup.
    /// - Throws: `SwiftSoup.Exception` if the HTML cannot be parsed.
    static func extractImageURLs(from html: String) throws -> [String] {
        let doc = try SwiftSoup.parse(html)
        let imgs = try doc.select("img")

        return try imgs.compactMap { img in
            let src = try img.attr("src")
            return src.isEmpty ? nil : src
        }
    }

    /// Extracts the `alt` attribute from every `<img>` tag in the HTML.
    ///
    /// - Parameter html: HTML string to search.
    /// - Returns: Array of alt text strings, one per `<img>` tag. Images with empty
    ///   or missing `alt` attributes produce empty strings. The array is positionally
    ///   aligned with the results of ``extractImageURLs(from:)`` when called on the
    ///   same HTML.
    /// - Throws: `SwiftSoup.Exception` if the HTML cannot be parsed.
    static func extractImageAltTexts(from html: String) throws -> [String] {
        let doc = try SwiftSoup.parse(html)
        let imgs = try doc.select("img")

        return try imgs.map { img in
            try img.attr("alt")
        }
    }

    // MARK: - Caption Extraction

    /// Extracts post caption text from `<span>` elements whose visible text is
    /// longer than 20 characters.
    ///
    /// - Parameter html: HTML string to search.
    /// - Returns: Array of caption strings, trimmed of leading/trailing whitespace.
    /// - Throws: `SwiftSoup.Exception` if the HTML cannot be parsed.
    ///
    /// ### Why 20 Characters?
    /// Instagram's DOM contains many short `<span>` elements for UI chrome (icons,
    /// labels like "Like", timestamps, etc.). The 20-character threshold filters
    /// these out while keeping meaningful post captions. This matches the heuristic
    /// used in the app's JavaScript extraction logic in `InstagramWebView.swift`.
    static func extractCaptions(from html: String) throws -> [String] {
        let doc = try SwiftSoup.parse(html)
        let spans = try doc.select("span")

        return try spans.compactMap { span in
            let text = try span.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
            return text.count > 20 ? text : nil
        }
    }
}
