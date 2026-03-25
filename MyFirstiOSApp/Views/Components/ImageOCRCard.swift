/// ImageOCRCard.swift
/// ==================
/// A reusable card component that displays an image alongside its OCR-extracted text.
///
/// ## SwiftUI Components
/// In SwiftUI, there's no formal "component" concept — any `View` struct can be
/// used as a reusable building block. By extracting this card into its own file,
/// we keep `ResultsView` focused on layout and navigation while this handles the
/// presentation of a single image+OCR pair.
///
/// ## UIImage from Data
/// When we download an image from the network, we get raw bytes (`Data`).
/// `UIImage(data:)` decodes those bytes (JPEG, PNG, etc.) into an in-memory image.
/// SwiftUI's `Image` view doesn't directly accept `Data`, so we bridge through
/// `UIImage` using `Image(uiImage:)`.

import SwiftUI

/// A card view showing a downloaded image and the text OCR found in it.
struct ImageOCRCard: View {
    /// The OCR result containing image data and recognized text.
    let result: OCRResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // --- Image ---
            if let uiImage = UIImage(data: result.imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Fallback if image data couldn't be decoded.
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(height: 200)
                    .overlay {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }

            // --- OCR Confidence Badge ---
            HStack {
                Image(systemName: confidenceIcon)
                    .foregroundStyle(confidenceColor)
                Text("OCR Confidence: \(Int(result.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // --- Recognized Text ---
            if result.recognizedText.isEmpty {
                Text("No text detected in this image")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recognized Text:")
                        .font(.subheadline.bold())
                    Text(result.recognizedText)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Helpers

    /// SF Symbol name based on OCR confidence level.
    private var confidenceIcon: String {
        switch result.confidence {
        case 0.8...: return "checkmark.circle.fill"
        case 0.5...: return "exclamationmark.circle.fill"
        default: return "xmark.circle.fill"
        }
    }

    /// Color based on OCR confidence level.
    private var confidenceColor: Color {
        switch result.confidence {
        case 0.8...: return .green
        case 0.5...: return .orange
        default: return .red
        }
    }
}
