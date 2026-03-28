/// HTMLParsingServiceTests.swift
/// =============================
/// TDD test suite for HTMLParsingService, using a real Instagram HTML dump as test data.
///
/// Tests are organized by the three parsing levels:
/// 1. Preprocessing (head/script/link removal)
/// 2. Image URL extraction
/// 3. Image alt text extraction
/// 4. Caption extraction
/// 5. Edge cases with synthetic HTML

import Foundation
import SwiftSoup
import Testing

@testable import MyFirstiOSApp

/// Loads the HTML dump once for all tests in this file.
/// Uses the source file path (#file) to navigate to the project root and find test-data/dump.html.
private let testHTML: String = {
    let thisFile = URL(fileURLWithPath: #filePath)
    let projectRoot = thisFile
        .deletingLastPathComponent() // MyFirstiOSAppTests/
        .deletingLastPathComponent() // project root
    let dumpURL = projectRoot.appendingPathComponent("test-data/dump.html")
    guard FileManager.default.fileExists(atPath: dumpURL.path) else {
        fatalError("dump.html not found at \(dumpURL.path)")
    }
    return try! String(contentsOf: dumpURL)
}()

// MARK: - Preprocessing Tests

@Suite("Preprocessing")
struct PreprocessingTests {

    @Test("Removes the head tag contents")
    func removesHeadTag() throws {
        let result = try HTMLParsingService.preprocessHTML(testHTML)
        let doc = try SwiftSoup.parse(result)
        // SwiftSoup re-creates an empty <head> during document normalization,
        // so we verify it has no children rather than checking for absence.
        let headChildren = try doc.select("head > *")
        #expect(headChildren.isEmpty(), "Head should have no children after preprocessing")
    }

    @Test("Removes all 142 script tags")
    func removesAllScriptTags() throws {
        let result = try HTMLParsingService.preprocessHTML(testHTML)
        let doc = try SwiftSoup.parse(result)
        #expect(try doc.select("script").isEmpty())
    }

    @Test("Removes all 122 link tags")
    func removesAllLinkTags() throws {
        let result = try HTMLParsingService.preprocessHTML(testHTML)
        let doc = try SwiftSoup.parse(result)
        #expect(try doc.select("link").isEmpty())
    }

    @Test("Preserves all 14 img tags")
    func preservesAllImgTags() throws {
        let result = try HTMLParsingService.preprocessHTML(testHTML)
        let doc = try SwiftSoup.parse(result)
        #expect(try doc.select("img").size() == 14)
    }

    @Test("Preserves span text content")
    func preservesSpanContent() throws {
        let result = try HTMLParsingService.preprocessHTML(testHTML)
        #expect(result.contains("Got a full month of evening programming ahead"))
    }

    @Test("Does not delete text that merely mentions 'script'")
    func doesNotDeleteTextMentioningScript() throws {
        let html = "<html><body><span>This script runs fast</span><script>var x = 1;</script></body></html>"
        let result = try HTMLParsingService.preprocessHTML(html)
        #expect(result.contains("This script runs fast"))
        let doc = try SwiftSoup.parse(result)
        #expect(try doc.select("script").isEmpty())
    }

    @Test("Significantly reduces HTML size after removing head and scripts")
    func reducesSize() throws {
        let result = try HTMLParsingService.preprocessHTML(testHTML)
        #expect(result.utf8.count < 120_000, "Expected output < 120KB, got \(result.utf8.count)")
    }
}

// MARK: - Image URL Extraction Tests

@Suite("Image URL Extraction")
struct ImageURLExtractionTests {

    @Test("Finds all 14 image URLs")
    func findsAll14Images() throws {
        let urls = try HTMLParsingService.extractImageURLs(from: testHTML)
        #expect(urls.count == 14)
    }

    @Test("All URLs contain the Instagram CDN domain")
    func allURLsContainCDNDomain() throws {
        let urls = try HTMLParsingService.extractImageURLs(from: testHTML)
        for url in urls {
            #expect(url.contains("cdninstagram.com"), "URL missing CDN domain: \(url.prefix(80))")
        }
    }

    @Test("HTML entities in URLs are decoded (& not &amp;)")
    func decodesHTMLEntitiesInURLs() throws {
        let urls = try HTMLParsingService.extractImageURLs(from: testHTML)
        for url in urls {
            #expect(!url.contains("&amp;"), "URL still has &amp;: \(url.prefix(80))")
        }
    }
}

// MARK: - Image Alt Text Extraction Tests

@Suite("Image Alt Text Extraction")
struct ImageAltTextExtractionTests {

    @Test("Returns 14 alt texts (one per img)")
    func returns14AltTexts() throws {
        let alts = try HTMLParsingService.extractImageAltTexts(from: testHTML)
        #expect(alts.count == 14)
    }

    @Test("Contains a profile picture alt text")
    func containsProfilePicture() throws {
        let alts = try HTMLParsingService.extractImageAltTexts(from: testHTML)
        #expect(alts.contains { $0.contains("profile picture") })
    }

    @Test("Contains the main post description")
    func containsPostDescription() throws {
        let alts = try HTMLParsingService.extractImageAltTexts(from: testHTML)
        #expect(alts.contains { $0.hasPrefix("Photo shared by @ddooll.2") })
    }

    @Test("Includes empty alt text entries")
    func includesEmptyAlt() throws {
        let alts = try HTMLParsingService.extractImageAltTexts(from: testHTML)
        #expect(alts.contains(""))
    }

    @Test("HTML entities in alt text are decoded")
    func decodesHTMLEntitiesInAlt() throws {
        let alts = try HTMLParsingService.extractImageAltTexts(from: testHTML)
        // Find the alt that originally had "&amp;" in the HTML source (Kalimotxo & Evening French Toast)
        let kalimotxoAlt = alts.first { $0.contains("Kalimotxo") && $0.contains("French Toast") }
        #expect(kalimotxoAlt != nil, "Expected an alt text mentioning Kalimotxo & French Toast")
        #expect(kalimotxoAlt?.contains("&amp;") == false, "Alt text still has &amp;")
        #expect(kalimotxoAlt?.contains("&") == true, "Alt text should have decoded &")
    }
}

// MARK: - Caption Extraction Tests

@Suite("Caption Extraction")
struct CaptionExtractionTests {

    @Test("Finds the main post caption")
    func findsMainCaption() throws {
        let captions = try HTMLParsingService.extractCaptions(from: testHTML)
        #expect(captions.contains {
            $0.contains("Got a full month of evening programming ahead")
        })
    }

    @Test("All captions are longer than 20 characters")
    func filtersShortText() throws {
        let captions = try HTMLParsingService.extractCaptions(from: testHTML)
        for caption in captions {
            #expect(caption.count > 20, "Caption too short: \"\(caption)\"")
        }
    }

    @Test("Finds the expected number of captions")
    func findsExpectedCount() throws {
        let captions = try HTMLParsingService.extractCaptions(from: testHTML)
        #expect(captions.count == 9)
    }

    @Test("HTML entities in captions are decoded")
    func decodesEntities() throws {
        let captions = try HTMLParsingService.extractCaptions(from: testHTML)
        let contactCaption = captions.first { $0.contains("Contact Uploading") }
        #expect(contactCaption != nil)
        #expect(contactCaption?.contains("&") == true)
        #expect(contactCaption?.contains("&amp;") == false)
    }
}

