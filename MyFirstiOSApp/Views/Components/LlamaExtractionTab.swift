/// LlamaExtractionTab.swift
/// ========================
/// Llama-specific wrapper around EventExtractionTabContent that adds a diagnostics
/// info banner showing model name, CPU/GPU mode, token counts, and timing.
///
/// This view composes EventExtractionTabContent (the shared event list) with
/// Llama-specific diagnostics in a single scroll region. It only appears for the
/// Llama tab in ResultsView.

import SwiftUI

/// Displays the Llama LLM extraction results with an inference diagnostics banner.
struct LlamaExtractionTab: View {
    let state: ExtractionState
    let diagnostics: LlamaDiagnostics?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Diagnostics banner (shown after inference completes)
                if let diag = diagnostics {
                    diagnosticsBanner(diag)
                }

                // Shared event extraction content (header, spinner/events/error)
                EventExtractionTabContent(method: .llama, state: state)
            }
            .padding(.top)
        }
    }

    /// A compact info card showing LLM inference metrics.
    @ViewBuilder
    private func diagnosticsBanner(_ diag: LlamaDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Inference Diagnostics", systemImage: "gauge.with.dots.needle.bottom.50percent")
                .font(.subheadline.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Model")
                        .foregroundStyle(.secondary)
                    Text(diag.modelName)
                        .fontDesign(.monospaced)
                }
                GridRow {
                    Text("Compute")
                        .foregroundStyle(.secondary)
                    Text(diag.usesGPU ? "GPU (\(diag.gpuLayerCount) layers)" : "CPU only")
                }
                GridRow {
                    Text("Prompt tokens")
                        .foregroundStyle(.secondary)
                    Text("\(diag.cachedSystemTokens) cached + \(diag.userTokens) new")
                }
                GridRow {
                    Text("Output tokens")
                        .foregroundStyle(.secondary)
                    Text("\(diag.generatedTokens)")
                }
                GridRow {
                    Text("Inference time")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fs", diag.inferenceDuration))
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
