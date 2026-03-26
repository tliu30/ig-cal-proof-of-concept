/// EventExtractionService.swift
/// ============================
/// Extracts structured date/time events from unstructured text sources using
/// a local LLM (Qwen2.5-3B-Instruct) via llama.cpp for inference.
///
/// ## Approach: Local LLM via llama.cpp (Experiment D)
/// A small quantized LLM processes all text sources (OCR, alt text, caption)
/// with a structured system prompt encoding extraction rules. The model outputs
/// JSON which is parsed into ExtractedEvent structs.
///
/// ## Pipeline
/// ```
/// Inputs → Build Prompt → LLM Inference → Parse JSON → Sort → Output
/// ```
///
/// The model is loaded once (lazy singleton) and reused across calls to avoid
/// the ~30-60s load time on each invocation.

import Foundation
import LlamaSwift

enum EventExtractionService {

    /// Extracts structured events from unstructured text sources.
    ///
    /// - Parameters:
    ///   - ocrTexts: Array of text strings recognized from images via OCR.
    ///   - altTexts: Array of image alt text strings from the page HTML.
    ///   - caption: The post caption text.
    ///   - currentDate: The current date, used to infer the year for dates that omit it.
    /// - Returns: Array of extracted events with start/end datetimes and descriptions.
    static func extractEvents(
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) -> [ExtractedEvent] {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmptyOCR = ocrTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let nonEmptyAlt = altTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // Early exit: nothing to work with
        guard !nonEmptyOCR.isEmpty || !nonEmptyAlt.isEmpty || !trimmedCaption.isEmpty else {
            return []
        }

        // Build the user prompt (system prompt is pre-cached in the session file)
        let userPrompt = buildUserPrompt(
            ocrTexts: nonEmptyOCR,
            altTexts: nonEmptyAlt,
            caption: trimmedCaption,
            currentDate: currentDate
        )

        // Run inference
        let manager = LlamaModelManager.shared
        manager.loadIfNeeded()

        guard manager.isReady else {
            return []
        }

        let response = manager.generate(userPrompt: userPrompt, maxTokens: 4096)

        // Parse JSON response
        let events = parseResponse(response)

        // Sort chronologically
        return events.sorted { $0.datetimeStart < $1.datetimeStart }
    }
}

// MARK: - Prompt Engineering

