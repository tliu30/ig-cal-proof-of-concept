# Resources Directory

## Purpose
Contains non-code assets: images, colors, app icons, and configuration plists.

## Architecture Role
Resources are bundled into the app binary at build time. They're referenced by code at runtime (e.g., `Image("iconName")` loads from the asset catalog).

## Files

### `Assets.xcassets/`
An **Asset Catalog** — Xcode's structured format for managing images, colors, and app icons. Each subfolder (`.colorset`, `.appiconset`, `.imageset`) contains a `Contents.json` that describes the asset's variants (light/dark mode, device resolutions, etc.).

- `AppIcon.appiconset/` — The app icon shown on the home screen and App Store. Requires a 1024x1024 image for iOS.
- `AccentColor.colorset/` — The app's accent/tint color used by default for buttons, links, and navigation elements.

### `Info.plist`
The **Information Property List** — an XML file that tells iOS about the app's configuration and permissions. Key entries:
- `NSAppTransportSecurity` — Allows HTTP (not just HTTPS) network requests. Required because some Instagram CDN URLs may use HTTP.

Modern Xcode generates most Info.plist keys automatically via build settings (like `INFOPLIST_KEY_UILaunchScreen_Generation`), so this file only contains entries that can't be expressed as build settings.
