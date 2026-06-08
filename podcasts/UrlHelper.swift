import Foundation
import PocketCastsUtils
import SafariServices
import UIKit

struct URLHelper {
    enum InAppBrowserContext: Equatable {
        case trustedDocumentation
        case externalContent
    }

    enum InAppBrowserDecision: Equatable {
        case inAppBrowser
        case externalApplication
        case blocked
    }

    struct OpenOptions {
        var presenter: UIViewController?
        var prefersExternalBrowser: Bool
        var delegate: SFSafariViewControllerDelegate?
        var modalPresentationStyle: UIModalPresentationStyle?
        var completion: (() -> Void)?

        init(
            presenter: UIViewController? = nil,
            prefersExternalBrowser: Bool = false,
            delegate: SFSafariViewControllerDelegate? = nil,
            modalPresentationStyle: UIModalPresentationStyle? = nil,
            completion: (() -> Void)? = nil
        ) {
            self.presenter = presenter
            self.prefersExternalBrowser = prefersExternalBrowser
            self.delegate = delegate
            self.modalPresentationStyle = modalPresentationStyle
            self.completion = completion
        }
    }

    // Trusted contexts block any HTTPS host not listed here. Add new hosts before
    // routing links through `.trustedDocumentation`.
    private static let trustedDocumentationHosts: Set<String> = [
        "support.pocketcasts.com",
        "support.pocketcasts.net",
        "pocketcasts.com",
        "www.pocketcasts.com",
        "pocketcasts.net",
        "www.pocketcasts.net"
    ]

    private static let showNotesTimestampScheme = "http"
    private static let showNotesTimestampHost = "localhost"
    private static let showNotesTimestampFragmentName = "playerJumpTo"

    static func isMailtoScheme(_ scheme: String?) -> Bool {
        guard let scheme else { return false }

        return scheme.caseInsensitiveCompare("mailto") == .orderedSame
    }

    static func isWebURL(_ url: URL) -> Bool {
        isHTTPSURL(url)
    }

    static func isAllowedEmbeddedContentNavigationURL(_ url: URL?) -> Bool {
        guard let url else { return true }

        if let scheme = url.scheme?.lowercased(), ["about", "applewebdata"].contains(scheme) {
            return true
        }

        guard url.isFileURL else { return false }

        let bundlePath = URL(fileURLWithPath: Bundle.main.bundlePath, isDirectory: true).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == bundlePath || path.hasPrefix(bundlePath + "/")
    }

    static func canOpenInAppBrowser(_ url: URL, context: InAppBrowserContext) -> Bool {
        inAppBrowserDecision(for: url, context: context) == .inAppBrowser
    }

    static func isAllowedExternalContentLink(_ url: URL) -> Bool {
        inAppBrowserDecision(for: url, context: .externalContent) != .blocked
    }

    static func showNotesTimestampValue(from url: URL) -> String? {
        guard url.scheme?.caseInsensitiveCompare(showNotesTimestampScheme) == .orderedSame,
              host(for: url) == showNotesTimestampHost,
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.path == "/" || url.path.isEmpty,
              url.query == nil,
              let fragment = url.fragment
        else {
            return nil
        }

        let components = fragment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0] == showNotesTimestampFragmentName,
              !components[1].isEmpty
        else {
            return nil
        }

        return String(components[1])
    }

    static func inAppBrowserDecision(
        for url: URL,
        context: InAppBrowserContext,
        prefersExternalBrowser: Bool = false
    ) -> InAppBrowserDecision {
        switch context {
        case .trustedDocumentation:
            guard isTrustedDocumentationURL(url) else { return .blocked }
            return prefersExternalBrowser ? .externalApplication : .inAppBrowser
        case .externalContent:
            return externalContentDecision(
                for: url,
                prefersExternalBrowser: prefersExternalBrowser
            )
        }
    }

    static func makeInAppBrowser(for url: URL, context: InAppBrowserContext) -> SFSafariViewController? {
        guard canOpenInAppBrowser(url, context: context) else { return nil }

        return SFSafariViewController(with: url)
    }

    @discardableResult
    static func open(
        _ url: URL,
        context: InAppBrowserContext,
        options: OpenOptions = OpenOptions()
    ) -> SFSafariViewController? {
        switch inAppBrowserDecision(
            for: url,
            context: context,
            prefersExternalBrowser: options.prefersExternalBrowser
        ) {
        case .inAppBrowser:
            guard let safariViewController = makeInAppBrowser(for: url, context: context) else { return nil }
            let presenter = options.presenter ?? SceneHelper.rootViewController()
            guard let presenter else { return nil }

            safariViewController.delegate = options.delegate
            if let modalPresentationStyle = options.modalPresentationStyle {
                safariViewController.modalPresentationStyle = modalPresentationStyle
            }
            presenter.present(safariViewController, animated: true, completion: options.completion)
            return safariViewController
        case .externalApplication:
            UIApplication.shared.open(url, options: [:]) { _ in
                options.completion?()
            }
            return nil
        case .blocked:
            FileLog.shared.addMessage("URLHelper blocked unsupported URL for \(context): \(redactedURLDescription(url))")
            return nil
        }
    }

    private static func externalContentDecision(
        for url: URL,
        prefersExternalBrowser: Bool
    ) -> InAppBrowserDecision {
        if isWebURL(url) {
            return prefersExternalBrowser ? .externalApplication : .inAppBrowser
        }

        if isMailtoScheme(url.scheme) {
            return .externalApplication
        }

        return .blocked
    }

    static func isTrustedDocumentationURL(_ url: URL) -> Bool {
        isHTTPSURL(url) && host(for: url).map(trustedDocumentationHosts.contains) == true
    }

    private static func isHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("https") == .orderedSame
    }

    private static func host(for url: URL) -> String? {
        url.host?.lowercased()
    }

    private static func redactedURLDescription(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme
        else {
            return "relative-url"
        }

        guard let host = components.host else {
            return scheme
        }

        return "\(scheme)://\(host)"
    }
}