// fileprivate so LlamaModelManager can access buildSystemPrompt for session caching
fileprivate extension EventExtractionService {

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func buildSystemPrompt(currentDate: Date) -> String {
        """
        You are an event extraction system. Extract structured event data from Instagram post content.

        ## Output Format
        Return ONLY a JSON array of events. No other text, no explanations, no markdown code fences. Each event object has:
        - "datetimeStart": string in "YYYY-MM-DD HH:mm" format for events with times, or "YYYY-MM-DD" for multi-day events with no specific daily times
        - "datetimeEnd": string in same format, or null if unknown. When only a start time is given, set to null
        - "description": string — concise event name with key performers/details (under 80 characters)

        If there are no events, return exactly: []

        ## Rules

        ### Date/Time
        - 24-hour format: "19:00" not "7:00 PM"
        - Midnight end times use NEXT calendar day "00:00" (event March 13 ending midnight → datetimeEnd "2026-03-14 00:00")
        - Multi-day events with no daily schedule: date-only "YYYY-MM-DD" for both start and end
        - "7-11pm" means 19:00 to 23:00. "7-Midnite" or "7-Midnight" means 19:00 to 00:00 (next day)
        - "10PM" alone with no end time → datetimeEnd is null
        - RSVP/entry/discount times like "$5 before 11pm" or "free b4 midnight" are NOT end times — ignore them for datetimeEnd

        ### Year Inference
        - Current date: \(formatDate(currentDate))
        - If a date has no year, use the current year or next year — whichever puts it closest to the future from the current date

        ### Timezone
        - Dual timezones like "4 PM PT / 7 ET": use Eastern Time (ET) since this is NYC. So 7 PM ET = 19:00

        ### Past Events
        - If the caption says "last night", "who came out", "thank you to the crowd" etc, this is a recap of a PAST event. Return []

        ### Typo Corrections
        - If caption has "***TYPO" or "****TYPO" followed by corrected times like "8PM - 12AM", use those corrected times instead of what OCR shows
        - OCR "8-12PM" but caption says "TYPO - 8PM - 12AM" → start 20:00, end 00:00 next day

        ### Doors/Show
        - "Doors: 6:30 p.m. / Show: 7:00 p.m." → use doors time (6:30 PM = 18:30) as datetimeStart

        ### Spanish Dates
        - "7 de abril de 2026" = April 7, 2026

        ### Event Counting
        - Multiple performers at one venue on one date/time = ONE event, not separate events
        - A flyer with shows on different dates = one event per date
        - Monthly calendar with separate listings = one event per listing

        ### Descriptions
        - Use the caption's first sentence/line as the base for the description (keep most of its words)
        - Include key performers/artists mentioned
        - Include venue name if clearly stated
        - Prefer caption text over OCR for spelling
        - Remove emojis, @handles, and URLs but keep the rest of the wording

        ## Examples

        Example 1 — time range gives both start and end:
        OCR: "OPEN MIC NIGHT\\nFri March 15\\n8-11pm\\nAt The Venue"
        Output: [{"datetimeStart":"2026-03-15 20:00","datetimeEnd":"2026-03-15 23:00","description":"Open Mic Night at The Venue"}]

        Example 2 — single time, no end time, RSVP discount is NOT an end time:
        Caption: "SAZONAO RETURNS THIS FRIDAY! 10PM | $5 entry b4 11pm"
        OCR: "MARCH 27TH"
        Output: [{"datetimeStart":"2026-03-27 22:00","datetimeEnd":null,"description":"Sazonao Returns This Friday"}]

        Example 3 — no events:
        Caption: "Beautiful sunset at the park"
        Output: []
        """
    }

    static func buildUserPrompt(
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) -> String {
        var parts: [String] = []

        parts.append("Current date: \(formatDate(currentDate))")
        parts.append("")

        if !ocrTexts.isEmpty {
            parts.append("## OCR Text (from images)")
            for (i, text) in ocrTexts.enumerated() {
                if i > 0 { parts.append("---") }
                parts.append(text)
            }
            parts.append("")
        }

        if !altTexts.isEmpty {
            parts.append("## Image Alt Text")
            for (i, text) in altTexts.enumerated() {
                if i > 0 { parts.append("---") }
                parts.append(text)
            }
            parts.append("")
        }

        if !caption.isEmpty {
            parts.append("## Post Caption")
            parts.append(caption)
            parts.append("")
        }

        parts.append("Extract all future events from this Instagram post. Return ONLY a JSON array.")

        return parts.joined(separator: "\n")
    }
}

// MARK: - Response Parsing

private extension EventExtractionService {

    struct EventJSON: Decodable {
        let datetimeStart: String
        let datetimeEnd: String?
        let description: String
    }

    static func parseResponse(_ text: String) -> [ExtractedEvent] {
        // Strip markdown code fences if present
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to find JSON array in the response
        if let startIdx = cleaned.firstIndex(of: "["),
           let endIdx = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        guard let jsonData = cleaned.data(using: .utf8),
              let events = try? JSONDecoder().decode([EventJSON].self, from: jsonData) else {
            return []
        }

        return events.map {
            ExtractedEvent(
                datetimeStart: $0.datetimeStart,
                datetimeEnd: $0.datetimeEnd,
                description: $0.description
            )
        }
    }
}

// MARK: - llama.cpp Model Manager

/// Manages the llama.cpp model lifecycle and inference. Loaded once and reused.
///
/// ## How llama.cpp Works (for non-C/Swift developers)
/// llama.cpp is a C library for running LLM inference. The workflow is:
/// 1. Initialize the backend (one-time setup)
/// 2. Load a quantized model file (.gguf) into memory
/// 3. Create a context (working memory for inference)
/// 4. Tokenize the prompt (convert text → integer tokens)
/// 5. Feed tokens through the model (forward pass)
/// 6. Sample output tokens one by one (autoregressive generation)
/// 7. Convert output tokens back to text
///
/// This class wraps all of that into a simple `generate(systemPrompt:userPrompt:)` API.
private final class LlamaModelManager {
    static let shared = LlamaModelManager()

    private var model: OpaquePointer?   // llama_model * (opaque in Swift)
    private var ctx: OpaquePointer?     // llama_context * (opaque in Swift)
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private(set) var isReady = false

