/// URLInputView.swift
/// ==================
/// A form where the user pastes or types an Instagram post URL.
///
/// ## Design
/// This view owns its own local state (text field value, validation error) and
/// communicates the validated URL back to its parent via an `onSubmit` closure.
/// It has no dependency on `PostViewModel` — it only deals with URL input and
/// validation, keeping the concerns cleanly separated.
///
/// ## UIPasteboard
/// `UIPasteboard.general` is the system-wide clipboard on iOS. Reading from it
/// triggers a system permission banner the first time (iOS 16+). We use it for
/// the "Paste" button so users can quickly paste a link copied from Instagram.

import SwiftUI
import UIKit

/// A form for entering an Instagram post URL.
struct URLInputView: View {
    /// Called when the user submits a valid URL.
    let onSubmit: (URL) -> Void

    /// The raw text the user has typed or pasted.
    @State private var urlText = ""

    /// Validation error message, shown below the text field when non-nil.
    @State private var errorMessage: String?

    /// Tracks whether the text field is focused.
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // App icon and title
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Instagram Post Analyzer")
                        .font(.title2.bold())
                    Text("Paste an Instagram post URL to extract text, images, and events.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // URL input area
                VStack(spacing: 12) {
                    HStack {
                        TextField("https://www.instagram.com/p/...", text: $urlText)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isTextFieldFocused)
                            .onSubmit(validateAndSubmit)

                        // Paste from clipboard button
                        Button {
                            if let clipboard = UIPasteboard.general.string {
                                urlText = clipboard
                                errorMessage = nil
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Paste from clipboard")
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Validation error
                    if let errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal)

                // Submit button
                Button(action: validateAndSubmit) {
                    Label("Analyze Post", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
                Spacer()
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Validates the URL text and calls `onSubmit` if valid.
    private func validateAndSubmit() {
        let result = URLValidator.validate(urlText)
        switch result {
        case .success(let url):
            errorMessage = nil
            onSubmit(url)
        case .failure(let error):
            errorMessage = error.errorDescription
        }
    }
}

#Preview {
    URLInputView { url in
        print("Submitted: \(url)")
    }
}
