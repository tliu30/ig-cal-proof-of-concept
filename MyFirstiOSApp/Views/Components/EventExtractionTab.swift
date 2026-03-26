/// EventExtractionTab.swift
/// =======================
/// Reusable tab view that displays the results from one event extraction method.
///
/// ## States
/// Each extraction method runs independently. This view handles all possible states:
/// - **Running**: Shows a spinner while the algorithm processes text.
/// - **Completed**: Lists extracted events as cards, or "No events" if empty.
/// - **Skipped**: Explains why the method was skipped (e.g., model unavailable).
/// - **Failed**: Shows the error message.
///
/// ## EventCard
/// A simple card showing one extracted event's description and time range.

import SwiftUI

/// Displays one extraction method's results in a scrollable tab.
struct EventExtractionTab: View {
    let method: ExtractionMethod
    let state: ExtractionState

    var body: some View {
        ScrollView {
            EventExtractionTabContent(method: method, state: state)
                .padding(.top)
        }
    }
}

/// The inner content of an extraction tab, without a ScrollView wrapper.
/// Used by LlamaExtractionTab to compose with diagnostics in a single scroll region.
struct EventExtractionTabContent: View {
    let method: ExtractionMethod
    let state: ExtractionState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with method name and icon
            Label(method.tabLabel, systemImage: method.icon)
                .font(.headline)
                .padding(.horizontal)

            switch state {
            case .idle, .running:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Running \(method.tabLabel)...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)

            case .completed(let events):
                if events.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.minus")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No events extracted")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Text("\(events.count) event(s) found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    ForEach(events) { event in
                        EventCard(event: event)
                    }
                }

            case .failed(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.horizontal)

            case .skipped(let reason):
                VStack(spacing: 8) {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text("Skipped")
                        .font(.subheadline.bold())
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.horizontal)
            }
        }
    }
}

/// A card displaying a single extracted event's description and time range.
struct EventCard: View {
    let event: ExtractedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.description)
                .font(.body.bold())
                .textSelection(.enabled)

            HStack {
                Image(systemName: "clock")
                Text(event.datetimeStart)
                if let end = event.datetimeEnd {
                    Text("–")
                    Text(end)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
