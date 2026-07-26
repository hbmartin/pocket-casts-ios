import Foundation
@testable import PocketCastsServer
import XCTest

final class AppAttestCanonicalRequestTests: XCTestCase {
    func testCanonicalizesMethodPathDuplicateQueryAndExactBody() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://podcasts.example/api/v1/resource?b=2&a=hello+world&a=1")))
        request.httpMethod = "post"
        request.httpBody = Data("hello".utf8)

        let canonical = try AppAttestCanonicalRequest.data(for: request)
        XCTAssertEqual(
            String(decoding: canonical, as: UTF8.self),
            "v1\nPOST\n/api/v1/resource\na=1&a=hello%20world&b=2\n2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testSortsByEncodedKeyThenValue() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://podcasts.example/folders?z=1&%C3%A4=2&a=3&a=2")))
        request.httpMethod = "GET"
        let canonical = String(decoding: try AppAttestCanonicalRequest.data(for: request), as: UTF8.self)
        XCTAssertTrue(canonical.contains("\n%C3%A4=2&a=2&a=3&z=1\n"))
    }

    func testRejectsAmbiguousNonCanonicalPaths() throws {
        for value in [
            "https://podcasts.example/a//b",
            "https://podcasts.example/a/../b",
            "https://podcasts.example/a%2Fb",
        ] {
            let request = URLRequest(url: try XCTUnwrap(URL(string: value)))
            XCTAssertThrowsError(try AppAttestCanonicalRequest.data(for: request), value)
        }
    }

    func testRoutePolicyMatchesPublicAndNativeAttestedContracts() throws {
        let origin = try XCTUnwrap(URL(string: "https://podcasts.example/"))
        for path in [
            "/livez", "/health.html", "/discover/ios/content_v3.json",
            "/podcasts/search", "/mobile/show_notes/full/podcast", "/share/list/code",
        ] {
            let request = URLRequest(url: try XCTUnwrap(URL(string: path, relativeTo: origin)?.absoluteURL))
            XCTAssertFalse(AppAttestRoutePolicy.requiresAttestation(request, origin: origin), path)
        }

        for path in [
            "/user/login", "/api/v1/capabilities", "/api/v1/update_podcast",
            "/podcast/suggest_folders", "/recommendations/podcast/id", "/corpus/episodes/id/manifest",
        ] {
            let request = URLRequest(url: try XCTUnwrap(URL(string: path, relativeTo: origin)?.absoluteURL))
            XCTAssertTrue(AppAttestRoutePolicy.requiresAttestation(request, origin: origin), path)
        }

        var authenticatedPublicRequest = URLRequest(url: try XCTUnwrap(URL(string: "/discover/ios/content_v3.json", relativeTo: origin)?.absoluteURL))
        authenticatedPublicRequest.setValue("Bearer token", forHTTPHeaderField: ServerConstants.HttpHeaders.authorization)
        XCTAssertTrue(AppAttestRoutePolicy.requiresAttestation(authenticatedPublicRequest, origin: origin))
    }
}