// MARK: - Caption from Embedded JSON Tests

@Suite("Caption from Embedded JSON")
struct CaptionFromEmbeddedJSONTests {

    @Test("Extracts the main post caption from dump.html")
    func extractsMainCaption() {
        let caption = HTMLParsingService.extractCaptionFromEmbeddedJSON(from: testHTML)
        #expect(caption != nil)
        #expect(caption == "Got a full month of evening programming ahead. Which one will we see you at?")
    }

    @Test("Returns full untruncated text (not og:description which may be shortened)")
    func returnsFullText() {
        let caption = HTMLParsingService.extractCaptionFromEmbeddedJSON(from: testHTML)
        // The full caption should NOT have the "39 likes, 1 comments - ..." prefix
        #expect(caption?.contains("likes") == false)
        #expect(caption?.contains("comments") == false)
    }

    @Test("Decodes JSON escape sequences")
    func decodesJSONEscapes() {
        let html = #"""
        <script>"caption":{"pk":"123","text":"Line one\nLine two \u0040user #tag"}</script>
        """#
        let caption = HTMLParsingService.extractCaptionFromEmbeddedJSON(from: html)
        #expect(caption == "Line one\nLine two @user #tag")
    }

    @Test("Returns nil when no caption JSON is present")
    func returnsNilForNoCaption() {
        let caption = HTMLParsingService.extractCaptionFromEmbeddedJSON(from: "<html><body>No JSON here</body></html>")
        #expect(caption == nil)
    }
}

// MARK: - Edge Case Tests

@Suite("Edge Cases")
struct EdgeCaseTests {

    @Test("Empty HTML returns empty results without throwing")
    func emptyHTML() throws {
        let preprocessed = try HTMLParsingService.preprocessHTML("")
        #expect(!preprocessed.isEmpty) // SwiftSoup wraps in <html><head></head><body></body></html>

        let urls = try HTMLParsingService.extractImageURLs(from: "")
        #expect(urls.isEmpty)

        let alts = try HTMLParsingService.extractImageAltTexts(from: "")
        #expect(alts.isEmpty)

        let captions = try HTMLParsingService.extractCaptions(from: "")
        #expect(captions.isEmpty)
    }

    @Test("Head tag contents are removed when present")
    func htmlWithHeadTag() throws {
        let html = """
            <html>
            <head><title>Test</title><script>alert(1)</script></head>
            <body><img src="a.jpg" alt="test image"><span>Keep this long enough text content here</span></body>
            </html>
            """
        let result = try HTMLParsingService.preprocessHTML(html)
        let doc = try SwiftSoup.parse(result)
        #expect(try doc.select("head > *").isEmpty(), "Head should have no children")
        #expect(try doc.select("script").isEmpty())
        #expect(try doc.select("img").size() == 1)
        #expect(result.contains("Keep this long enough text content here"))
    }
}
