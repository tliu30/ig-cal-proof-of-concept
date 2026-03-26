# Experiment C: Foundation Models

## Approach

Uses Apple's on-device Foundation Models framework (`FoundationModels`, iOS 26+) to extract structured events from unstructured Instagram post text. The on-device LLM receives a prompt containing all input sources (OCR text, alt text, caption) along with extraction rules, and produces structured output via the `@Generable` macro.

## How It Works

1. **Input consolidation**: OCR texts, alt texts, and caption are assembled into labeled sections.
2. **Prompt construction**: A system prompt with 16 extraction rules (datetime format, midnight handling, timezone conversion, etc.) is prepended to the input data.
3. **Structured generation**: `LanguageModelSession.respond(to:generating:)` produces a `GenerableEventList` — an array of events with typed fields, constrained by the `@Generable` schema.
4. **Conversion**: `GenerableEvent` structs are converted to `ExtractedEvent` and sorted chronologically.

## Key Files

- `MyFirstiOSApp/Services/EventExtractionService.swift` — Main implementation (sync wrapper, async engine, prompt builder)
- `MyFirstiOSApp/Models/GenerableEvent.swift` — `@Generable` structs for structured LLM output

## Prerequisites

- **Xcode 26+** (for FoundationModels SDK)
- **iOS 26+ deployment target** (set in project)
- **Apple Intelligence enabled** on the Mac running the simulator (System Settings > Apple Intelligence & Siri)

## Limitations

- Requires Apple Intelligence to be enabled and the on-device model downloaded
- Model quality may vary — extraction accuracy depends on the on-device LLM's understanding of date/time formats and event structure
- The sync-to-async bridge via `DispatchSemaphore` assumes tests run off the main actor
- On-device model has token limits that may affect very large inputs (e.g., 17-event captions)
