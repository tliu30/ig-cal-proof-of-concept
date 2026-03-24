# Introduction

Create a proof-of-concept iOS app that 

1. loads a fixed URL for an Instagram post using the iOS WebView
2. extracts the text from the post
3. runs OCR on all full-sized (not cropped) images on the web page
4. displays the text from (2), then the image from (3) along with the
   text extracted from that image in (3)

There should be two views: the user should first see a loading screen as
the app runs steps (1)-(3) and then a results screen, with a link to the
fixed URL so the user can cross-compare.

On the results screen, we should have a second tab the user can swipe to
to see the source code of the page opened up in step (1), for further
debugging.

Start by implementing a version we can run with Simulator, followed by
dev tools to help run on a USB-connected device, and finally by dev tools
that deploy this to TestFlight.

## Tech stack

- OCR: use Apple Vision framework (https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- UI: SwiftUI
- Architecture: MVVM
- State: @Observable + @State + @Environment
- Persistence: SwiftData
- Networking: URLSession + async / await
- Concurrency: Structured concurrency (async / await, actors)
- Min Target: iOS 17

## How to work in this project

This is a proof-of-concept - no need for tests, CI/CD, or a deploy pipeline.

However, we do want good local dev tooling (build scripts, linting, etc).

Part of the goal here is to help developers understand how iOS apps work - all
modules should include extensive documentation explaining how they work to
an audience that is unfamiliar with Swift; subdirectories should include READMEs
explaining not only the purpose of the modules in that subdirectory in terms of
what they do, but also how they function in the architecture.
