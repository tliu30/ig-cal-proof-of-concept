/// URLValidatorTests.swift
/// ======================
/// TDD tests for Instagram URL validation. Written before the implementation
/// to define the expected behavior of URLValidator.
///
/// ## Test Strategy
/// Tests cover: valid post URLs, various invalid inputs (empty, non-URL, wrong domain,
/// reels, missing /p/ path), and the extractURL helper for pulling Instagram URLs
/// out of arbitrary shared text.

import Foundation
import Testing

@testable import MyFirstiOSApp

// MARK: - Valid URL Tests

struct URLValidatorValidTests {

    @Test func validPostURLWithTrailingSlash() {
        let result = URLValidator.validate("https://www.instagram.com/p/DVb33j7lVEm/")
        switch result {
        case .success(let url):
            #expect(url.absoluteString.contains("/p/DVb33j7lVEm"))
        case .failure(let error):
            Issue.record("Expected success but got error: \(error.localizedDescription)")
        }
    }

    @Test func validPostURLWithoutTrailingSlash() {
        let result = URLValidator.validate("https://instagram.com/p/ABC123")
        switch result {
        case .success(let url):
            #expect(url.absoluteString.contains("/p/ABC123"))
        case .failure(let error):
            Issue.record("Expected success but got error: \(error.localizedDescription)")
        }
    }

    @Test func validPostURLWithHTTP() {
        let result = URLValidator.validate("http://www.instagram.com/p/ABC123/")
        switch result {
        case .success(let url):
            #expect(url.absoluteString.contains("/p/ABC123"))
        case .failure(let error):
            Issue.record("Expected success but got error: \(error.localizedDescription)")
        }
    }

    @Test func validPostURLWithQueryParameters() {
        let result = URLValidator.validate("https://www.instagram.com/p/ABC123/?utm_source=ig_web")
        switch result {
        case .success(let url):
            #expect(url.absoluteString.contains("/p/ABC123"))
        case .failure(let error):
            Issue.record("Expected success but got error: \(error.localizedDescription)")
        }
    }

