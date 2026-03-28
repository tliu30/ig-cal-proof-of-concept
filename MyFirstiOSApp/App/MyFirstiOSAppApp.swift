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
///
/// ## URL Scheme Handling
/// The app registers a custom URL scheme (`myfirstiosapp://`) so the ShareInspector
/// extension can open the main app after writing a shared URL to App Groups UserDefaults.
/// `.onOpenURL` fires when the app is opened via this scheme, and `scenePhase` changes
/// to `.active` when the app returns to the foreground.
@main
struct MyFirstiOSAppApp: App {
    /// Tracks the current scene phase (active, inactive, background).
    @Environment(\.scenePhase) private var scenePhase

    /// The pending URL received from the share extension, if any.
    @State private var pendingURL: URL?

    /// Shared store for user-corrected training examples, persisted as JSON on disk.
    @State private var trainingDataStore = TrainingDataStore()

    var body: some Scene {
        WindowGroup {
            ContentView(pendingURL: $pendingURL)
                .environment(trainingDataStore)
                .onOpenURL { url in
                    // Triggered when opened via myfirstiosapp://share URL scheme.
                    // Read the actual Instagram URL from shared UserDefaults.
                    checkForPendingURL()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        checkForPendingURL()
                    }
                }
        }
    }

    /// Reads a pending Instagram URL from App Groups UserDefaults.
    /// If found, sets `pendingURL` and clears the stored value.
    private func checkForPendingURL() {
        let sharedDefaults = UserDefaults(suiteName: SharedConstants.appGroupID)
        guard let urlString = sharedDefaults?.string(forKey: SharedConstants.pendingURLKey),
              let url = URL(string: urlString) else {
            return
        }
        // Clear it so we don't re-process on next foreground.
        sharedDefaults?.removeObject(forKey: SharedConstants.pendingURLKey)
        sharedDefaults?.synchronize()
        pendingURL = url
    }
}
