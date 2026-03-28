# MyFirstiOSApp

Proof-of-concept iOS app that loads an Instagram post, extracts text, runs OCR
on full-sized images using Apple Vision, and displays the results.

## Quick Start

```bash
# Install dev tools (SwiftLint, SwiftFormat)
make install

# Download the LLM model for local event extraction (~1.1 GB)
make download-model

# Verify your setup
make check

# Open in Xcode (then Cmd+R to run)
make open

# Build from command line
make build

# Run tests
make test

# Lint (check only)
make lint

# Auto-format
make format

# Full preflight check (format → lint → build → test)
make preflight

# See all available commands
make help
```

## Prerequisites

- **macOS** with [Xcode](https://developer.apple.com/xcode/) 15+ installed
- **Homebrew** ([brew.sh](https://brew.sh)) for installing lint tools
- Run `make check` to verify your setup

## Architecture

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation, build
commands, and implementation notes.

## Requirements

Create a proof-of-concept iOS app that

1. loads a fixed URL for an Instagram post using the iOS WebView
2. extracts the text from the post
3. runs OCR on all full-sized (not cropped) images on the web page
4. displays the text from (2), then the image from (3) along with the
   text extracted from that image in (3)

There should be two views: the user should first see a loading screen as
the app runs steps (1)-(3) and then a results screen, with a link to the
fixed URL so the user can cross-compare.

The results screen uses a swipeable tab view with seven pages:
1. **Results** — post text, images with OCR results, link to original post
2. **Extraction Inputs** — the exact data (caption, OCR texts, alt texts, current date) fed to the extraction algorithms
3. **Regex** — events extracted via regex heuristics
4. **NSDataDetector** — events extracted via Apple's NSDataDetector
5. **Foundation Models** — events extracted via on-device Foundation Models (iOS 26+)
6. **Llama LLM** — events extracted via local Llama model, with inference diagnostics
7. **Training Data** — editor for creating corrected ground-truth examples

Start by implementing a version we can run with Simulator, followed by
dev tools to help run on a USB-connected device, and finally by dev tools
that deploy this to TestFlight.

### Tech stack

- OCR: use Apple Vision framework (https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- UI: SwiftUI
- Architecture: MVVM
- State: @Observable + @State + @Environment
- Persistence: SwiftData
- Networking: URLSession + async / await
- Concurrency: Structured concurrency (async / await, actors)
- Min Target: iOS 17

### How to work in this project

This is a proof-of-concept - no need for CI/CD or a deploy pipeline.

However, we do want good local dev tooling (build scripts, linting, etc).

Part of the goal here is to help developers understand how iOS apps work - all
modules should include extensive documentation explaining how they work to
an audience that is unfamiliar with Swift; subdirectories should include READMEs
explaining not only the purpose of the modules in that subdirectory in terms of
what they do, but also how they function in the architecture.
