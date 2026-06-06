@testable import podcasts
import XCTest

final class URLHelperTests: XCTestCase {
    func testTrustedDocumentationAllowsPocketCastsSupportURL() {
        let supportURL = webURL(host: URLFixture.supportHost, path: URLFixture.supportPath)
        let cancelURL = webURL(host: URLFixture.supportHost, path: URLFixture.cancelSubscriptionPath)

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: supportURL, context: .trustedDocumentation), .inAppBrowser)
        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: cancelURL, context: .trustedDocumentation), .inAppBrowser)
    }

    func testTrustedDocumentationRejectsUnexpectedHosts() {
        let url = webURL(host: URLFixture.untrustedHost, path: URLFixture.supportPath)

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .trustedDocumentation), .blocked)
    }

    func testTrustedDocumentationRejectsInsecureSupportURL() {
        let url = webURL(scheme: URLFixture.httpScheme, host: URLFixture.supportHost, path: URLFixture.supportPath)

        XCTAssertFalse(URLHelper.isTrustedDocumentationURL(url))
    }

    func testTrustedDocumentationAllowsStagingSupportURL() {
        let url = webURL(host: URLFixture.stagingSupportHost, path: URLFixture.supportPath)

        XCTAssertTrue(URLHelper.isTrustedDocumentationURL(url))
    }

    func testTrustedMarketingAllowsSlumberURL() {
        let url = webURL(host: URLFixture.slumberHost, path: URLFixture.marketingPath)

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .trustedMarketing), .inAppBrowser)
    }

    func testExternalContentAllowsHTTPSAndBlocksHTTP() {
        let httpURL = webURL(scheme: URLFixture.httpScheme, host: URLFixture.untrustedHost, path: URLFixture.podcastPath)
        let httpsURL = webURL(host: URLFixture.untrustedHost, path: URLFixture.podcastPath)

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: httpURL, context: .externalContent), .blocked)
        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: httpsURL, context: .externalContent), .inAppBrowser)
    }

    func testExternalContentRejectsNonWebURLsForInAppPresentation() {
        let nonWebURLs = [
            customURL(scheme: URLFixture.javascriptScheme, path: URLFixture.scriptPath),
            URLFixture.localFileURL,
            customURL(scheme: URLFixture.appScheme, host: URLFixture.appHost),
            relativeURL(path: URLFixture.relativePath)
        ]

        nonWebURLs.forEach {
            XCTAssertFalse(URLHelper.canOpenInAppBrowser($0, context: .externalContent), "\($0) should not open in app")
        }
    }

    func testExternalContentCanRouteMailToExternally() {
        let url = customURL(scheme: URLFixture.mailtoScheme, path: URLFixture.supportEmail)

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .externalContent), .externalApplication)
    }

    func testExternalContentBlocksCustomSchemesEvenWithExternalBrowserPreference() {
        let url = customURL(scheme: URLFixture.appScheme, host: URLFixture.appHost)

        XCTAssertEqual(
            URLHelper.inAppBrowserDecision(
                for: url,
                context: .externalContent,
                prefersExternalBrowser: true
            ),
            .blocked
        )
    }

    func testExternalContentBlocksRelativeURLsEvenWithExternalBrowserPreference() {
        let url = relativeURL(path: URLFixture.relativePath)

        XCTAssertEqual(
            URLHelper.inAppBrowserDecision(
                for: url,
                context: .externalContent,
                prefersExternalBrowser: true
            ),
            .blocked
        )
    }

    func testExternalPreferenceOpensWebURLExternally() {
        let url = webURL(host: URLFixture.untrustedHost, path: URLFixture.podcastPath)

        XCTAssertEqual(
            URLHelper.inAppBrowserDecision(
                for: url,
                context: .externalContent,
                prefersExternalBrowser: true
            ),
            .externalApplication
        )
    }

    func testEmbeddedContentAllowsLocalDocumentURLs() {
        let bundleURL = URL(fileURLWithPath: Bundle.main.bundlePath)
            .appendingPathComponent(URLFixture.embeddedContentFileName)

        XCTAssertTrue(URLHelper.isAllowedEmbeddedContentNavigationURL(nil))
        XCTAssertTrue(URLHelper.isAllowedEmbeddedContentNavigationURL(customURL(scheme: URLFixture.aboutScheme, path: URLFixture.blankPath)))
        XCTAssertTrue(URLHelper.isAllowedEmbeddedContentNavigationURL(bundleURL))
    }

    func testEmbeddedContentBlocksRemoteAndExternalFileURLs() {
        let remoteURL = webURL(host: URLFixture.untrustedHost, path: URLFixture.redirectPath)
        let externalFileURL = URLFixture.localFileURL

        XCTAssertFalse(URLHelper.isAllowedEmbeddedContentNavigationURL(remoteURL))
        XCTAssertFalse(URLHelper.isAllowedEmbeddedContentNavigationURL(externalFileURL))
    }

    func testShowNotesTimestampValueAllowsGeneratedLocalhostLink() {
        let url = showNotesTimestampURL(timestamp: URLFixture.showNotesTimestamp)

        XCTAssertEqual(URLHelper.showNotesTimestampValue(from: url), URLFixture.showNotesTimestamp)
    }

    func testShowNotesTimestampValueAllowsLocalhostLinkWithoutTrailingSlash() {
        let url = URL(string: "http://localhost#playerJumpTo=\(URLFixture.showNotesTimestamp)")!

        XCTAssertEqual(URLHelper.showNotesTimestampValue(from: url), URLFixture.showNotesTimestamp)
    }

    func testShowNotesTimestampValueRejectsUnexpectedShapes() {
        let urls = [
            showNotesTimestampURL(scheme: URLFixture.httpsScheme),
            showNotesTimestampURL(host: URLFixture.untrustedHost),
            showNotesTimestampURL(path: URLFixture.redirectPath),
            showNotesTimestampURL(fragmentName: URLFixture.redirectFragmentName),
            webURL(host: URLFixture.untrustedHost, path: URLFixture.podcastPath)
        ]

        urls.forEach {
            XCTAssertNil(URLHelper.showNotesTimestampValue(from: $0))
        }
    }

    private func webURL(scheme: String = URLFixture.httpsScheme, host: String, path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        return components.url!
    }

    private func customURL(scheme: String, host: String? = nil, path: String = "") -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        return components.url!
    }

    private func relativeURL(path: String) -> URL {
        var components = URLComponents()
        components.path = path
        return components.url!
    }

    private func showNotesTimestampURL(
        scheme: String = URLFixture.showNotesTimestampScheme,
        host: String = URLFixture.showNotesTimestampHost,
        path: String = URLFixture.rootPath,
        fragmentName: String = URLFixture.showNotesTimestampFragmentName,
        timestamp: String = URLFixture.showNotesTimestamp
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.fragment = [fragmentName, timestamp].joined(separator: URLFixture.fragmentSeparator)
        return components.url!
    }
}

