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
        attachment.loadItem(forTypeIdentifier: identifier, options: nil) { [weak self] item, _ in
            // Save the file to the shared group directory. Every hand-off gets an
            // immutable directory of its own: the host may leave its review sheet
            // open while another share arrives, and reusing a filename would let
            // the later share change the bytes the first sheet commits.
            let fileManager = FileManager.default
            guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.GroupUserDefaults.groupContainerId) else {
                Task { @MainActor [weak self] in self?.close() }
                return
            }

            let stagingDirectory = container
                .appendingPathComponent("share-imports", isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)

            do {
                try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

                let destination: URL
                if isOPML {
                    destination = stagingDirectory.appendingPathComponent("opml.opml")
                } else if let sourceURL = item as? URL {
                    destination = stagingDirectory.appendingPathComponent(sourceURL.lastPathComponent)
                } else {
                    destination = stagingDirectory.appendingPathComponent("Shared Text.txt")
                }

                switch item {
                case let sourceURL as URL:
                    try fileManager.copyItem(at: sourceURL, to: destination)
                case let string as String:
                    try Data(string.utf8).write(to: destination, options: .atomic)
                case let attributed as NSAttributedString:
                    try Data(attributed.string.utf8).write(to: destination, options: .atomic)
                case let data as Data:
                    try data.write(to: destination, options: .atomic)
                default:
                    throw CocoaError(.fileReadUnknown)
                }

                Task { @MainActor [weak self] in
                    self?.close()
                    self?.redirectToHostApp(destination.absoluteString)
                }
            } catch {
                try? fileManager.removeItem(at: stagingDirectory)
                Task { @MainActor [weak self] in self?.close() }
            }
        }
    }

    private func close() {
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
