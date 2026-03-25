# Services Directory

## Purpose
Contains pure logic layers that perform specific tasks — OCR processing and web content extraction. Services have no UI code and no knowledge of ViewModels or Views.

## Architecture Role
Services sit beneath ViewModels in the dependency graph:
```
Views → ViewModels → Services → Apple Frameworks (Vision, WebKit)
```

ViewModels call Services to do work; Services return Models. This separation means:
- Services can be reused by different ViewModels.
- Business logic is testable in isolation (if we add tests later).
- The ViewModel doesn't need to know *how* OCR or web scraping works.

## Files

### `OCRService.swift`
An `actor` that performs text recognition using Apple's Vision framework.

**How it works:**
1. Takes raw image bytes (`Data`) as input.
2. Decodes into `UIImage` → `CGImage` (Vision requires Core Graphics format).
3. Creates a `VNRecognizeTextRequest` configured for accurate English recognition.
4. Creates a `VNImageRequestHandler` and calls `perform()` — this is CPU-intensive.
5. Reads `VNRecognizedTextObservation` results, extracts top candidate strings.
6. Returns an `OCRResult` with the concatenated text and average confidence.

Because it's an `actor`, all method calls are serialized — no two images are processed simultaneously on the same service instance. Callers use `await`.

### `InstagramWebView.swift`
A `UIViewRepresentable` wrapper around `WKWebView` that loads Instagram and extracts content via JavaScript injection.

**How it works:**
1. Creates a `WKWebView` with a mobile Safari user agent (to avoid Instagram blocks).
2. Loads the target URL.
3. Waits for `didFinish` navigation callback + a delay (for client-side JS rendering).
4. Injects JavaScript that:
   - Extracts post text from meta tags and article spans.
   - Finds full-size image URLs from `srcset` attributes (picking the largest width).
   - Captures the full `outerHTML` for debugging.
5. Returns an `ExtractedContent` struct via a callback closure.

### `HTMLParsingService.swift`
A caseless `enum` namespace providing static methods for parsing Instagram page source HTML using SwiftSoup (a DOM-based HTML parser).

**How it works:**
1. **Preprocessing** — `preprocessHTML(_:)` parses HTML into a DOM tree, then removes `<head>`, `<script>`, and `<link>` elements via CSS selectors. This reduces a ~1.3 MB Instagram page dump to ~100 KB of meaningful body content.
2. **Image URL extraction** — `extractImageURLs(from:)` queries all `<img>` tags and returns their `src` attributes. HTML entities (e.g., `&amp;`) are automatically decoded.
3. **Image alt text extraction** — `extractImageAltTexts(from:)` returns the `alt` attribute from each `<img>` tag, preserving empty strings for images without alt text.
4. **Caption extraction** — `extractCaptions(from:)` finds `<span>` elements whose own text (not inherited from children) exceeds 20 characters, filtering out short UI labels.

Uses SwiftSoup (a pure-Swift port of Java's jsoup) for DOM parsing. CSS selectors operate on the DOM tree, so removing `<script>` tags never accidentally deletes text content that mentions the word "script".

## Key Concepts for Non-Swift Developers

| Concept | Explanation |
|---------|-------------|
| `actor` | A concurrency primitive that serializes access. Like a mutex-protected class, but the compiler enforces it. |
| `UIViewRepresentable` | Protocol for wrapping UIKit views in SwiftUI. Like a React wrapper around a vanilla JS library. |
| `WKWebView` | Apple's web rendering engine (Safari's engine). Like Android's `WebView` or Electron's `BrowserWindow`. |
| `WKNavigationDelegate` | Callback protocol for web view events (did start, did finish, did fail). Like event listeners on a browser. |
| `evaluateJavaScript` | Runs JS code in the web page context and returns the result. Like Chrome DevTools console. |
| `SwiftSoup` | Third-party HTML parser (port of Java's jsoup). Parses messy real-world HTML into a DOM tree with CSS selector support. |
| Caseless `enum` | An enum with no cases that acts as a pure namespace for static methods. Cannot be instantiated. |
