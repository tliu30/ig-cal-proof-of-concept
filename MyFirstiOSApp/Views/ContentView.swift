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

/// The root view that switches between loading and results screens.
struct ContentView: View {
    /// The ViewModel that manages all app state and business logic.
    /// `@State` means this view owns the ViewModel — it's created once when the view
    /// first appears and persists across re-renders.
    @State private var viewModel = PostViewModel()

    var body: some View {
        ZStack {
            // Show the loading view while processing, results view when done.
            if viewModel.isLoading {
                LoadingView(
                    phase: viewModel.loadingPhase,
                    progress: viewModel.progress
                )
            } else if let post = viewModel.post {
                ResultsView(post: post, targetURL: viewModel.targetURL)
            } else if let error = viewModel.errorMessage {
                // Error state with retry button.
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
                    Button("Try Again") {
                        viewModel.startExtraction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // The hidden web view that loads Instagram and extracts content.
            // It's placed in the ZStack but has zero size — it works off-screen.
            // We only include it when the ViewModel says it's needed.
            if viewModel.needsWebView {
                InstagramWebView(url: viewModel.targetURL) { content in
                    Task { @MainActor in
                        await viewModel.handleExtractedContent(content)
                    }
                }
                .frame(width: 0, height: 0)
            }
        }
        .onAppear {
            // Start the extraction pipeline when the view first appears.
            viewModel.startExtraction()
        }
    }
}

#Preview {
    ContentView()
}
