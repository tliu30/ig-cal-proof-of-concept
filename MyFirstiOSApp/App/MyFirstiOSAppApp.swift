/// MyFirstiOSAppApp.swift
/// ========================
/// This is the entry point of the iOS application.
///
/// ## How iOS Apps Start
/// In SwiftUI, the `@main` attribute marks the struct that serves as the application's
/// entry point — similar to `main()` in C or `if __name__ == "__main__"` in Python.
/// The struct conforms to the `App` protocol, which requires a single computed property
/// called `body` that returns a `Scene`. A `Scene` is a container for a view hierarchy
/// that the system manages (e.g., a window on iPad, the full screen on iPhone).
///
/// `WindowGroup` is the most common scene type — it creates a window that displays the
/// root view. On iPhone, there's always exactly one window; on iPad/Mac, the user could
/// potentially open multiple windows of the same app.

import SwiftUI

/// The `@main` attribute tells the Swift compiler this is the application entry point.
/// At launch, the system creates an instance of this struct, evaluates its `body`,
/// and displays the resulting view hierarchy on screen.
@main
struct MyFirstiOSAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
