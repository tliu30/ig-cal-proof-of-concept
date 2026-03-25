# Utilities Directory

## Purpose
Contains app-wide constants, extensions, and helper functions that don't belong to any specific layer.

## Architecture Role
Utilities are cross-cutting — any layer (Models, Views, ViewModels, Services) can import and use them. They should remain stateless and side-effect-free.

## Files

### `Constants.swift`
A caseless `enum` (cannot be instantiated) used as a namespace for app-wide constants:
- `instagramURL` — the fixed Instagram post URL to analyze.
- `mobileSafariUserAgent` — user agent string to spoof Mobile Safari.
- `pageLoadDelay` — nanoseconds to wait after page load for JS rendering.
- `extractionTimeout` — maximum seconds for the entire extraction process.

## Key Concepts for Non-Swift Developers

| Concept | Explanation |
|---------|-------------|
| Caseless `enum` | An enum with no cases can't be instantiated — used purely as a namespace. Like a static class in Java or a frozen object in JS. |
| `static let` | A compile-time constant on the type itself (not on instances). Like `const` in a module. |
