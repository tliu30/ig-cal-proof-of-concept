/// ShareViewController.swift
/// =========================
/// Entry point for the ShareInspector share extension.
///
/// ## What Is a Share Extension?
/// A share extension is a small app that appears in the iOS share sheet. When a user
/// taps "Share" in another app (like Instagram) and selects our extension, iOS launches
/// this view controller. The extension runs in a separate process from the main app.
///
/// ## How Data Arrives
/// iOS passes shared content through `extensionContext?.inputItems`, which is an array
/// of `NSExtensionItem` objects. Each item has `attachments` — an array of
/// `NSItemProvider` objects that can load different data types (URLs, text, images).
///
/// ## Data Flow
/// 1. User taps Share in Instagram and selects our extension
/// 2. We extract the shared URL from the NSItemProvider
/// 3. We strip tracking params and write the clean URL to App Groups UserDefaults
/// 4. We open the main app via custom URL scheme
/// 5. The main app reads the pending URL and starts extraction

import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// The main view controller for the share extension.
/// Receives a shared URL from Instagram, validates it, stores it in shared
/// UserDefaults, and opens the main app to process it.
class ShareViewController: UIViewController {

    /// Collected shared data from all input items (for diagnostic display).
    private var sharedData = SharedData()

    override func viewDidLoad() {
        super.viewDidLoad()
        extractAndHandleURL()
    }

    /// Extracts the shared URL, writes it to App Groups, and opens the main app.
    /// Falls back to the diagnostic inspector view if no valid URL is found.
    private func extractAndHandleURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            presentInspectorView()
            return
        }

        // Collect raw descriptions for debugging.
        for (itemIndex, item) in extensionItems.enumerated() {
            let desc = "Item \(itemIndex): attributedTitle=\(item.attributedTitle?.string ?? "nil"), " +
                "attributedContentText=\(item.attributedContentText?.string ?? "nil"), " +
                "attachments=\(item.attachments?.count ?? 0)"
            sharedData.rawItemDescriptions.append(desc)
        }

        let allAttachments = extensionItems.flatMap { $0.attachments ?? [] }

        for (index, provider) in allAttachments.enumerated() {
            let typeDesc = "Attachment \(index): types=\(provider.registeredTypeIdentifiers)"
            sharedData.rawItemDescriptions.append(typeDesc)
        }

        // Look for the first URL attachment (Instagram sends exactly one).
        guard let urlProvider = allAttachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) else {
            presentInspectorView()
            return
        }

        urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, error in
            DispatchQueue.main.async {
                guard let self else { return }

                // Try to get the URL from the loaded item.
                var sharedURL: URL?
                if let url = item as? URL {
                    sharedURL = url
                } else if let urlData = item as? Data {
                    sharedURL = URL(dataRepresentation: urlData, relativeTo: nil)
                }

                guard let url = sharedURL else {
                    self.presentInspectorView()
                    return
                }

                self.sharedData.urls.append(url.absoluteString)

                // Strip tracking params and write to shared UserDefaults.
                let cleanURL = URLValidator.stripTrackingParams(from: url)
                let sharedDefaults = UserDefaults(suiteName: SharedConstants.appGroupID)
                sharedDefaults?.set(cleanURL.absoluteString, forKey: SharedConstants.pendingURLKey)
                sharedDefaults?.synchronize()

                // Open the main app via custom URL scheme.
                let appURL = URL(string: "\(SharedConstants.appURLScheme)://share")!
                self.openMainApp(url: appURL)
            }
        }
    }

    /// Opens the main app using its custom URL scheme.
    ///
    /// Extensions cannot use `UIApplication.shared.open()` directly. Instead,
    /// we use the `openURL:` selector on the nearest `UIResponder` that
    /// responds to it (which reaches the system's URL handler).
    private func openMainApp(url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url)
                break
            }
            responder = current.next
        }

        // Dismiss the extension after a short delay to allow the URL to open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Presents the SwiftUI diagnostic view as a fallback when no valid URL is found.
    private func presentInspectorView() {
        let inspectorView = ShareInspectorView(
            sharedData: sharedData,
            onDone: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )

        let hostingController = UIHostingController(rootView: inspectorView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}

/// Data collected from the share sheet, displayed in the diagnostic view.
struct SharedData {
    var urls: [String] = []
    var texts: [String] = []
    var imageCount: Int = 0
    var imageSizes: [Int] = []
    var rawItemDescriptions: [String] = []
}
