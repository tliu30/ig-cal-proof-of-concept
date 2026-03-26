/// ResultsView.swift
/// =================
/// Displays the extracted Instagram post content with OCR results.
///
/// ## TabView
/// A `TabView` with `.page` style creates a horizontally swipeable set of pages,
/// similar to a UIPageViewController. Each child view becomes one page. The dots
/// at the bottom indicate which page the user is on.
///
/// ## ScrollView
/// `ScrollView` creates a scrollable region. Unlike `List` (which is optimized for
/// large datasets), `ScrollView` renders all its content at once. This is fine for
/// our use case since we have a bounded amount of content (one post's worth of data).

import SwiftUI

/// Shows the extraction results in six tabs:
/// 1. Post content with OCR results
/// 2. HTML parsing output (preprocessed HTML, captions, image URLs, alt texts)
/// 3–6. Event extraction results from each method (Regex, NSDataDetector, Foundation Models, Llama)
struct ResultsView: View {
    /// The fully-processed post data.
    let post: Post

    /// The original URL, shown as a tappable link.
    let targetURL: URL

    /// Per-method extraction state, passed from the ViewModel.
    let extractionStates: [ExtractionMethod: ExtractionState]

    /// Diagnostic info from the most recent Llama inference, if available.
    let llamaDiagnostics: LlamaDiagnostics?

    /// Called when the user wants to analyze a different URL.
    var onNewURL: (() -> Void)?

    /// Which tab is currently selected.
    @State private var selectedTab = 0

    /// Parsed results from HTMLParsingService, computed asynchronously from pageSource.
    @State private var parsedCaptions: [String] = []
    @State private var parsedImageURLs: [String] = []
    @State private var parsedAltTexts: [String] = []
    @State private var preprocessedHTML: String = ""
    @State private var hasParsed = false

    /// Navigation title based on the selected tab.
    private var tabTitle: String {
        switch selectedTab {
        case 0: return "Results"
        case 1: return "Parsed HTML"
        case 2: return ExtractionMethod.regex.tabLabel
        case 3: return ExtractionMethod.nsDataDetector.tabLabel
        case 4: return ExtractionMethod.foundationModels.tabLabel
        case 5: return ExtractionMethod.llama.tabLabel
        default: return "Results"
        }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                resultsTab
                    .tag(0)

                parsedHTMLTab
                    .tag(1)

                EventExtractionTab(
                    method: .regex,
                    state: extractionStates[.regex] ?? .idle
                ).tag(2)

                EventExtractionTab(
                    method: .nsDataDetector,
                    state: extractionStates[.nsDataDetector] ?? .idle
                ).tag(3)

                EventExtractionTab(
                    method: .foundationModels,
                    state: extractionStates[.foundationModels] ?? .idle
                ).tag(4)

                LlamaExtractionTab(
                    state: extractionStates[.llama] ?? .idle,
                    diagnostics: llamaDiagnostics
                ).tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle(tabTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onNewURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onNewURL()
                        } label: {
                            Label("New URL", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
        }
        .task {
            guard !hasParsed else { return }
            await parsePageSource()
        }
    }

    // MARK: - Tab 1: Results (existing content)

    private var resultsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // --- Link to original post ---
                Link(destination: targetURL) {
                    HStack {
                        Image(systemName: "link")
                        Text("View Original Post")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                // --- Post Text ---
                VStack(alignment: .leading, spacing: 8) {
                    Label("Post Text", systemImage: "text.quote")
                        .font(.headline)
                    Text(post.textContent)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)

                // --- Divider ---
                Divider()
                    .padding(.horizontal)

                // --- Images with OCR ---
                if post.ocrResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No images found on the page")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Images & OCR Results", systemImage: "eye.circle")
                            .font(.headline)
                            .padding(.horizontal)

                        Text("\(post.ocrResults.count) image(s) processed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    ForEach(Array(post.ocrResults.values)) { result in
                        ImageOCRCard(result: result)
                    }
                }
            }
            .padding(.top)
        }
    }

    // MARK: - Tab 2: Parsed HTML output

    private var parsedHTMLTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !hasParsed {
                    ProgressView("Parsing HTML...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // --- Captions ---
                    parsedSection(
                        title: "Captions",
                        icon: "text.bubble",
                        items: parsedCaptions,
                        emptyMessage: "No captions found"
                    )

                    Divider().padding(.horizontal)

                    // --- Image URLs ---
                    parsedSection(
                        title: "Image URLs",
                        icon: "photo",
                        items: parsedImageURLs,
                        emptyMessage: "No image URLs found"
                    )

                    Divider().padding(.horizontal)

                    // --- Alt Texts ---
                    parsedSection(
                        title: "Image Alt Text",
                        icon: "text.below.photo",
                        items: parsedAltTexts.enumerated().map { i, alt in
                            alt.isEmpty ? "[\(i + 1)] (empty)" : "[\(i + 1)] \(alt)"
                        },
                        emptyMessage: "No alt text found"
                    )

                    Divider().padding(.horizontal)

                    // --- Preprocessed HTML size ---
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Preprocessed HTML", systemImage: "doc.text")
                            .font(.headline)

                        let origKB = post.pageSource.utf8.count / 1024
                        let cleanKB = preprocessedHTML.utf8.count / 1024
                        Text("Original: \(origKB) KB  |  Cleaned: \(cleanKB) KB")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(String(preprocessedHTML.prefix(2000)))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        if preprocessedHTML.count > 2000 {
                            Text("(\(preprocessedHTML.count - 2000) more characters...)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
    }

    // MARK: - Helpers

    /// Reusable section showing a titled list of text items.
    private func parsedSection(title: String, icon: String, items: [String], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)

            Text("\(items.count) item(s)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.horizontal)
    }

    /// Runs HTMLParsingService on the page source off the main thread.
    private func parsePageSource() async {
        let source = post.pageSource
        let results: (String, [String], [String], [String])? = await Task.detached {
            do {
                let cleaned = try HTMLParsingService.preprocessHTML(source)
                let urls = try HTMLParsingService.extractImageURLs(from: source)
                let alts = try HTMLParsingService.extractImageAltTexts(from: source)
                let caps = try HTMLParsingService.extractCaptions(from: source)
                return (cleaned, urls, alts, caps)
            } catch {
                return nil
            }
        }.value

        if let (cleaned, urls, alts, caps) = results {
            preprocessedHTML = cleaned
            parsedImageURLs = urls
            parsedAltTexts = alts
            parsedCaptions = caps
        }
        hasParsed = true
    }
}
