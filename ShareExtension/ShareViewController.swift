import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await captureSharedContent() }
    }

    private func captureSharedContent() async {
        guard let text = await sharedText()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            extensionContext?.cancelRequest(withError: ShareCaptureError.noText)
            return
        }

        CaptureInbox().append(CapturedTask(text: text))
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func sharedText() async -> String? {
        let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []

        // Share sheets often expose a web page title as attributedContentText
        // alongside the actual URL attachment. Prefer the URL so a website
        // share remains actionable after it reaches DynamoDB.
        for item in extensionItems {
            for attachment in item.attachments ?? [] {
                guard attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let value = try? await loadItem(from: attachment, type: .url) else {
                    continue
                }

                if let url = value as? URL {
                    return url.absoluteString
                }
                if let urlString = value as? String, !urlString.isEmpty {
                    return urlString
                }
            }
        }

        for item in extensionItems {
            for attachment in item.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = try? await loadItem(from: attachment, type: .plainText),
                   let text = value as? String {
                    return text
                }
            }

            if let text = item.attributedContentText?.string, !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private func loadItem(from provider: NSItemProvider, type: UTType) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: ShareCaptureError.noText)
                }
            }
        }
    }
}

private enum ShareCaptureError: LocalizedError {
    case noText

    var errorDescription: String? {
        "No shareable text was found."
    }
}
