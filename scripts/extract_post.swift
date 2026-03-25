/// extract_post.swift
/// ==================
/// Standalone macOS script that opens an Instagram post in a visible WKWebView,
/// extracts images + OCR + alt texts + caption, and writes results to a text file.
///
/// Uses the same WebKit + Vision frameworks as the iOS app, adapted for macOS.
///
/// Build & run:
///   cd /Users/anthonyliu/Projects/my-first-ios-app
///   swiftc -framework AppKit -framework WebKit -framework Vision scripts/extract_post.swift -o scripts/extract_post
///   ./scripts/extract_post https://www.instagram.com/p/DVb33j7lVEm/
///
/// Output lands in test-data/<shortcode>.txt (e.g. test-data/DVb33j7lVEm.txt).

import AppKit
import WebKit
import Vision

// MARK: - Configuration

/// Parse the Instagram URL from the first CLI argument.
func parseArgs() -> (url: URL, shortcode: String) {
    guard CommandLine.arguments.count > 1 else {
        print("Usage: extract_post <instagram-url>")
        print("  e.g. extract_post https://www.instagram.com/p/DVb33j7lVEm/")
        exit(1)
    }
    guard let url = URL(string: CommandLine.arguments[1]) else {
        print("ERROR: Invalid URL: \(CommandLine.arguments[1])")
        exit(1)
    }
    // Extract shortcode from path like /p/DVb33j7lVEm/ or /reel/ABC123/ or /reels/XYZ/
    let validPrefixes: Set = ["p", "reel", "reels"]
    let pathParts = url.pathComponents  // ["/" , "p", "DVb33j7lVEm"]
    guard pathParts.count >= 3,
          validPrefixes.contains(pathParts[1]) else {
        print("ERROR: URL doesn't look like an Instagram post/reel: \(url.absoluteString)")
        print("  Expected format: https://www.instagram.com/p/<shortcode>/")
        exit(1)
    }
    let shortcode = pathParts[2]
    return (url, shortcode)
}

let (targetURL, shortcode) = parseArgs()
let outputDir = "test-data"
let outputFile = "\(outputDir)/\(shortcode).txt"
let pageLoadDelay: TimeInterval = 8  // seconds to wait for Instagram JS rendering

/// Mobile Safari user agent — same as AppConstants.mobileSafariUserAgent in the iOS app.
/// Instagram blocks or degrades content for non-browser clients.
let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

// MARK: - OCR via Apple Vision

/// Runs Vision OCR on raw image bytes using the same settings as OCRService.swift.
/// Uses NSImage (macOS) instead of UIImage (iOS), but the Vision pipeline is identical.
func performOCR(on imageData: Data) -> String {
    guard let image = NSImage(data: imageData),
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let cgImage = bitmap.cgImage else {
        return "[Could not decode image]"
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return "[OCR failed: \(error.localizedDescription)]"
    }

    guard let observations = request.results, !observations.isEmpty else {
        return "[No text recognized]"
    }

    return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

// MARK: - App Delegate (window setup)

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var extractor: PostExtractor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create a visible window sized like an iPhone screen
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 414, height: 896),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Extracting Instagram Post..."
        window.isReleasedWhenClosed = false

        extractor = PostExtractor(window: window)
        window.contentView = extractor.webView
        window.makeKeyAndOrderFront(nil)

        extractor.start()
    }
}

// MARK: - Post Extractor

