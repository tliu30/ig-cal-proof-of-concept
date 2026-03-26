/// SharedConstants.swift
/// ====================
/// Constants shared between the main app and the ShareInspector extension.
///
/// ## App Groups
/// App Groups allow the main app and its extensions to share data via a shared
/// `UserDefaults` suite. Both targets must declare the same App Group ID in
/// their entitlements. Data written by the extension can then be read by the
/// main app (and vice versa).

import Foundation

/// Constants shared between the main app and extensions.
enum SharedConstants {
    /// The App Group identifier used for sharing data between the main app
    /// and the ShareInspector extension. Must match the entitlements in both targets.
    static let appGroupID = "group.com.example.MyFirstiOSAppH174tgj"

    /// The UserDefaults key where the extension stores a pending Instagram URL
    /// for the main app to pick up.
    static let pendingURLKey = "pendingInstagramURL"

    /// Custom URL scheme for the main app. The extension uses this to open
    /// the main app after writing the shared URL.
    static let appURLScheme = "myfirstiosapp"
}
