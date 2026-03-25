# Views Directory

## Purpose
Contains all SwiftUI views — the visual components that define what the user sees and interacts with. Views read state from ViewModels and render UI accordingly.

## Architecture Role
In MVVM, **Views** are the top layer. They:
1. Declare the UI layout using SwiftUI's declarative syntax.
2. Observe ViewModel properties — when a property changes, affected views re-render automatically.
3. Forward user actions (taps, swipes) to the ViewModel.

Views should contain **no business logic** — they only decide *how* to display data, not *what* data to display or how to compute it.

## Files

### `ContentView.swift`
The root view. Acts as a router:
- Shows `LoadingView` while `viewModel.isLoading` is true.
- Shows `ResultsView` when a `Post` is ready.
- Shows an error state with a retry button if something fails.
- Hosts the hidden `InstagramWebView` (zero-sized) when content extraction is in progress.

### `LoadingView.swift`
A full-screen loading indicator showing:
- An animated SF Symbol icon
- A progress bar (0–100%)
- The current processing phase as text (e.g., "Downloading images...")

### `ResultsView.swift`
A two-page swipeable view (`TabView` with page style):
- **Page 1 — Results**: Post text, images with OCR results, link to original post.
- **Page 2 — Source**: Raw HTML of the loaded page for debugging.

### `Components/ImageOCRCard.swift`
A reusable card that displays one image and its OCR output. Shows:
- The downloaded image
- A confidence badge (green/orange/red)
- The recognized text (or "no text detected")

## Key Concepts for Non-Swift Developers

| Concept | Explanation |
|---------|-------------|
| `View` protocol | Every SwiftUI view is a struct conforming to `View`. Its `body` property returns other views, forming a tree. Like React components returning JSX. |
| `@State` | Marks view-owned mutable state. When it changes, the view re-renders. Like `useState()` in React. |
| `some View` | An opaque return type — means "returns a View, but I won't say which concrete type." Lets SwiftUI optimize without boxing. |
| `#Preview` | A macro that creates an Xcode canvas preview. Like Storybook stories — lets you see a component in isolation. |
