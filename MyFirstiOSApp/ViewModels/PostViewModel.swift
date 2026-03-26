/// PostViewModel.swift
/// ===================
/// The main ViewModel that orchestrates loading an Instagram post, extracting content,
/// downloading images, running OCR, and managing the UI state.
///
/// ## MVVM Architecture
/// MVVM (Model-View-ViewModel) separates an app into three layers:
/// - **Model**: Pure data structures (`Post`, `OCRResult`) — no UI logic.
/// - **View**: SwiftUI views that display data and handle user interaction.
/// - **ViewModel**: The bridge between Model and View. It holds the app state,
///   contains business logic, and exposes data in a form the View can easily consume.
///
/// The View observes the ViewModel for changes. When the ViewModel updates its
/// published state (e.g., `isLoading` changes from `true` to `false`), SwiftUI
/// automatically re-renders any Views that depend on that state.
///
/// ## @Observable Macro (iOS 17+)
/// The `@Observable` macro (from the Observation framework) automatically makes all
/// stored properties observable. Any SwiftUI view that reads a property of an
/// `@Observable` object will re-render when that specific property changes. This is
/// more efficient than the older `ObservableObject`/`@Published` pattern, which would
/// re-render on ANY property change.
///
/// Under the hood, `@Observable` rewrites your property accessors to register
/// which views are reading which properties, enabling fine-grained updates.

import os
import SwiftUI
import Observation

private let logger = Logger(subsystem: "com.example.MyFirstiOSApp", category: "PostViewModel")

/// Represents the current phase of the extraction process.
/// Used to show appropriate loading messages to the user.
enum LoadingPhase: String {
    case loadingPage = "Loading Instagram post..."
    case extractingContent = "Extracting content from page..."
    case downloadingImages = "Downloading images..."
    case runningOCR = "Running OCR on images..."
    case complete = "Done!"
    case error = "Something went wrong"
}

/// The main ViewModel for the app. Manages the entire lifecycle of loading,
/// extracting, and processing an Instagram post.
///
/// ## How It Works
/// 1. The View creates this ViewModel and calls `startExtraction()`.
/// 2. The ViewModel sets up a hidden `InstagramWebView` (via `needsWebView`).
/// 3. When the WebView finishes loading and extracting content, it calls back
///    with an `ExtractedContent` value.
/// 4. The ViewModel downloads each image, runs OCR on it, and builds a `Post`.
/// 5. The View observes `isLoading` and `post` to know what to display.
@Observable
class PostViewModel {

    // MARK: - Published State
    // These properties are automatically observed by SwiftUI views.

    /// Whether the extraction process is currently running.
    var isLoading = true

    /// The current phase of extraction (shown in the loading UI).
    var loadingPhase: LoadingPhase = .loadingPage

    /// The fully-extracted post, populated when processing is complete.
    var post: Post?

    /// Error message if something went wrong.
    var errorMessage: String?

    /// Whether the hidden web view should be present in the view hierarchy.
    /// The View checks this to conditionally include the InstagramWebView.
    var needsWebView = false

    /// Progress for the current phase (0.0 to 1.0).
    var progress: Double = 0

    /// Per-method extraction state. Each tab in ResultsView observes its own key.
    var extractionStates: [ExtractionMethod: ExtractionState] = [:]

    // MARK: - Private State

    /// The OCR service (an actor) that handles text recognition.
    private let ocrService = OCRService()

    /// The URL we're processing.
    let targetURL: URL

    // MARK: - Initialization

    init(url: URL = AppConstants.instagramURL) {
        self.targetURL = url
    }

    // MARK: - Public Methods

    /// Kicks off the extraction pipeline.
    /// The View calls this when it appears. It triggers the web view to load.
    func startExtraction() {
        isLoading = true
        loadingPhase = .loadingPage
        needsWebView = true
        errorMessage = nil
        progress = 0
    }

    /// Called by the InstagramWebView when content extraction from the DOM is complete.
    /// This continues the pipeline: download images → run OCR → build Post.
    ///
    /// - Parameter content: The text, image URLs, and HTML source extracted by JavaScript.
    @MainActor
    func handleExtractedContent(_ content: ExtractedContent) async {
        logger.info("handleExtractedContent: received — textContent=\(content.textContent.count) chars, imageURLs=\(content.imageURLs.count), pageSource=\(content.pageSource.count) chars")

        // The web view has done its job; remove it from the view hierarchy.
        needsWebView = false

        loadingPhase = .extractingContent
        progress = 0.2

        // If no images were found, build the Post with just text.
        guard !content.imageURLs.isEmpty else {
            post = Post(
                url: targetURL,
                textContent: content.textContent,
                imageURLs: [],
                pageSource: content.pageSource,
                ocrResults: [:]
            )
            loadingPhase = .complete
            isLoading = false
            progress = 1.0

            // Still run extraction on whatever text we have.
            await launchExtractions(
                ocrResults: [:],
                pageSource: content.pageSource,
                textContent: content.textContent
            )
            return
        }

        // --- Download Images ---
        loadingPhase = .downloadingImages
        progress = 0.3

        var downloadedImages: [(URL, Data)] = []
        let totalImages = content.imageURLs.count

        for (index, imageURL) in content.imageURLs.enumerated() {
            if let imageData = await downloadImage(from: imageURL) {
                downloadedImages.append((imageURL, imageData))
            }
            // Update progress proportionally.
            progress = 0.3 + 0.3 * Double(index + 1) / Double(totalImages)
        }

        // --- Run OCR ---
        loadingPhase = .runningOCR
        progress = 0.6

        var ocrResults: [URL: OCRResult] = [:]

        for (index, (imageURL, imageData)) in downloadedImages.enumerated() {
            let result = await ocrService.recognizeText(in: imageData, from: imageURL)
            ocrResults[imageURL] = result
            progress = 0.6 + 0.3 * Double(index + 1) / Double(downloadedImages.count)
        }

        // --- Build the final Post model ---
        post = Post(
            url: targetURL,
            textContent: content.textContent,
            imageURLs: content.imageURLs,
            pageSource: content.pageSource,
            ocrResults: ocrResults
        )

        loadingPhase = .complete
        isLoading = false
        progress = 1.0

        // Launch all four extraction methods in parallel.
        await launchExtractions(
            ocrResults: ocrResults,
            pageSource: content.pageSource,
            textContent: content.textContent
        )
    }

