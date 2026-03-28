/// InstagramWebView.swift
/// ======================
/// A hidden WKWebView that loads an Instagram post and extracts content via JavaScript.
///
/// ## How WKWebView Works
/// `WKWebView` is Apple's modern web rendering engine (the same engine behind Safari).
/// It runs web content in a separate process for security and stability. You interact
/// with it by:
/// - Loading URLs or HTML strings
/// - Injecting JavaScript via `evaluateJavaScript(_:)` or `WKUserScript`
/// - Receiving callbacks through delegate protocols (`WKNavigationDelegate`, etc.)
///
/// ## Why a UIViewRepresentable Wrapper?
/// SwiftUI doesn't have a native WebView component. `UIViewRepresentable` is a protocol
/// that lets you wrap any UIKit view (like `WKWebView`) for use in SwiftUI. It requires:
/// - `makeUIView()`: Create and configure the UIKit view.
/// - `updateUIView()`: Called when SwiftUI state changes; update the UIKit view if needed.
/// - A `Coordinator` class: Acts as the delegate for UIKit callbacks (since SwiftUI views
///   are structs and can't conform to delegate protocols).
///
/// ## Content Extraction Strategy
/// Instagram is a Single Page Application (SPA) — the initial HTML is mostly empty, and
/// JavaScript fills in the actual content. Our approach:
/// 1. Load the post URL with a mobile Safari user agent.
/// 2. Wait for `WKNavigationDelegate.didFinish` (initial load complete).
/// 3. Wait an additional delay for client-side JS to render.
/// 4. Inject JavaScript to extract text and image URLs from the rendered DOM.
/// 5. Also grab the full `document.documentElement.outerHTML` for the debug view.

import os
import SwiftUI
import WebKit

/// Logger for the web extraction pipeline. View logs in Xcode console or via:
/// `log stream --predicate 'subsystem == "com.example.MyFirstiOSApp"'`
private let logger = Logger(subsystem: "com.example.MyFirstiOSApp", category: "WebExtraction")

/// Represents the content extracted from an Instagram page via JavaScript.
struct ExtractedContent {
    /// The post's text content (caption, etc.).
    let textContent: String
    /// Full-size image URLs found on the page.
    let imageURLs: [URL]
    /// Alt text attributes for each image in ``imageURLs``, in the same order.
    /// Extracted alongside image URLs using the same filter criteria (CDN, width,
    /// no profile pictures), so alt texts are always aligned with their images.
    let imageAlts: [String]
    /// The complete HTML source of the rendered page.
    let pageSource: String
}

/// A SwiftUI-compatible wrapper around WKWebView that loads an Instagram post
/// and extracts its content.
///
/// This view is designed to be hidden (zero-sized) — it does its work off-screen
/// and communicates results back through an async continuation.
struct InstagramWebView: UIViewRepresentable {

    /// The Instagram post URL to load.
    let url: URL

    /// Called when content extraction is complete.
    /// This closure bridges the UIKit delegate world back to Swift async/await.
    let onContentExtracted: (ExtractedContent) -> Void

    // MARK: - UIViewRepresentable

