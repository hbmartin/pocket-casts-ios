@testable import podcasts
import XCTest

final class URLHelperTests: XCTestCase {
    func testTrustedDocumentationAllowsPocketCastsSupportURL() {
        let supportURL = webURL(host: "support.pocketcasts.com", path: "/ios/")
        let cancelURL = webURL(host: "support.pocketcasts.com", path: "/knowledge-base/how-to-cancel-a-subscription/")

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: supportURL, context: .trustedDocumentation), .inAppBrowser)
        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: cancelURL, context: .trustedDocumentation), .inAppBrowser)
    }

    func testTrustedDocumentationRejectsUnexpectedHosts() {
        let url = webURL(host: "example.com", path: "/support")

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .trustedDocumentation), .blocked)
    }

    func testTrustedDocumentationRejectsInsecureSupportURL() {
        let url = webURL(scheme: "http", host: "support.pocketcasts.com", path: "/ios/")

        XCTAssertFalse(URLHelper.isTrustedDocumentationURL(url))
    }

    func testTrustedDocumentationAllowsStagingSupportURL() {
        let url = webURL(host: "support.pocketcasts.net", path: "/ios/")

        XCTAssertTrue(URLHelper.isTrustedDocumentationURL(url))
    }

    func testTrustedMarketingAllowsSlumberURL() {
        let url = webURL(host: "slumberstudios.com", path: "/pocketcasts/")

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .trustedMarketing), .inAppBrowser)
    }

    func testExternalContentAllowsHTTPAndHTTPSInApp() {
        let httpURL = webURL(scheme: "http", host: "example.com", path: "/podcast")
        let httpsURL = webURL(host: "example.com", path: "/podcast")

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: httpURL, context: .externalContent), .inAppBrowser)
        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: httpsURL, context: .externalContent), .inAppBrowser)
    }

    func testExternalContentRejectsUnsafeSchemesForInAppPresentation() {
        let unsafeURLs = [
            customURL(scheme: "javascript", path: "alert(1)"),
            URL(fileURLWithPath: "/private/tmp/test.html"),
            customURL(scheme: "pocketcasts", host: "podcasts"),
            relativeURL(path: "example.com/path")
        ]

        unsafeURLs.forEach {
            XCTAssertFalse(URLHelper.canOpenInAppBrowser($0, context: .externalContent), "\($0) should not open in app")
        }
    }

    func testExternalContentCanRouteMailToExternally() {
        let url = customURL(scheme: "mailto", path: "support@pocketcasts.com")

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .externalContent), .externalApplication)
    }

    func testExternalContentPreservesExplicitExternalFallbackForCustomSchemes() {
        let url = customURL(scheme: "pocketcasts", host: "podcasts")

        XCTAssertEqual(
            URLHelper.inAppBrowserDecision(
                for: url,
                context: .externalContent,
                allowsExternalFallback: true
            ),
            .externalApplication
        )
    }

    func testExternalContentBlocksRelativeURLsEvenWithExternalFallback() {
        let url = relativeURL(path: "example.com/path")

        XCTAssertEqual(
            URLHelper.inAppBrowserDecision(
                for: url,
                context: .externalContent,
                allowsExternalFallback: true
            ),
            .blocked
        )
    }

    func testExternalPreferenceOpensWebURLExternally() {
        let url = webURL(host: "example.com", path: "/podcast")

        XCTAssertEqual(
            URLHelper.inAppBrowserDecision(
                for: url,
                context: .externalContent,
                prefersExternalBrowser: true,
                allowsExternalFallback: true
            ),
            .externalApplication
        )
    }

    func testSensitiveAuthRequiresAuthenticationSession() {
        let url = webURL(host: "pocketcasts.com", path: "/login")

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .sensitiveAuth), .authenticationSessionRequired)
    }

    private func webURL(scheme: String = "https", host: String, path: String) -> URL {
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
