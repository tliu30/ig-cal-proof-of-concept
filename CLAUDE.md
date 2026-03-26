# CLAUDE.md

## Project Overview

Proof-of-concept iOS app that loads an Instagram post via WKWebView, extracts post text, runs OCR on full-sized images using Apple Vision, and displays results. Two views: a loading screen during processing, then a results screen with extracted text/images and a swipeable tab showing page source for debugging.

See `README.md` for full requirements.

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Architecture:** MVVM
- **State:** `@Observable` macro (Observation framework, iOS 17+), `@State`, `@Environment`
- **Persistence:** SwiftData
- **Networking:** URLSession + async/await
- **Concurrency:** Structured concurrency (async/await, actors)
- **OCR:** Apple Vision framework (`VNRecognizeTextRequest`)
- **WebView:** WKWebView via `UIViewRepresentable` wrapper
- **Min Target:** iOS 18.6

## Project Structure

```
MyFirstiOSApp/
  App/
    MyFirstiOSAppApp.swift       # @main entry point
  Models/                        # Data structs (Post, OCRResult, etc.)
  Views/                         # SwiftUI views
    Components/                  # Reusable UI components (LoadingView, etc.)
  ViewModels/                    # @Observable classes with business logic
  Services/                      # Pure logic layers (OCR, WebView, Network)
  Utilities/                     # Extensions, constants
  Resources/                     # Assets.xcassets, Info.plist
```

Each subdirectory should include a README explaining the purpose and architecture of its modules, written for an audience unfamiliar with Swift.

## Build & Run Commands

> **Tip:** Most commands below are wrapped in the project `Makefile`. Run `make help`
> to see all available targets, or `make preflight` to format, lint, build, and test
> in one step.

### Prerequisites

- Xcode 15+ (for iOS 17 SDK)
- `brew install swiftlint swiftformat` for linting

### Simulator

```bash
# List available schemes
xcodebuild -list -project MyFirstiOSApp.xcodeproj

# Build for simulator
xcodebuild -scheme MyFirstiOSApp -project MyFirstiOSApp.xcodeproj \
  -sdk iphonesimulator -configuration Debug build

# List available simulators
xcrun simctl list devices available

# Boot a simulator (use iPhone 17 Pro — matches our physical test device)
xcrun simctl boot "iPhone 17 Pro"

# Install and launch
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/MyFirstiOSApp.app
xcrun simctl launch booted <bundle-identifier>
```

Or open in Xcode and press Cmd+R:
```bash
open MyFirstiOSApp.xcodeproj
```

### USB-Connected Device

```bash
xcodebuild -scheme MyFirstiOSApp -sdk iphoneos \
  -destination 'platform=iOS,id=<DeviceUDID>' \
  -allowProvisioningUpdates build
```

Requires Apple Developer account and valid provisioning profile.

### Running Tests

```bash
xcodebuild test -scheme MyFirstiOSApp -project MyFirstiOSApp.xcodeproj \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Always use **iPhone 17 Pro** as the simulator destination — it matches our physical test device.

### TestFlight

Use `xcodebuild archive` then `xcodebuild -exportArchive`, or Fastlane for automation.

## Linting

```bash
# Lint
swiftlint lint
swiftformat --lint .

# Auto-fix
swiftlint lint --fix
swiftformat .
```

Configure via `.swiftlint.yml` and `.swiftformat` in project root.

## Key Implementation Notes

### WKWebView + Instagram

- **Must set a mobile Safari user agent** or Instagram will block/degrade content:
  ```swift
  webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
  ```
- Instagram uses heavy client-side rendering; content may not be in initial HTML. Wait for full page load or observe DOM mutations before extracting.
- Instagram shows login modals after a few seconds. Inject JavaScript to dismiss overlays.
- Use `WKUserScript` for JavaScript injection at document end; use `WKScriptMessageHandler` to receive messages back from JS.
- Extract full-size image URLs (not thumbnails/crops) from the DOM via JavaScript.

### Apple Vision OCR

- Use `VNRecognizeTextRequest` with `.accurate` recognition level.
- Set `recognitionLanguages = ["en-US"]` and `usesLanguageCorrection = true`.
- Vision API is synchronous (`VNImageRequestHandler.perform()`). Run on a background thread, not the main thread. Wrap in a `Task` or use `DispatchQueue.global()`.
- Results are `[VNRecognizedTextObservation]`; call `topCandidates(1).first?.string` on each.

### SwiftUI + WKWebView

- Wrap WKWebView in a `UIViewRepresentable` struct with a `Coordinator` for delegate callbacks.
- Use `@Observable` ViewModels (not `ObservableObject`/`@Published`) for iOS 17+.
- Views own ViewModels via `@State private var viewModel = MyViewModel()`.

## Code Style

- All modules should include extensive documentation explaining how they work to an audience unfamiliar with Swift.
- Subdirectory READMEs should explain both purpose and architectural role.
- This is a proof-of-concept: no CI/CD or deploy pipeline needed.
- Focus on clear, well-documented code over production hardening.
