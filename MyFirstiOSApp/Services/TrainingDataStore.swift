// TrainingDataStore.swift
// ======================
// Manages persistence of training examples as a JSON file in the app's Documents directory.
//
// ## How It Works
// Training examples are stored as a JSON array in `training_data.json`. The file is loaded
// into memory at init and written back atomically on every save. This is efficient because
// the training data set is small (dozens to low hundreds of examples).
//
// ## Why JSON Instead of SwiftData
// The primary use case is append-and-export. The on-disk format is identical to the export
// format, keeping the implementation simple. If querying or filtering becomes necessary,
// migration to SwiftData is straightforward since the model shapes already exist as Codable structs.
//
// ## Thread Safety
// Marked `@MainActor` because it is accessed exclusively from SwiftUI views. File I/O for
// a small JSON file is fast enough to not block the UI.

import Foundation

/// Loads, saves, and exports training examples from a JSON file.
@Observable
@MainActor
class TrainingDataStore {
    /// All saved training examples, loaded from disk at init.
    private(set) var allExamples: [TrainingExample] = []

    /// Path to the JSON file in the app's Documents directory.
    private let fileURL: URL

    /// JSON encoder configured for readable output and ISO 8601 dates.
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    /// JSON decoder matching the encoder's date strategy.
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    init() {
        // swiftlint:disable:next force_unwrapping
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("training_data.json")
        allExamples = Self.loadFromDisk(at: fileURL, using: decoder)
    }

    /// Appends a training example and persists the full array to disk.
    func save(_ example: TrainingExample) {
        allExamples.append(example)
        writeToDisk()
    }

    /// Serializes all saved examples as pretty-printed JSON data, suitable for export.
    func exportAllAsJSON() -> Data {
        (try? encoder.encode(allExamples)) ?? Data()
    }

    // MARK: - Private

    /// Loads the JSON file from disk, returning an empty array if the file doesn't exist or is malformed.
    private static func loadFromDisk(
        at url: URL,
        using decoder: JSONDecoder
    ) -> [TrainingExample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([TrainingExample].self, from: data)) ?? []
    }

    /// Writes the current examples array to disk atomically.
    private func writeToDisk() {
        guard let data = try? encoder.encode(allExamples) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