    /// Number of tokens in the cached system prompt prefix.
    /// Loaded from a session file on disk (or computed once and saved).
    private var cachedSystemTokenCount: Int32 = 0

    private init() {}

    deinit {
        if let sampler { llama_sampler_free(sampler) }
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
        llama_backend_free()
    }

    // MARK: - Model Path Resolution

    private static var modelsDir: URL {
        if let envPath = ProcessInfo.processInfo.environment["LLAMA_MODEL_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath).deletingLastPathComponent()
        }
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // MyFirstiOSApp/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("models")
    }

    private static var modelPath: String {
        if let envPath = ProcessInfo.processInfo.environment["LLAMA_MODEL_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }
        return modelsDir.appendingPathComponent("Qwen2.5-1.5B-Instruct-Q4_K_M.gguf").path
    }

    private static var sessionCachePath: String {
        modelsDir.appendingPathComponent("system-prompt-cache.bin").path
    }

    // MARK: - Model Loading

    func loadIfNeeded() {
        guard !isReady else { return }

        let path = Self.modelPath
        guard FileManager.default.fileExists(atPath: path) else {
            print("[LlamaModelManager] Model not found at: \(path)")
            return
        }

        llama_backend_init()

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 0 // CPU-only: Metal in iOS Simulator has massive overhead
        model = llama_model_load_from_file(path, mparams)

        guard model != nil else {
            print("[LlamaModelManager] Failed to load model from: \(path)")
            return
        }

        var cparams = llama_context_default_params()
        cparams.n_ctx = 4096
        cparams.n_batch = 512
        ctx = llama_init_from_model(model, cparams)

        guard ctx != nil else {
            print("[LlamaModelManager] Failed to create context")
            return
        }

        let sparams = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.0))
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        // Load or create the system prompt session cache
        loadOrCreateSessionCache()