    /// Creates and configures the WKWebView.
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Allow inline media playback (Instagram videos).
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)

        // Set mobile Safari user agent to prevent Instagram from blocking us.
        webView.customUserAgent = AppConstants.mobileSafariUserAgent

        // The Coordinator acts as the navigation delegate, receiving callbacks
        // when pages start/finish loading, encounter errors, etc.
        webView.navigationDelegate = context.coordinator

        // Start loading the Instagram post.
        webView.load(URLRequest(url: url))

        return webView
    }

    /// Called when SwiftUI state changes. We don't need to update anything.
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Creates the Coordinator that handles WKWebView delegate callbacks.
    func makeCoordinator() -> Coordinator {
        Coordinator(onContentExtracted: onContentExtracted)
    }

    // MARK: - Coordinator

    /// The Coordinator bridges UIKit's delegate pattern to our SwiftUI/async world.
    ///
    /// In UIKit, delegates are objects that receive callbacks about events. SwiftUI views
    /// are value types (structs) and can't be delegates, so we use a Coordinator (a class)
    /// that SwiftUI manages for us. The Coordinator's lifetime matches the view's.
    class Coordinator: NSObject, WKNavigationDelegate {
        let onContentExtracted: (ExtractedContent) -> Void
        private var hasExtracted = false

        init(onContentExtracted: @escaping (ExtractedContent) -> Void) {
            self.onContentExtracted = onContentExtracted
        }

        /// Called when the web view finishes loading a page.
        ///
        /// IMPORTANT: "Finished loading" in WKWebView means the initial HTML and its
        /// direct resources are loaded. For SPAs like Instagram, the meaningful content
        /// is rendered asynchronously by JavaScript AFTER this point. That's why we wait
        /// an additional delay before extracting.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasExtracted else { return }
            hasExtracted = true
            logger.info("didFinish: page load complete, waiting \(AppConstants.pageLoadDelay / 1_000_000_000)s for JS rendering")

            // Wait for Instagram's JS to render, then extract content.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: AppConstants.pageLoadDelay)
                await self.extractContent(from: webView)
            }
        }

        /// Injects JavaScript into the page to extract text, images, and HTML source.
        @MainActor
        private func extractContent(from webView: WKWebView) async {
            logger.info("extractContent: starting JavaScript extraction")
            // This JavaScript does three things:
            // 1. Finds the post text content (Instagram puts it in article > spans, or
            //    meta tags as fallback).
            // 2. Finds all full-size image URLs (from <img> tags with srcset, or src).
            // 3. Captures the full page HTML for debugging.
            //
            // The script returns a JSON object with these three fields.
            let extractionJS = """
            (function() {
                // --- Extract post text ---
                // Try to get text from the main article content area.
                // Instagram wraps post captions in <h1> or specific span elements
                // within the article tag.
                var textContent = '';

                // Strategy 1: Look for the meta description (most reliable for caption)
                var metaDesc = document.querySelector('meta[property="og:description"]');
                if (metaDesc) {
                    textContent = metaDesc.getAttribute('content') || '';
                }

                // Strategy 2: Also grab visible text from the article
                var article = document.querySelector('article');
                if (article) {
                    // Get all text spans that likely contain caption/comments
                    var spans = article.querySelectorAll('span');
                    var articleTexts = [];
                    spans.forEach(function(span) {
                        var text = span.innerText.trim();
                        // Filter out very short strings (icons, UI elements) and duplicates
                        if (text.length > 20 && articleTexts.indexOf(text) === -1) {
                            articleTexts.push(text);
                        }
                    });
                    if (articleTexts.length > 0) {
                        textContent = textContent + '\\n\\n--- Visible Text ---\\n' + articleTexts.join('\\n');
                    }
                }

                if (!textContent) {
                    textContent = '[No text content found on page]';
                }

                // --- Extract image URLs and alt texts ---
                // Instagram serves images at multiple resolutions via srcset.
                // We want the largest version. srcset format: "url1 widthW, url2 widthW, ..."
                // Alt texts are collected in parallel so they stay aligned with image URLs.
                var imageURLs = [];
                var imageAlts = [];
                var imgs = document.querySelectorAll('article img, main img');
                imgs.forEach(function(img) {
                    var url = '';

                    // Prefer srcset — pick the URL with the largest width descriptor
                    if (img.srcset) {
                        var candidates = img.srcset.split(',').map(function(s) {
                            var parts = s.trim().split(/\\s+/);
                            var w = parseInt((parts[1] || '0').replace('w', ''), 10);
                            return { url: parts[0], width: w };
                        });
                        candidates.sort(function(a, b) { return b.width - a.width; });
                        if (candidates.length > 0) {
                            url = candidates[0].url;
                        }
                    }

                    // Fallback to src
                    if (!url && img.src) {
                        url = img.src;
                    }

                    // Filter: only include Instagram CDN images, skip UI icons/avatars
                    // and profile pictures. Instagram CDN images are served from
                    // scontent*.cdninstagram.com or scontent*.xx.fbcdn.net. We filter
                    // by natural size to skip tiny icons and by alt text to skip
                    // profile pictures.
                    if (url && (url.includes('cdninstagram') || url.includes('fbcdn'))
                        && img.naturalWidth > 200
                        && !(img.alt && img.alt.toLowerCase().includes('profile picture'))) {
                        if (imageURLs.indexOf(url) === -1) {
                            imageURLs.push(url);
                            imageAlts.push(img.alt || '');
                        }
                    }
                });

                return JSON.stringify({
                    textContent: textContent,
                    imageURLs: imageURLs,
                    imageAlts: imageAlts
                });
            })();
            """

            do {
                // evaluateJavaScript runs the script in the web page's context and returns
                // the result. The return value is bridged from JavaScript types to Swift types.
                guard let resultString = try await webView.evaluateJavaScript(extractionJS) as? String,
                      let data = resultString.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    logger.error("extractContent: failed to parse main extraction JSON")
                    onContentExtracted(ExtractedContent(
                        textContent: "[Failed to parse extraction results]",
                        imageURLs: [],
                        imageAlts: [],
                        pageSource: ""
                    ))
                    return
                }

                let textContent = json["textContent"] as? String ?? ""
                let imageURLStrings = json["imageURLs"] as? [String] ?? []
                let imageAlts = json["imageAlts"] as? [String] ?? []

                let imageURLs = imageURLStrings.compactMap { URL(string: $0) }
                logger.info("extractContent: main extraction OK — textContent=\(textContent.count) chars, imageURLs=\(imageURLs.count), imageAlts=\(imageAlts.count)")

                // Extract page source in a separate call to avoid size limits.
                // Instagram pages can produce multi-MB outerHTML that exceeds
                // evaluateJavaScript's return size when bundled into a JSON string.
                let pageSourceJS = "document.documentElement.outerHTML"
                let pageSource: String
                do {
                    let rawResult = try await webView.evaluateJavaScript(pageSourceJS)
                    logger.info("extractContent: pageSource JS returned type=\(type(of: rawResult))")
                    if let source = rawResult as? String {
                        logger.info("extractContent: pageSource string length=\(source.count)")
                        pageSource = source.isEmpty ? "" : source
                    } else {
                        logger.error("extractContent: pageSource was not a String, got \(String(describing: rawResult))")
                        pageSource = ""
                    }
                } catch {
                    logger.error("extractContent: pageSource JS threw error: \(error.localizedDescription)")
                    pageSource = ""
                }

                // Dismiss any Instagram login modals that may have appeared.
                let dismissJS = """
                (function() {
                    // Instagram shows a login modal after a few seconds.
                    // Try to find and remove common overlay/modal elements.
                    var overlays = document.querySelectorAll('[role="dialog"], [role="presentation"]');
                    overlays.forEach(function(el) { el.remove(); });

                    // Also try to remove the fixed overlay backdrop
                    var backdrops = document.querySelectorAll('div[style*="position: fixed"]');
                    backdrops.forEach(function(el) {
                        if (el.style.zIndex > 0) el.remove();
                    });
                })();
                """
                _ = try? await webView.evaluateJavaScript(dismissJS)

                logger.info("extractContent: delivering content — pageSource=\(pageSource.count) chars")
                onContentExtracted(ExtractedContent(
                    textContent: textContent,
                    imageURLs: imageURLs,
                    imageAlts: imageAlts,
                    pageSource: pageSource
                ))
            } catch {
                logger.error("extractContent: main extraction JS threw: \(error.localizedDescription)")
                onContentExtracted(ExtractedContent(
                    textContent: "[JavaScript extraction error: \(error.localizedDescription)]",
                    imageURLs: [],
                    imageAlts: [],
                    pageSource: ""
                ))
            }
        }

        /// Called when navigation fails. Log the error and report empty content.
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !hasExtracted else { return }
            hasExtracted = true
            logger.error("didFail: navigation error: \(error.localizedDescription)")
            onContentExtracted(ExtractedContent(
                textContent: "[Page load failed: \(error.localizedDescription)]",
                imageURLs: [],
                imageAlts: [],
                pageSource: ""
            ))
        }

        /// Called when navigation fails during the provisional (early) stage.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !hasExtracted else { return }
            hasExtracted = true
            logger.error("didFailProvisionalNavigation: \(error.localizedDescription)")
            onContentExtracted(ExtractedContent(
                textContent: "[Page load failed: \(error.localizedDescription)]",
                imageURLs: [],
                imageAlts: [],
                pageSource: ""
            ))
        }
    }
}
