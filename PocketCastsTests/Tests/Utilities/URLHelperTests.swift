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
            URL(fileURLWithPath: URLFixture.localFilePath),
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
        let externalFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(URLFixture.embeddedContentFileName)

        XCTAssertFalse(URLHelper.isAllowedEmbeddedContentNavigationURL(remoteURL))
        XCTAssertFalse(URLHelper.isAllowedEmbeddedContentNavigationURL(externalFileURL))
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
    static let supportPath = "/ios/"
    static let cancelSubscriptionPath = "/knowledge-base/how-to-cancel-a-subscription/"
    static let marketingPath = "/pocketcasts/"
    static let podcastPath = "/podcast"
    static let scriptPath = "alert(1)"
    static let localFilePath = "/private/tmp/test.html"
    static let relativePath = "example.com/path"
    static let supportEmail = "support@pocketcasts.com"
    static let blankPath = "blank"
    static let redirectPath = "/redirect"
    static let embeddedContentFileName = "embedded-content.html"
}
