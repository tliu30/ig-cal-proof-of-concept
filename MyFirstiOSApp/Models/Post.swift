/// Post.swift
/// ==========
/// Data model representing an extracted Instagram post.
///
/// ## How Swift Structs Work
/// In Swift, `struct` defines a value type — when you assign a struct to a new variable
/// or pass it to a function, it gets copied (unlike classes, which are reference types).
/// Structs are the preferred way to model simple data in Swift because they're lightweight,
/// thread-safe (no shared mutable state), and the compiler can optimize them aggressively.
///
/// ## Identifiable Protocol
/// `Identifiable` is a protocol that requires an `id` property. SwiftUI uses this to
/// efficiently track items in lists and collections — when the data changes, SwiftUI
/// compares IDs to figure out which items were added, removed, or moved, rather than
/// re-rendering everything.
///
/// ## Codable Protocol
/// `Codable` (which is shorthand for both `Encodable` and `Decodable`) lets Swift
/// automatically serialize/deserialize the struct to/from JSON, Property Lists, etc.
/// The compiler generates the encoding/decoding code as long as all stored properties
/// are themselves `Codable`.

import Foundation

/// Represents the data extracted from a single Instagram post.
/// This includes the text content of the post, the full-size image URLs found in the DOM,
/// the raw HTML page source (for debugging), and the OCR results for each image.
struct Post: Identifiable {
    /// Unique identifier for this post. `UUID()` generates a random 128-bit ID.
    let id = UUID()

    /// The URL of the Instagram post that was loaded.
    let url: URL

    /// The text content extracted from the post (caption, comments, etc.).
    let textContent: String

    /// URLs of full-size images found on the page.
    /// Instagram serves multiple sizes; we specifically extract the largest available.
    let imageURLs: [URL]

    /// The full HTML source of the loaded page, used for debugging.
    let pageSource: String

    /// OCR results for each image, keyed by image URL string.
    /// Each entry maps an image URL to the text recognized in that image.
    var ocrResults: [URL: OCRResult]
}
