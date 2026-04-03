/// ContentView.swift
/// =================
/// The root view of the application. It decides whether to show the loading screen
/// or the results screen based on the ViewModel's state.
///
/// ## How SwiftUI Views Work
/// In SwiftUI, views are lightweight structs that describe what the UI *should* look like.
/// They're not the actual UI objects on screen — SwiftUI takes your view descriptions and
/// efficiently creates/updates the real UI elements behind the scenes.
///
/// Every SwiftUI view has a `body` property that returns other views. This creates a tree
/// of views (called the "view hierarchy") that SwiftUI renders. When state changes, SwiftUI
/// re-evaluates `body` and updates only the parts of the screen that changed.
///
/// ## @State and View Ownership
/// `@State` is a property wrapper that tells SwiftUI "this view owns this data."
/// When a `@State` property changes, SwiftUI re-renders the view. Here, we use
/// `@State` to hold the ViewModel because the ViewModel's lifetime should match
/// the view's lifetime — when ContentView is created, so is the ViewModel.

import SwiftUI

/// The root view that switches between URL input, loading, and results screens.
///
/// ## Navigation Flow
/// The app starts on `URLInputView` (when `viewModel` is nil). When the user submits
/// a valid URL, a new `PostViewModel` is created and extraction begins. After viewing
/// results, the user can tap "New URL" to return to the input screen, which sets
/// `viewModel` back to nil and discards the old ViewModel.
struct ContentView: View {
    /// The ViewModel that manages extraction state and business logic.
    /// `nil` means the app is in the URL input state — no extraction is in progress.
    /// A new ViewModel is created each time the user submits a URL, ensuring a clean
    /// state for each extraction run.
    @State private var viewModel: PostViewModel?

    /// A URL received from the share extension via App Groups.
    /// When set, the app automatically starts extraction for this URL.
    @Binding var pendingURL: URL?

    /// Whether the Llama model should use GPU (Metal) for inference.
    /// Lives here (not in PostViewModel) because it outlives any single extraction run.
    @State private var llamaUseGPU = UserDefaults.standard.bool(forKey: "llamaUseGPU")

    var body: some View {
        Group {
        if let viewModel {
            ZStack {
                if viewModel.isLoading {
                    // Show the live web view while loading so the user can see the
                    // page rendering. A status overlay sits on top.
                    if viewModel.needsWebView {
                        InstagramWebView(url: viewModel.targetURL) { content in
                            Task { @MainActor in
                                await viewModel.handleExtractedContent(content)
                            }
                        }
                        .ignoresSafeArea()

                        // Semi-transparent status bar at the bottom
                        VStack {
                            Spacer()
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(viewModel.loadingPhase.rawValue)
                                    .font(.subheadline.bold())
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                        }
                    } else {
                        // Post-webview processing (downloading images, running OCR)
                        LoadingView(
                            phase: viewModel.loadingPhase,
                            progress: viewModel.progress
                        )
                    }
                } else if let post = viewModel.post {
                    ResultsView(
                        post: post,
                        targetURL: viewModel.targetURL,
                        extractionStates: viewModel.extractionStates,
                        llamaDiagnostics: viewModel.llamaDiagnostics,
                        extractionInputs: viewModel.extractionInputs,
                        onNewURL: { self.viewModel = nil }
                    )
                } else if let error = viewModel.errorMessage {
                    // Error state with retry and new URL buttons.
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Error")
                            .font(.title2.bold())
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        HStack(spacing: 12) {
                            Button("Try Again") {
                                viewModel.startExtraction()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("New URL") {
                                self.viewModel = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        } else {
            URLInputView(useGPU: $llamaUseGPU) { url in
                startExtraction(for: url)
            } onToggleGPU: {
                let enabled = llamaUseGPU
                UserDefaults.standard.set(enabled, forKey: "llamaUseGPU")
                await Task.detached {
                    LlamaExtractionService.setGPUEnabled(enabled)
                }.value
            }
        }
        }
        .onChange(of: pendingURL) { _, newURL in
            if let url = newURL {
                startExtraction(for: url)
            }
        }
    }

    /// Creates a new ViewModel for the given URL and starts extraction.
    private func startExtraction(for url: URL) {
        let vm = PostViewModel(url: url)
        self.viewModel = vm
        self.pendingURL = nil
        vm.startExtraction()
    }
}

#Preview {
    ContentView(pendingURL: .constant(nil))
}