    @Test func validPostURLWithLeadingTrailingWhitespace() {
        let result = URLValidator.validate("  https://www.instagram.com/p/ABC123/  ")
        switch result {
        case .success(let url):
            #expect(url.absoluteString.contains("/p/ABC123"))
        case .failure(let error):
            Issue.record("Expected success but got error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Invalid URL Tests

struct URLValidatorInvalidTests {

    @Test func emptyStringReturnsEmptyInputError() {
        let result = URLValidator.validate("")
        switch result {
        case .success:
            Issue.record("Expected emptyInput error but got success")
        case .failure(let error):
            #expect(error == .emptyInput)
        }
    }

    @Test func whitespaceOnlyReturnsEmptyInputError() {
        let result = URLValidator.validate("   ")
        switch result {
        case .success:
            Issue.record("Expected emptyInput error but got success")
        case .failure(let error):
            #expect(error == .emptyInput)
        }
    }

    @Test func nonURLStringReturnsInvalidURLError() {
        let result = URLValidator.validate("not a url at all")
        switch result {
        case .success:
            Issue.record("Expected invalidURL error but got success")
        case .failure(let error):
            #expect(error == .invalidURL)
        }
    }

    @Test func nonInstagramDomainReturnsNotInstagramError() {
        let result = URLValidator.validate("https://twitter.com/post/123")
        switch result {
        case .success:
            Issue.record("Expected notInstagram error but got success")
        case .failure(let error):
            #expect(error == .notInstagram)
        }
    }

    @Test func reelURLSingularReturnsUnsupportedContentError() {
        let result = URLValidator.validate("https://www.instagram.com/reel/ABC123/")
        switch result {
        case .success:
            Issue.record("Expected unsupportedContent error but got success")
        case .failure(let error):
            if case .unsupportedContent = error {
                // Expected
            } else {
                Issue.record("Expected unsupportedContent but got \(error)")
            }
        }
    }

    @Test func reelsURLPluralReturnsUnsupportedContentError() {
        let result = URLValidator.validate("https://www.instagram.com/reels/ABC123/")
        switch result {
        case .success:
            Issue.record("Expected unsupportedContent error but got success")
        case .failure(let error):
            if case .unsupportedContent = error {
                // Expected
            } else {
                Issue.record("Expected unsupportedContent but got \(error)")
            }
        }
    }

    @Test func storiesURLReturnsUnsupportedContentError() {
        let result = URLValidator.validate("https://www.instagram.com/stories/username/123/")
        switch result {
        case .success:
            Issue.record("Expected unsupportedContent error but got success")
        case .failure(let error):
            if case .unsupportedContent = error {
                // Expected
            } else {
                Issue.record("Expected unsupportedContent but got \(error)")
            }
        }
    }

    @Test func profileURLReturnsMissingPostPathError() {
        let result = URLValidator.validate("https://www.instagram.com/username/")
        switch result {
        case .success:
            Issue.record("Expected missingPostPath error but got success")
        case .failure(let error):
            #expect(error == .missingPostPath)
        }
    }

    @Test func instagramHomepageReturnsMissingPostPathError() {
        let result = URLValidator.validate("https://www.instagram.com/")
        switch result {
        case .success:
            Issue.record("Expected missingPostPath error but got success")
        case .failure(let error):
            #expect(error == .missingPostPath)
        }
    }
}

// MARK: - extractURL Tests

struct URLValidatorExtractURLTests {

    @Test func extractsURLFromMixedText() {
        let text = "Check out this post! https://www.instagram.com/p/ABC123/ so cool"
        let extracted = URLValidator.extractURL(from: text)
        #expect(extracted != nil)
        #expect(extracted?.contains("/p/ABC123") == true)
    }

    @Test func extractsURLFromURLOnly() {
        let text = "https://www.instagram.com/p/XYZ789/"
        let extracted = URLValidator.extractURL(from: text)
        #expect(extracted != nil)
        #expect(extracted?.contains("/p/XYZ789") == true)
    }

    @Test func returnsNilWhenNoInstagramURL() {
        let text = "Check out https://twitter.com/post/123 instead"
        let extracted = URLValidator.extractURL(from: text)
        #expect(extracted == nil)
    }

    @Test func returnsNilForEmptyString() {
        let extracted = URLValidator.extractURL(from: "")
        #expect(extracted == nil)
    }

    @Test func extractsURLWithQueryParameters() {
        let text = "Link: https://www.instagram.com/p/ABC123/?utm_source=ig_web_copy_link"
        let extracted = URLValidator.extractURL(from: text)
        #expect(extracted != nil)
        #expect(extracted?.contains("/p/ABC123") == true)
    }
}

// MARK: - stripTrackingParams Tests

struct URLValidatorStripTrackingParamsTests {

    @Test func stripsIgshParam() {
        let url = URL(string: "https://www.instagram.com/p/DWW0Y-2kZaw/?igsh=someuuidparams")!
        let cleaned = URLValidator.stripTrackingParams(from: url)
        #expect(cleaned.absoluteString == "https://www.instagram.com/p/DWW0Y-2kZaw/")
    }

    @Test func stripsUtmParams() {
        let url = URL(string: "https://www.instagram.com/p/ABC123/?utm_source=ig_web&utm_medium=copy_link")!
        let cleaned = URLValidator.stripTrackingParams(from: url)
        #expect(cleaned.absoluteString == "https://www.instagram.com/p/ABC123/")
    }

    @Test func stripsMixedTrackingParams() {
        let url = URL(string: "https://www.instagram.com/p/ABC123/?igsh=abc123&utm_source=ig_web")!
        let cleaned = URLValidator.stripTrackingParams(from: url)
        #expect(cleaned.absoluteString == "https://www.instagram.com/p/ABC123/")
    }

    @Test func preservesURLWithNoParams() {
        let url = URL(string: "https://www.instagram.com/p/ABC123/")!
        let cleaned = URLValidator.stripTrackingParams(from: url)
        #expect(cleaned.absoluteString == "https://www.instagram.com/p/ABC123/")
    }

    @Test func preservesURLWithNoTrailingSlash() {
        let url = URL(string: "https://www.instagram.com/p/ABC123?igsh=xyz")!
        let cleaned = URLValidator.stripTrackingParams(from: url)
        #expect(cleaned.absoluteString == "https://www.instagram.com/p/ABC123")
    }
}
