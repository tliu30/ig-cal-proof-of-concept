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
    /// Whether the Llama model uses GPU (Metal) for inference.
    @Binding var useGPU: Bool

    /// Called when the user submits a valid URL.
    let onSubmit: (URL) -> Void

    /// Called when the GPU toggle is flipped. Performs the model reload asynchronously.
    var onToggleGPU: (() async -> Void)?

    /// The raw text the user has typed or pasted.
    @State private var urlText = ""

    /// Validation error message, shown below the text field when non-nil.
    @State private var errorMessage: String?

    /// Whether the model is currently reloading after a GPU toggle.
    @State private var isReloading = false

    /// Whether the reload just finished (shows success state in modal).
    @State private var reloadComplete = false

    /// Tracks whether the text field is focused.
    @FocusState private var isTextFieldFocused: Bool

    #if targetEnvironment(simulator)
    private let isSimulator = true
    #else
    private let isSimulator = false
    #endif

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

                // GPU acceleration toggle
                VStack(spacing: 4) {
                    HStack {
                        Label("GPU Acceleration", systemImage: "bolt.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $useGPU)
                            .labelsHidden()
                            .disabled(isReloading || isSimulator)
                    }
                    if isSimulator {
                        Text("GPU not available in Simulator")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
                .onChange(of: useGPU) {
                    Task {
                        isReloading = true
                        reloadComplete = false
                        await onToggleGPU?()
                        reloadComplete = true
                    }
                }
                .sheet(isPresented: $isReloading) {
                    gpuReloadModal
                        .presentationDetents([.medium])
                        .interactiveDismissDisabled(!reloadComplete)
                }

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

    /// Modal shown while the model is reloading after a GPU toggle.
    private var gpuReloadModal: some View {
        VStack(spacing: 20) {
            Spacer()

            if reloadComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Model loaded")
                    .font(.title3.bold())
                Text(useGPU ? "GPU acceleration enabled" : "Running on CPU")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Reloading model...")
                    .font(.title3.bold())
                Text(useGPU ? "Enabling GPU acceleration" : "Switching to CPU")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if reloadComplete {
                Button("Done") {
                    isReloading = false
                    reloadComplete = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
    }
}

#Preview {
    URLInputView(useGPU: .constant(false)) { url in
        print("Submitted: \(url)")
    }
}