class PostExtractor: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    var hasExtracted = false

    init(window: NSWindow) {
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: config)
        self.window = window
        super.init()
        webView.customUserAgent = userAgent
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
    }

    func start() {
        print("Loading \(targetURL.absoluteString) ...")
        webView.load(URLRequest(url: targetURL))
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasExtracted else { return }
        hasExtracted = true
        print("Page loaded. Waiting \(Int(pageLoadDelay))s for client-side JS rendering...")

        DispatchQueue.main.asyncAfter(deadline: .now() + pageLoadDelay) {
            self.extractContent()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("ERROR: Navigation failed: \(error.localizedDescription)")
        NSApp.terminate(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("ERROR: Provisional navigation failed: \(error.localizedDescription)")
        NSApp.terminate(nil)
    }

    // MARK: Extraction

    private func extractContent() {
        print("Injecting extraction JavaScript...")
        window.title = "Extracting content..."

        // JavaScript mirrors the extraction logic from InstagramWebView.swift,
        // with alt texts and captions added.
        let js = """
        (function() {
            // --- Post text from meta tag + article spans ---
            var textContent = '';
            var metaDesc = document.querySelector('meta[property="og:description"]');
            if (metaDesc) textContent = metaDesc.getAttribute('content') || '';

            var article = document.querySelector('article');
            if (article) {
                var spans = article.querySelectorAll('span');
                var articleTexts = [];
                spans.forEach(function(span) {
                    var text = span.innerText.trim();
                    if (text.length > 20 && articleTexts.indexOf(text) === -1) {
                        articleTexts.push(text);
                    }
                });
                if (articleTexts.length > 0) {
                    textContent += '\\n\\n--- Visible Text ---\\n' + articleTexts.join('\\n');
                }
            }
            if (!textContent) textContent = '[No text content found]';

            // --- Images: URLs + alt texts (same CDN/size filter as the app) ---
            var images = [];
            var imgs = document.querySelectorAll('article img, main img');
            imgs.forEach(function(img) {
                var url = '';
                // Prefer srcset — pick the largest width variant
                if (img.srcset) {
                    var candidates = img.srcset.split(',').map(function(s) {
                        var parts = s.trim().split(/\\s+/);
                        var w = parseInt((parts[1] || '0').replace('w', ''), 10);
                        return { url: parts[0], width: w };
                    });
                    candidates.sort(function(a, b) { return b.width - a.width; });
                    if (candidates.length > 0) url = candidates[0].url;
                }
                if (!url && img.src) url = img.src;

                // Filter: Instagram CDN images larger than avatars/icons
                if (url && (url.includes('cdninstagram') || url.includes('fbcdn'))
                    && img.naturalWidth > 200) {
                    var isDup = images.some(function(e) { return e.url === url; });
                    if (!isDup) {
                        images.push({ url: url, alt: img.alt || '' });
                    }
                }
            });

            // --- Captions from all <span> elements (>20 chars) ---
            var captions = [];
            document.querySelectorAll('span').forEach(function(span) {
                var text = span.innerText.trim();
                if (text.length > 20 && captions.indexOf(text) === -1) {
                    captions.push(text);
                }
            });

            return JSON.stringify({ textContent: textContent, images: images, captions: captions });
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self else { return }
            if let error {
                print("ERROR: JS extraction failed: \(error.localizedDescription)")
                NSApp.terminate(nil)
                return
            }

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("ERROR: Could not parse JS result")
                NSApp.terminate(nil)
                return
            }

            let textContent = json["textContent"] as? String ?? "[none]"
            let imageEntries = json["images"] as? [[String: String]] ?? []
            let captions = json["captions"] as? [String] ?? []

            print("Extracted: \(imageEntries.count) images, \(captions.count) caption spans")

            Task { await self.buildOutput(textContent: textContent, imageEntries: imageEntries, captions: captions) }
        }
    }

    // MARK: Download, OCR, Write

    private func buildOutput(
        textContent: String,
        imageEntries: [[String: String]],
        captions: [String]
    ) async {
        var out = ""

        out += "============================================================\n"
        out += "INSTAGRAM POST EXTRACTION\n"
        out += "============================================================\n"
        out += "URL: \(targetURL.absoluteString)\n"
        out += "Date: \(Date())\n"
        out += "\n"

        // --- Post Caption ---
        out += "============================================================\n"
        out += "POST CAPTION (og:description + article text)\n"
        out += "============================================================\n"
        out += textContent + "\n"
        out += "\n"

        // --- HTML Captions ---
        out += "============================================================\n"
        out += "CAPTIONS (from HTML <span> elements > 20 chars)\n"
        out += "============================================================\n"
        for (i, caption) in captions.enumerated() {
            out += "[\(i + 1)] \(caption)\n\n"
        }

        // --- Images: alt text + OCR ---
        out += "============================================================\n"
        out += "IMAGES — ALT TEXT & OCR\n"
        out += "============================================================\n\n"

        for (i, entry) in imageEntries.enumerated() {
            let urlString = entry["url"] ?? ""
            let altText = entry["alt"] ?? ""

            out += "------------------------------------------------------------\n"
            out += "Image \(i + 1) of \(imageEntries.count)\n"
            out += "------------------------------------------------------------\n"
            out += "URL: \(urlString)\n"
            out += "Alt text: \(altText.isEmpty ? "[none]" : altText)\n"

            if let imageURL = URL(string: urlString) {
                await MainActor.run { window.title = "Downloading image \(i + 1)/\(imageEntries.count)..." }
                print("Downloading image \(i + 1)/\(imageEntries.count)...")
                do {
                    let (data, _) = try await URLSession.shared.data(from: imageURL)
                    await MainActor.run { window.title = "OCR on image \(i + 1)/\(imageEntries.count)..." }
                    print("Running OCR on image \(i + 1)...")
                    let ocrText = performOCR(on: data)
                    out += "OCR text:\n\(ocrText)\n"
                } catch {
                    out += "OCR text: [Download failed: \(error.localizedDescription)]\n"
                }
            }
            out += "\n"
        }

        // --- Write to file ---
        let cwd = FileManager.default.currentDirectoryPath
        let dirPath = cwd + "/" + outputDir
        try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        let outputPath = cwd + "/" + outputFile
        do {
            try out.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("\nDone! Results written to \(outputPath)")
        } catch {
            print("ERROR: Failed to write output: \(error.localizedDescription)")
            // Dump to stdout as fallback
            print(out)
        }

        await MainActor.run {
            window.title = "Done!"
            // Give user a moment to see "Done" then quit
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.regular)  // Show in dock so window is fully visible/interactive
let delegate = AppDelegate()
app.delegate = delegate
app.run()
