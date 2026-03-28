// TrainingDataTab.swift
// ====================
// A tab for creating and saving corrected training examples.
//
// ## Purpose
// After the app extracts events from an Instagram post using four algorithms, this tab
// lets the user manually create the "correct" set of events. They can prefill from any
// algorithm's results (or start blank), then edit fields to produce ground-truth data.
//
// ## Prefill Sheet
// Tapping "Add Event" opens a sheet with a grouped list. Each section corresponds to one
// extraction method (Regex, NSDataDetector, etc.) and shows its extracted events. The user
// can tap any event to prefill the new training event's fields, or choose "Blank" to start
// from scratch.
//
// ## Validation
// Datetime fields are validated on save (not per-keystroke). Invalid fields show a red
// error message below the text field. The format must be "YYYY-MM-DD HH:mm", and
// `datetimeEnd` may also be empty.
//
// ## Export
// "Export All" uses SwiftUI's `.fileExporter` to save all training examples (across all
// posts, not just the current one) as a JSON file to the user's chosen location in Files.

import SwiftUI
import UniformTypeIdentifiers

/// Displays the training data editor as a swipeable tab page.
struct TrainingDataTab: View {
    /// The Instagram post URL, used to prefill the URL field.
    let targetURL: URL

    /// Per-method extraction results, used to populate the prefill picker.
    let extractionStates: [ExtractionMethod: ExtractionState]

    /// The shared training data store, injected via environment.
    @Environment(TrainingDataStore.self) private var store

    /// The URL string, editable by the user.
    @State private var url: String = ""

    /// The list of events being edited (not yet saved).
    @State private var events: [TrainingEvent] = []

    /// Per-event validation errors, keyed by event ID.
    @State private var validationErrors: [UUID: [String]] = [:]

    /// Controls whether the prefill picker sheet is shown.
    @State private var showingPrefillSheet = false

    /// Controls whether the file exporter is shown.
    @State private var showingExporter = false

    /// Temporary confirmation message shown after saving.
    @State private var showingSaveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // --- URL ---
                urlSection

                Divider().padding(.horizontal)

                // --- Events ---
                eventsSection

                // --- Add Event ---
                addEventButton

                Divider().padding(.horizontal)

                // --- Actions ---
                actionsSection
            }
            .padding(.top)
        }
        .onAppear {
            if url.isEmpty {
                url = targetURL.absoluteString
            }
        }
        .sheet(isPresented: $showingPrefillSheet) {
            PrefillPickerSheet(
                extractionStates: extractionStates,
                onSelect: addEvent
            )
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: TrainingDataDocument(data: store.exportAllAsJSON()),
            contentType: .json,
            defaultFilename: "training_data.json"
        ) { _ in }
    }

    // MARK: - URL Section

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("URL", systemImage: "link")
                .font(.headline)

            TextField("Instagram post URL", text: $url)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
        .padding(.horizontal)
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Events (\(events.count))", systemImage: "calendar")
                .font(.headline)
                .padding(.horizontal)

            if events.isEmpty {
                Text("No events yet — tap \"Add Event\" to start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach($events) { $event in
                    editableEventCard(event: $event)
                }
            }
        }
    }

    /// A card for editing one training event, with delete and validation errors.
    private func editableEventCard(event: Binding<TrainingEvent>) -> some View {
        let errors = validationErrors[event.wrappedValue.id] ?? []

        return VStack(alignment: .leading, spacing: 8) {
            // Header with delete button
            HStack {
                Text("Event")
                    .font(.subheadline.bold())
                Spacer()
                Button(role: .destructive) {
                    withAnimation {
                        events.removeAll { $0.id == event.wrappedValue.id }
                        validationErrors.removeValue(forKey: event.wrappedValue.id)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                }
            }

            // Start datetime
            VStack(alignment: .leading, spacing: 4) {
                Text("Start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("YYYY-MM-DD HH:mm", text: event.datetimeStart)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
            }

            // End datetime
            VStack(alignment: .leading, spacing: 4) {
                Text("End (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("YYYY-MM-DD HH:mm", text: event.datetimeEnd)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
            }

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Event description", text: event.description)
                    .textFieldStyle(.roundedBorder)
            }

            // Validation errors
            if !errors.isEmpty {
                ForEach(errors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Add Event Button

    private var addEventButton: some View {
        Button {
            showingPrefillSheet = true
        } label: {
            Label("Add Event", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Save button
            Button {
                saveExample()
            } label: {
                Label("Save Training Example", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal)

            if showingSaveConfirmation {
                Label("Saved!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .padding(.horizontal)
            }

            // Export button
            Button {
                showingExporter = true
            } label: {
                Label("Export All Training Data", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.allExamples.isEmpty)
            .padding(.horizontal)

            // Saved count
            Text("\(store.allExamples.count) saved example(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    // MARK: - Logic

    /// Adds a new event to the list, optionally prefilled from an extracted event.
    private func addEvent(from source: ExtractedEvent?) {
        let event = TrainingEvent(
            datetimeStart: source?.datetimeStart ?? "",
            datetimeEnd: source?.datetimeEnd ?? "",
            description: source?.description ?? ""
        )
        withAnimation {
            events.append(event)
        }
    }

    /// Validates all events and saves to the store if valid.
    private func saveExample() {
        validationErrors.removeAll()
        var hasErrors = false

        for event in events {
            var errors: [String] = []

            if let error = DatetimeValidator.validate(event.datetimeStart) {
                errors.append("Start: \(error)")
            }
            if let error = DatetimeValidator.validate(event.datetimeEnd, allowEmpty: true) {
                errors.append("End: \(error)")
            }
            if event.description.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("Description is required")
            }

            if !errors.isEmpty {
                validationErrors[event.id] = errors
                hasErrors = true
            }
        }

        guard !hasErrors else { return }

        let example = TrainingExample(
            url: url,
            createdAt: Date(),
            events: events
        )
        store.save(example)

        // Reset for next example
        events.removeAll()
        showingSaveConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            showingSaveConfirmation = false
        }
    }
}

// MARK: - Prefill Picker Sheet

/// A modal sheet listing events from each extraction method, grouped by algorithm.
/// The user taps one to prefill a new training event, or "Blank" to start empty.
private struct PrefillPickerSheet: View {
    let extractionStates: [ExtractionMethod: ExtractionState]
    let onSelect: (ExtractedEvent?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Blank option
                Section {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("Blank Event", systemImage: "plus")
                    }
                }

                // One section per extraction method that has completed results
                ForEach(ExtractionMethod.allCases) { method in
                    if let events = completedEvents(for: method), !events.isEmpty {
                        Section(method.rawValue) {
                            ForEach(events) { event in
                                Button {
                                    onSelect(event)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.description)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .font(.caption)
                                            Text(event.datetimeStart)
                                            if let end = event.datetimeEnd {
                                                Text("–")
                                                Text(end)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Prefill From...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Returns the completed events for a method, or nil if not completed.
    private func completedEvents(for method: ExtractionMethod) -> [ExtractedEvent]? {
        if case let .completed(events) = extractionStates[method] {
            return events
        }
        return nil
    }
}

// MARK: - File Document for Export

/// A minimal `FileDocument` wrapper around JSON data for use with `.fileExporter`.
struct TrainingDataDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
