/// Constants.swift
/// ===============
/// App-wide constants collected in one place.
///
/// ## Why an Enum with No Cases?
/// In Swift, a `case`-less enum cannot be instantiated — it acts purely as a namespace.
/// This is the idiomatic Swift pattern for grouping related constants. You access them
/// as `AppConstants.instagramURL`, etc. Using an enum (rather than a struct) prevents
/// anyone from accidentally creating an instance of the constants container.

import Foundation

/// Namespace for app-wide constant values.
enum AppConstants {
    /// The fixed Instagram post URL that the app loads on launch.
    /// Change this URL to point to any public Instagram post you want to analyze.
    static let instagramURL = URL(string: "https://www.instagram.com/p/DVb33j7lVEm/")!

    /// Mobile Safari user agent string.
    /// Instagram checks the User-Agent header and will block or degrade content
    /// if it detects a non-browser client. We spoof Mobile Safari so Instagram
    /// serves the same HTML/JS it would send to a real iPhone browser.
    static let mobileSafariUserAgent = """
        Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) \
        AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 \
        Mobile/15E148 Safari/604.1
        """

    /// How long (in seconds) to wait after the page "finishes" loading before
    /// extracting content. Instagram's client-side JS needs extra time to render
    /// the actual post content into the DOM after the initial HTML loads.
    static let pageLoadDelay: UInt64 = 5_000_000_000 // 5 seconds in nanoseconds

    /// Maximum time (in seconds) to wait for the entire extraction process
    /// before giving up and showing an error.
    static let extractionTimeout: TimeInterval = 30
}
