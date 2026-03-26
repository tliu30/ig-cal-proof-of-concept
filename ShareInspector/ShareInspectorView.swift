/// ShareInspectorView.swift
/// ========================
/// A diagnostic SwiftUI view that displays everything received from the iOS share sheet.
///
/// ## Purpose
/// This is intentionally verbose. The goal is to discover exactly what data Instagram
/// (and other apps) send when sharing content. Once we know the format, we can build
/// proper handling in the main app.
///
/// ## How It Works
/// The view receives a `SharedData` struct containing all collected URLs, texts,
/// images, and raw NSItemProvider metadata. It displays each category in its own
/// section so you can see exactly what was shared.

import SwiftUI

/// Displays diagnostic information about shared content.
struct ShareInspectorView: View {
    let sharedData: SharedData
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // Summary
                Section("Summary") {
                    LabeledContent("URLs", value: "\(sharedData.urls.count)")
                    LabeledContent("Text items", value: "\(sharedData.texts.count)")
                    LabeledContent("Images", value: "\(sharedData.imageCount)")
                }

                // URLs
                if !sharedData.urls.isEmpty {
                    Section("URLs Received") {
                        ForEach(sharedData.urls, id: \.self) { url in
                            Text(url)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                // Text
                if !sharedData.texts.isEmpty {
                    Section("Text Received") {
                        ForEach(sharedData.texts, id: \.self) { text in
                            Text(text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                // Images
                if sharedData.imageCount > 0 {
                    Section("Images Received") {
                        Text("\(sharedData.imageCount) image(s)")
                        ForEach(Array(sharedData.imageSizes.enumerated()), id: \.offset) { index, size in
                            LabeledContent("Image \(index + 1) size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        }
                    }
                }

                // Raw metadata
                Section("Raw NSItemProvider Data") {
                    ForEach(sharedData.rawItemDescriptions, id: \.self) { desc in
                        Text(desc)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Share Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .bold()
                }
            }
        }
    }
}
