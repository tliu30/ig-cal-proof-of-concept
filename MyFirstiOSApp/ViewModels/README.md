# ViewModels Directory

## Purpose
Contains `@Observable` classes that hold app state and orchestrate business logic. ViewModels are the bridge between raw data (Models) and the UI (Views).

## Architecture Role
In MVVM, the **ViewModel** is the middle layer that:
1. Owns the app's mutable state (loading flags, results, errors).
2. Orchestrates async workflows (load page → extract content → download images → run OCR).
3. Exposes state in a view-friendly form — Views just read properties, they never call services directly.

The `@Observable` macro (iOS 17+) makes all stored properties automatically observable. SwiftUI tracks exactly which properties each View reads and only re-renders when those specific properties change.

## Files

### `PostViewModel.swift`
The main (and only) ViewModel. Manages the full extraction pipeline:

```
startExtraction() → needsWebView=true → InstagramWebView loads page
                                          ↓
                            handleExtractedContent() called with text + image URLs + HTML
                                          ↓
                            Downloads each image via URLSession
                                          ↓
                            Runs OCR on each image via OCRService
                                          ↓
                            Builds final Post model, sets isLoading=false
```

**State properties** (observed by Views):
- `isLoading` — controls whether LoadingView or ResultsView is shown
- `loadingPhase` — descriptive text for the current step
- `progress` — 0.0 to 1.0 for the progress bar
- `post` — the final result, nil until processing completes
- `errorMessage` — set if something goes wrong
- `needsWebView` — tells ContentView to include/exclude the hidden WKWebView

## Key Concepts for Non-Swift Developers

| Concept | Explanation |
|---------|-------------|
| `@Observable` | Macro that makes all properties observable. Like MobX `@observable` or Vue `reactive()`. |
| `class` (not struct) | ViewModels are reference types so multiple views can share the same instance. |
| `@MainActor` | Ensures a method runs on the main thread (required for UI updates). Like `runOnUiThread` in Android. |
| `async/await` | Swift's structured concurrency. Like JS async/await or Python asyncio. |
| `actor` | A reference type that serializes access to prevent data races. Like a single-threaded executor. |
