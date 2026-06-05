@testable import podcasts
import XCTest

final class URLHelperTests: XCTestCase {
    func testTrustedDocumentationAllowsPocketCastsSupportURL() {
        let supportURL = URL(string: "https://support.pocketcasts.com/ios/")!
        let cancelURL = URL(string: "https://support.pocketcasts.com/knowledge-base/how-to-cancel-a-subscription/")!

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: supportURL, context: .trustedDocumentation), .inAppBrowser)
        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: cancelURL, context: .trustedDocumentation), .inAppBrowser)
    }

    func testTrustedDocumentationRejectsUnexpectedHosts() {
        let url = URL(string: "https://example.com/support")!

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .trustedDocumentation), .blocked)
    }

    func testTrustedMarketingAllowsSlumberURL() {
        let url = URL(string: "https://slumberstudios.com/pocketcasts/")!

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .trustedMarketing), .inAppBrowser)
    }

    func testExternalContentAllowsHTTPAndHTTPSInApp() {
        let httpURL = URL(string: "http://example.com/podcast")!
        let httpsURL = URL(string: "https://example.com/podcast")!

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: httpURL, context: .externalContent), .inAppBrowser)
        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: httpsURL, context: .externalContent), .inAppBrowser)
    }

    func testExternalContentRejectsUnsafeSchemesForInAppPresentation() {
        let unsafeURLs = [
            URL(string: "javascript:alert(1)")!,
            URL(string: "file:///private/tmp/test.html")!,
            URL(string: "pocketcasts://podcasts")!,
            URL(string: "example.com/path")!
        ]

        unsafeURLs.forEach {
            XCTAssertFalse(URLHelper.canOpenInAppBrowser($0, context: .externalContent), "\($0) should not open in app")
        }
    }

    func testExternalContentCanRouteMailToExternally() {
        let url = URL(string: "mailto:support@pocketcasts.com")!

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .externalContent), .externalApplication)
    }

    func testExternalContentPreservesExplicitExternalFallbackForCustomSchemes() {
        let url = URL(string: "pocketcasts://podcasts")!

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
        let url = URL(string: "example.com/path")!

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
        let url = URL(string: "https://example.com/podcast")!

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
        let url = URL(string: "https://pocketcasts.com/login")!

        XCTAssertEqual(URLHelper.inAppBrowserDecision(for: url, context: .sensitiveAuth), .authenticationSessionRequired)
    }
}