    // MARK: - Parallel Extraction

    /// Parses HTML for alt texts and captions, then launches all extraction methods concurrently.
    ///
    /// Called after the Post model is built and `isLoading` is set to false, so ResultsView
    /// is already visible. Each extraction tab shows a spinner until its method completes.
    @MainActor
    private func launchExtractions(
        ocrResults: [URL: OCRResult],
        pageSource: String,
        textContent: String
    ) async {
        // Initialize all states to running.
        for method in ExtractionMethod.allCases {
            extractionStates[method] = .running
        }

        // Parse HTML on a background thread to get alt texts and captions.
        let (altTexts, captions) = await Task.detached {
            let alts = (try? HTMLParsingService.extractImageAltTexts(from: pageSource)) ?? []
            let caps = (try? HTMLParsingService.extractCaptions(from: pageSource)) ?? []
            return (alts, caps)
        }.value

        let ocrTexts = ocrResults.values.map { $0.recognizedText }
        let caption = captions.first ?? textContent
        let currentDate = Date()

        let inputs = ExtractionInputs(
            ocrTexts: ocrTexts,
            altTexts: altTexts,
            caption: caption,
            currentDate: currentDate
        )

        await runAllExtractions(inputs: inputs)
    }

    /// Runs all four extraction methods concurrently using a TaskGroup.
    /// Updates `extractionStates` as each method completes, allowing SwiftUI
    /// to re-render only the affected tab.
    @MainActor
    private func runAllExtractions(inputs: ExtractionInputs) async {
        await withTaskGroup(of: (ExtractionMethod, ExtractionState).self) { group in

            // A: Regex (synchronous — run on background thread)
            group.addTask {
                let results = await Task.detached {
                    RegexExtractionService.extractEvents(
                        ocrTexts: inputs.ocrTexts,
                        altTexts: inputs.altTexts,
                        caption: inputs.caption,
                        currentDate: inputs.currentDate
                    )
                }.value
                return (.regex, .completed(results))
            }

            // B: NSDataDetector (synchronous — run on background thread)
            group.addTask {
                let results = await Task.detached {
                    NSDataDetectorExtractionService.extractEvents(
                        ocrTexts: inputs.ocrTexts,
                        altTexts: inputs.altTexts,
                        caption: inputs.caption,
                        currentDate: inputs.currentDate
                    )
                }.value
                return (.nsDataDetector, .completed(results))
            }

            // C: Foundation Models (iOS 26+ only, check availability)
            group.addTask {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    guard FoundationModelsExtractionService.isModelAvailable else {
                        return (.foundationModels, .skipped("No model available"))
                    }
                    let results = await FoundationModelsExtractionService.extractEventsAsync(
                        ocrTexts: inputs.ocrTexts,
                        altTexts: inputs.altTexts,
                        caption: inputs.caption,
                        currentDate: inputs.currentDate
                    )
                    return (.foundationModels, .completed(results))
                } else {
                    return (.foundationModels, .skipped("No model available (requires iOS 26+)"))
                }
                #else
                return (.foundationModels, .skipped("No model available (requires iOS 26+)"))
                #endif
            }

            // D: Llama (synchronous — run on background thread, skip if model absent)
            group.addTask {
                guard LlamaExtractionService.isModelAvailable else {
                    return (.llama, .skipped("No model available"))
                }
                let results = await Task.detached {
                    LlamaExtractionService.extractEvents(
                        ocrTexts: inputs.ocrTexts,
                        altTexts: inputs.altTexts,
                        caption: inputs.caption,
                        currentDate: inputs.currentDate
                    )
                }.value
                return (.llama, .completed(results))
            }

            // Update states as each method finishes.
            for await (method, state) in group {
                self.extractionStates[method] = state
            }
        }
    }

    // MARK: - Private Helpers

    /// Downloads an image from the given URL using URLSession.
    ///
    /// `URLSession` is Apple's networking API. `data(from:)` is an async method
    /// that downloads the content at a URL and returns the raw bytes plus the
    /// HTTP response metadata.
    private func downloadImage(from url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Check that the server returned a successful HTTP status code (200-299).
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            return data
        } catch {
            return nil
        }
    }
}
