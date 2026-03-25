/// ResultsView.swift
/// =================
/// Displays the extracted Instagram post content with OCR results.
///
/// ## ScrollView
/// `ScrollView` creates a scrollable region. Unlike `List` (which is optimized for
/// large datasets), `ScrollView` renders all its content at once. This is fine for
/// our use case since we have a bounded amount of content (one post's worth of data).

import SwiftUI

/// Shows the extraction results: post text, images with OCR text, and a link to the original.
struct ResultsView: View {
    /// The fully-processed post data.
    let post: Post

    /// The original URL, shown as a tappable link.
    let targetURL: URL

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
