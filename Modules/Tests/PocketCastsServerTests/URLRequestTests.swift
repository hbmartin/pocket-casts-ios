import Foundation
@testable import PocketCastsServer
import XCTest

class URLRequestTests: XCTestCase {

    override class func tearDown() {
        LocalizationHelper.provider = nil
        super.tearDown()
    }

    func testURLRequestLocalizationHeaders() throws {
        let provider = InternationalizationProvider(
            userRegion: "en",
            appLanguage: "en-US"
        )
        LocalizationHelper.provider = provider

        // Resolve the first-party host through ServerConstants so the test holds
        // regardless of which origin (hosted, loopback override, or blocked
        // fallback) the test process resolves.
        let url = try XCTUnwrap(URL(string: ServerConstants.Urls.api()))
        var request = URLRequest(url: url)
        request.addLocalizationHeaders()

        XCTAssertEqual(request.value(forHTTPHeaderField: ServerConstants.HttpHeaders.userRegion), "en")
        XCTAssertEqual(request.value(forHTTPHeaderField: ServerConstants.HttpHeaders.appLanguage), "en-US")

        let externalURL = try XCTUnwrap(URL(string: "https://example.com/"))
        var newRequest = URLRequest(url: externalURL)
        newRequest.addLocalizationHeaders()

        XCTAssertNil(newRequest.value(forHTTPHeaderField: ServerConstants.HttpHeaders.userRegion))
        XCTAssertNil(newRequest.value(forHTTPHeaderField: ServerConstants.HttpHeaders.appLanguage))
    }
}
