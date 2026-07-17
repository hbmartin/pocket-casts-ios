import Foundation
@testable import PocketCastsServer
import XCTest

final class ServerConstantsLocalBackendTests: XCTestCase {
    func testLocalBackendRoutesSupportedHostsThroughNormalizedBaseURL() {
        let endpoints = ServerConstants.Urls.resolvedEndpoints(
            production: false,
            localBaseURL: "  HTTP://127.0.0.1:8000  "
        )

        XCTAssertEqual(endpoints.main, "http://127.0.0.1:8000/")
        XCTAssertEqual(endpoints.api, "http://127.0.0.1:8000/")
        XCTAssertEqual(endpoints.cache, "http://127.0.0.1:8000/")
        XCTAssertEqual(endpoints.sharing, "http://127.0.0.1:8000/")
        XCTAssertEqual(endpoints.discover, "http://127.0.0.1:8000/discover/")
        XCTAssertEqual(endpoints.image, "http://127.0.0.1:8000/")
        XCTAssertEqual(endpoints.search, "http://127.0.0.1:8000/")
    }

    func testLocalBackendPreservesHostedUnsupportedServices() {
        let endpoints = ServerConstants.Urls.resolvedEndpoints(
            production: false,
            localBaseURL: "http://127.0.0.1:8000/"
        )

        XCTAssertEqual(endpoints.share, "https://pcast.pocketcasts.net/")
        XCTAssertEqual(endpoints.lists, "https://lists.pocketcasts.net/")
        XCTAssertEqual(endpoints.generatedTranscripts, "https://shownotes.pocketcasts.net/generated_transcripts/")
        XCTAssertEqual(endpoints.tvPair, "https://pocketcasts.net/pair")
        XCTAssertEqual(endpoints.tvCreate, "https://pocketcasts.net/create")
    }

    func testLocalBackendPreservesPathAndNormalizesTrailingSlash() {
        XCTAssertEqual(
            ServerConstants.Urls.normalizedLocalBaseURL("https://localhost:8443/backend"),
            "https://localhost:8443/backend/"
        )
        XCTAssertEqual(
            ServerConstants.Urls.normalizedLocalBaseURL("https://localhost:8443/backend/"),
            "https://localhost:8443/backend/"
        )
    }

    func testInvalidLocalBackendURLsFallBackToHostedEndpoints() {
        let invalidValues: [String?] = [
            nil,
            "",
            "localhost:8000",
            "ftp://localhost:8000",
            "http:///missing-host",
            "http://user:password@localhost:8000",
            "http://localhost:8000?query=value",
            "http://localhost:8000/#fragment",
        ]

        for value in invalidValues {
            let endpoints = ServerConstants.Urls.resolvedEndpoints(
                production: true,
                localBaseURL: value
            )

            XCTAssertEqual(endpoints.main, "https://refresh.pocketcasts.com/", "Unexpected override for \(String(describing: value))")
            XCTAssertEqual(endpoints.api, "https://api.pocketcasts.com/", "Unexpected override for \(String(describing: value))")
            XCTAssertEqual(endpoints.search, "https://search.pocketcasts.com/", "Unexpected override for \(String(describing: value))")
        }
    }
}