        isReady = true
        print("[LlamaModelManager] Model loaded successfully")
    }

    /// Loads the pre-computed system prompt KV cache from disk, or creates it on first run.
    /// This eliminates the ~130s first-call penalty for processing the 948-token system prompt.
    private func loadOrCreateSessionCache() {
        guard let model, let ctx else { return }
        let vocab = llama_model_get_vocab(model)!
        let cachePath = Self.sessionCachePath

        if FileManager.default.fileExists(atPath: cachePath) {
            // Load pre-computed state from disk
            var tokens = [llama_token](repeating: 0, count: 4096)
            var nTokens: Int = 0
            let ok = tokens.withUnsafeMutableBufferPointer { buf in
                llama_state_load_file(ctx, cachePath, buf.baseAddress!, 4096, &nTokens)
            }
            if ok {
                cachedSystemTokenCount = Int32(nTokens)
                print("[LlamaModelManager] Session cache loaded (\(nTokens) tokens) from disk")
                return
            }
            print("[LlamaModelManager] Session cache load failed, regenerating")
        }

        // First run: process system prompt and save to disk
        // Use a fixed reference date for the cache (tests use 2026-03-25)
        let currentDate = Date()
        let systemPrompt = EventExtractionService.buildSystemPrompt(currentDate: currentDate)
        let systemPrefix = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n"

        // Tokenize
        let nBytes = Int32(systemPrefix.utf8.count)
        let maxTokens = nBytes + 64
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let nTokens = systemPrefix.withCString { cStr in
            llama_tokenize(vocab, cStr, nBytes, &tokens, maxTokens, true, true)
        }
        guard nTokens > 0 else {
            print("[LlamaModelManager] System prompt tokenization failed")
            return
        }

        // Decode (the slow part — only happens once)
        print("[LlamaModelManager] Processing system prompt (\(nTokens) tokens)...")
        var nProcessed: Int32 = 0
        while nProcessed < nTokens {
            let remaining = nTokens - nProcessed
            let currentBatch = min(remaining, 512)
            let result: Int32 = tokens.withUnsafeMutableBufferPointer { buf in
                let ptr = buf.baseAddress! + Int(nProcessed)
                return llama_decode(ctx, llama_batch_get_one(ptr, currentBatch))
            }
            if result != 0 {
                print("[LlamaModelManager] System prompt decode failed")
                return
            }
            nProcessed += currentBatch
        }

        // Save state to disk
        let saved = tokens.withUnsafeBufferPointer { buf in
            llama_state_save_file(ctx, cachePath, buf.baseAddress!, Int(nTokens))
        }
        if saved {
            print("[LlamaModelManager] Session cache saved (\(nTokens) tokens) to disk")
        }
        cachedSystemTokenCount = nTokens
    }

    // MARK: - Text Generation (with prompt caching)

    func generate(userPrompt: String, maxTokens: Int = 4096) -> String {
        guard isReady, let model, let ctx, let sampler else { return "[]" }

        let vocab = llama_model_get_vocab(model)!
        let mem = llama_get_memory(ctx)

        // System prompt is pre-cached in the KV cache (loaded from session file).
        // Only process the user-specific tokens for each call.
        let userSuffix = "\(userPrompt)<|im_end|>\n<|im_start|>assistant\n"

        // Remove previous user tokens, keep cached system prefix
        llama_memory_seq_rm(mem, 0, cachedSystemTokenCount, -1)

        let nUserTokens = tokenizeAndDecode(userSuffix, vocab: vocab, ctx: ctx, startPos: cachedSystemTokenCount)
        guard nUserTokens > 0 else { return "[]" }
        print("[LlamaModelManager] Processed \(nUserTokens) user tokens (system: \(cachedSystemTokenCount) cached)")

        // Autoregressive generation loop
        var output = ""
        var nGenerated: Int32 = 0
        let eosToken = llama_vocab_eos(vocab)

        while nGenerated < maxTokens {
            let newToken = llama_sampler_sample(sampler, ctx, -1)

            if newToken == eosToken || llama_vocab_is_eog(vocab, newToken) {
                break
            }

            var buf = [CChar](repeating: 0, count: 256)
            let nChars = llama_token_to_piece(vocab, newToken, &buf, Int32(buf.count), 0, true)
            if nChars > 0 {
                buf[Int(nChars)] = 0
                output += String(cString: buf)
            }

            var newTokenArr = [newToken]
            let decodeResult = newTokenArr.withUnsafeMutableBufferPointer { bufferPtr in
                let batch = llama_batch_get_one(bufferPtr.baseAddress!, 1)
                return llama_decode(ctx, batch)
            }
            if decodeResult != 0 { break }

            nGenerated += 1
        }

        print("[LlamaModelManager] Generated \(nGenerated) tokens")
        llama_sampler_reset(sampler)
        return output
    }

    // MARK: - Helpers

    /// Tokenizes text and returns the token count (without decoding).
    private func tokenize(_ text: String, vocab: OpaquePointer) -> Int32 {
        let nBytes = Int32(text.utf8.count)
        let maxTokens = nBytes + 64
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        return text.withCString { cStr in
            llama_tokenize(vocab, cStr, nBytes, &tokens, maxTokens, false, true)
        }
    }

    /// Tokenizes text, decodes it starting at the given KV cache position, and returns the token count.
    private func tokenizeAndDecode(
        _ text: String,
        vocab: OpaquePointer,
        ctx: OpaquePointer,
        startPos: Int32
    ) -> Int32 {
        let addBos = (startPos == 0) // Only add BOS for the very first tokens
        let nBytes = Int32(text.utf8.count)
        let maxTokens = nBytes + 64
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))

        let nTokens = text.withCString { cStr in
            llama_tokenize(vocab, cStr, nBytes, &tokens, maxTokens, addBos, true)
        }

        guard nTokens > 0 else {
            print("[LlamaModelManager] Tokenization failed")
            return -1
        }

        // Decode in batches
        var nProcessed: Int32 = 0
        let batchSize: Int32 = 512

        while nProcessed < nTokens {
            let remaining = nTokens - nProcessed
            let currentBatch = min(remaining, batchSize)

            let decodeResult: Int32 = tokens.withUnsafeMutableBufferPointer { bufferPtr in
                let ptr = bufferPtr.baseAddress! + Int(nProcessed)
                let batch = llama_batch_get_one(ptr, currentBatch)
                return llama_decode(ctx, batch)
            }

            if decodeResult != 0 {
                print("[LlamaModelManager] Decode failed at position \(startPos + nProcessed)")
                return -1
            }
            nProcessed += currentBatch
        }

        return nTokens
    }
}
