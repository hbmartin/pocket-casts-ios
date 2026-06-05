import Foundation
import SafariServices
import UIKit

struct URLHelper {
    enum InAppBrowserContext: Equatable {
        case trustedDocumentation
        case trustedMarketing
        case externalContent
        case sensitiveAuth
    }

    enum InAppBrowserDecision: Equatable {
        case inAppBrowser
        case externalApplication
        case blocked
        case authenticationSessionRequired
    }

    private static let trustedDocumentationHosts: Set<String> = [
        "support.pocketcasts.com",
        "support.pocketcasts.net",
        "pocketcasts.com",
        "www.pocketcasts.com",
        "pocketcasts.net",
        "www.pocketcasts.net"
    ]

    private static let trustedMarketingHosts: Set<String> = [
        "slumberstudios.com",
        "www.slumberstudios.com"
    ]

    private static let blockedExternalSchemes: Set<String> = [
        "about",
        "blob",
        "data",
        "file",
        "javascript"
    ]

    static func isValidScheme(_ scheme: String?) -> Bool {
        guard let scheme else { return false }

        return ((scheme.caseInsensitiveCompare("http") == .orderedSame) || (scheme.caseInsensitiveCompare("https") == .orderedSame))
    }

    static func isMailtoScheme(_ scheme: String?) -> Bool {
        guard let scheme else { return false }

        return scheme.caseInsensitiveCompare("mailto") == .orderedSame
    }

    static func isWebURL(_ url: URL) -> Bool {
        isValidScheme(url.scheme)
    }

    static func canOpenInAppBrowser(_ url: URL, context: InAppBrowserContext) -> Bool {
        inAppBrowserDecision(for: url, context: context) == .inAppBrowser
    }

    static func inAppBrowserDecision(
        for url: URL,
        context: InAppBrowserContext,
        prefersExternalBrowser: Bool = false,
        allowsExternalFallback: Bool = false
    ) -> InAppBrowserDecision {
        switch context {
        case .trustedDocumentation:
            guard isTrustedDocumentationURL(url) else { return .blocked }
            return prefersExternalBrowser ? .externalApplication : .inAppBrowser
        case .trustedMarketing:
            guard isTrustedMarketingURL(url) else { return .blocked }
            return prefersExternalBrowser ? .externalApplication : .inAppBrowser
        case .externalContent:
            return externalContentDecision(
                for: url,
                prefersExternalBrowser: prefersExternalBrowser,
                allowsExternalFallback: allowsExternalFallback
            )
        case .sensitiveAuth:
            return .authenticationSessionRequired
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
        from presenter: UIViewController? = SceneHelper.rootViewController(),
        prefersExternalBrowser: Bool = false,
        allowsExternalFallback: Bool = false,
        delegate: SFSafariViewControllerDelegate? = nil,
        modalPresentationStyle: UIModalPresentationStyle? = nil,
        completion: (() -> Void)? = nil
    ) -> SFSafariViewController? {
        switch inAppBrowserDecision(
            for: url,
            context: context,
            prefersExternalBrowser: prefersExternalBrowser,
            allowsExternalFallback: allowsExternalFallback
        ) {
        case .inAppBrowser:
            guard let safariViewController = makeInAppBrowser(for: url, context: context), let presenter else { return nil }

            safariViewController.delegate = delegate
            if let modalPresentationStyle {
                safariViewController.modalPresentationStyle = modalPresentationStyle
            }
            presenter.present(safariViewController, animated: true, completion: completion)
            return safariViewController
        case .externalApplication:
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return nil
        case .blocked, .authenticationSessionRequired:
            return nil
        }
    }

    private static func externalContentDecision(
        for url: URL,
        prefersExternalBrowser: Bool,
        allowsExternalFallback: Bool
    ) -> InAppBrowserDecision {
        guard let scheme = url.scheme else {
            return .blocked
        }

        if isBlockedExternalScheme(scheme) {
            return .blocked
        }

        if isWebURL(url) {
            return prefersExternalBrowser ? .externalApplication : .inAppBrowser
        }

        if isMailtoScheme(url.scheme) {
            return .externalApplication
        }

        return allowsExternalFallback ? .externalApplication : .blocked
    }

    private static func isTrustedDocumentationURL(_ url: URL) -> Bool {
        isHTTPSURL(url) && host(for: url).map(trustedDocumentationHosts.contains) == true
    }

    private static func isTrustedMarketingURL(_ url: URL) -> Bool {
        isHTTPSURL(url) && host(for: url).map(trustedMarketingHosts.contains) == true
    }

    private static func isHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("https") == .orderedSame
    }

    private static func isBlockedExternalScheme(_ scheme: String?) -> Bool {
        guard let scheme else { return false }

        return blockedExternalSchemes.contains(scheme.lowercased())
    }

    private static func host(for url: URL) -> String? {
        url.host?.lowercased()
    }
}