private enum URLFixture {
    static let httpsScheme = "https"
    static let httpScheme = "http"
    static let javascriptScheme = "javascript"
    static let appScheme = "pocketcasts"
    static let mailtoScheme = "mailto"
    static let aboutScheme = "about"
    static let supportHost = "support.pocketcasts.com"
    static let stagingSupportHost = "support.pocketcasts.net"
    static let slumberHost = "slumberstudios.com"
    static let untrustedHost = "example.com"
    static let appHost = "podcasts"
    static let supportPath = path("ios", trailingSlash: true)
    static let cancelSubscriptionPath = path(
        "knowledge-base",
        "how-to-cancel-a-subscription",
        trailingSlash: true
    )
    static let marketingPath = path("pocketcasts", trailingSlash: true)
    static let podcastPath = path("podcast")
    static let scriptPath = "alert(1)"
    static let localFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(embeddedContentFileName)
    static let relativePath = [untrustedHost, "path"].joined(separator: pathSeparator)
    static let supportEmail = "support@pocketcasts.com"
    static let blankPath = "blank"
    static let redirectPath = path("redirect")
    static let embeddedContentFileName = "embedded-content.html"
    static let rootPath = path()
    static let showNotesTimestampScheme = "http"
    static let showNotesTimestampHost = "localhost"
    static let showNotesTimestampFragmentName = "playerJumpTo"
    static let redirectFragmentName = "redirect"
    static let showNotesTimestamp = "57:00"
    static let fragmentSeparator = "="

    private static let pathSeparator = "/"

    private static func path(_ components: String..., trailingSlash: Bool = false) -> String {
        guard !components.isEmpty else {
            return pathSeparator
        }

        var path = pathSeparator + components.joined(separator: pathSeparator)
        if trailingSlash {
            path += pathSeparator
        }
        return path
    }
}
