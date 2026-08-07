import UIKit
import UniformTypeIdentifiers
import Social

class ShareViewController: UIViewController {

    /// Ordered most-specific first, because the first match wins.
    ///
    /// `.plainText` must precede `.data`: text conforms to `public.data`, so a
    /// shared `.txt`/`.md` would otherwise fall into the catch-all below and be
    /// renamed to `opml.opml`. It is safe ahead of the OPML path because OPML and
    /// XML conform to `public.text` but *not* to `public.plain-text` — they are
    /// siblings, not ancestors.
    private let acceptedTypes: [UTType] = [.audio, .movie, .plainText, .data]

    /// Types the host app should treat as a podcast subscription list.
    private static let opmlIdentifiers = ["unofficial.opml", "public.opml", "org.opml.opml"]

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let content = extensionContext?.inputItems.first as? NSExtensionItem
        guard let attachment = content?.attachments?.first as? NSItemProvider else {
            close()
            return
        }

        if let type = acceptedTypes.first(where: { attachment.hasItemConformingToTypeIdentifier($0.identifier) }) {
            loadFile(from: attachment, identifier: type.identifier, isOPML: Self.isOPML(attachment))
        } else {
            close()
        }
    }

    /// Whether the attachment actually declares itself as OPML, rather than
    /// merely having failed to be anything else.
    private static func isOPML(_ attachment: NSItemProvider) -> Bool {
        opmlIdentifiers.contains { attachment.hasItemConformingToTypeIdentifier($0) }
    }

    func redirectToHostApp(_ url: String) {
        guard let url = URL(string: "thcast://import-file/\(url)") else {
            return
        }

        let context = NSExtensionContext()
        context.open(url as URL, completionHandler: nil)
        var responder = self as UIResponder?

        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
            }
            responder = responder?.next
        }
    }

    private func loadFile(from attachment: NSItemProvider, identifier: String, isOPML: Bool) {
        attachment.loadItem(forTypeIdentifier: identifier, options: nil) { [weak self] data, _ in
            guard let url = data as? URL else {
                Task { @MainActor [weak self] in self?.close() }
                return
            }

            // Save the file to the shared group directory
            let fileManager = FileManager.default
            guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.GroupUserDefaults.groupContainerId) else {
                Task { @MainActor [weak self] in self?.close() }
                return
            }

            // OPML arrives under many extensions (and sometimes none), and the
            // host app routes it by extension — so it is renamed on the way in.
            // Everything else keeps its own name: the name is what the host app
            // shows the user, and for text it is what the document is titled.
            let destURL = isOPML
                ? container.appendingPathComponent("opml.opml")
                : container.appendingPathComponent(url.lastPathComponent)

            do {
                // A previous share of the same name leaves a file behind, and
                // `copyItem` refuses to overwrite. Swallowing that error meant
                // the host app silently re-imported the *older* file.
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: url, to: destURL)
            } catch {
                Task { @MainActor [weak self] in self?.close() }
                return
            }

            // The item-provider callback is off-main; UI/extension work belongs on the main actor
            let destination = destURL.absoluteString
            Task { @MainActor [weak self] in
                self?.close()

                // Redirect to Pocket Casts to handle the file
                self?.redirectToHostApp(destination)
            }
        }
    }

    private func close() {
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
