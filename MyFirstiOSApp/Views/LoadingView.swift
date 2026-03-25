/// LoadingView.swift
/// =================
/// A full-screen loading view shown while the app processes the Instagram post.
///
/// ## SwiftUI Layout System
/// SwiftUI uses a declarative layout system where you compose views using modifiers.
/// The layout algorithm works top-down:
/// 1. Parent proposes a size to the child.
/// 2. Child decides its own size (possibly using the proposal).
/// 3. Parent positions the child.
///
/// Modifiers like `.frame()`, `.padding()`, and `.background()` wrap the view in
/// additional layout containers that participate in this negotiation.
///
/// ## ProgressView
/// `ProgressView` is SwiftUI's built-in progress indicator. It can show:
/// - An indeterminate spinner (no value parameter)
/// - A determinate progress bar (with `value:` from 0.0 to 1.0)
/// We use the determinate form to show extraction progress.

import SwiftUI

/// Displays a loading animation with the current processing phase and progress bar.
struct LoadingView: View {
    /// The current phase of the extraction pipeline.
    let phase: LoadingPhase

    /// Progress from 0.0 to 1.0.
    let progress: Double

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon/logo area
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: true)

            Text("Instagram Post Analyzer")
                .font(.title2.bold())

            // Progress bar with percentage
            VStack(spacing: 12) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)

                Text(phase.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut, value: phase)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    LoadingView(phase: .downloadingImages, progress: 0.45)
}
