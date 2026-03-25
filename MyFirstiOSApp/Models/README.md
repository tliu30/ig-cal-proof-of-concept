# Models Directory

## Purpose
Contains pure data structures that represent the app's domain objects. Models hold data but contain no business logic, UI code, or side effects.

## Architecture Role
In MVVM, **Models** are the bottom layer. They define the shape of data that flows through the app:
- **Services** produce Models (e.g., OCRService creates `OCRResult`).
- **ViewModels** hold and transform Models for display.
- **Views** read Models (via ViewModels) to render UI.

Models are value types (`struct`) so they're automatically thread-safe — you can pass them between threads without risk of data races.

## Files

### `Post.swift`
Represents a fully-extracted Instagram post, including:
- The source URL
- Extracted text content (caption, comments)
- Full-size image URLs found on the page
- Raw HTML page source (for the debug tab)
- OCR results keyed by image URL

### `OCRResult.swift`
Represents the output of running OCR on a single image:
- The source image URL and downloaded image data
- Recognized text (all lines concatenated)
- Confidence score (0.0–1.0)

## Key Concepts for Non-Swift Developers

| Concept | Explanation |
|---------|-------------|
| `struct` | A value type — copied on assignment, not shared. Like a `dataclass` in Python or a plain object spread in JS. |
| `Identifiable` | Protocol requiring an `id` property. SwiftUI uses this to track items in lists efficiently (like React's `key` prop). |
| `UUID()` | Generates a random unique identifier. Used as the default `id` for Identifiable conformance. |
| `let` vs `var` | `let` = immutable (constant), `var` = mutable. Most model properties are `let` since data doesn't change after creation. |
