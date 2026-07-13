import Foundation
@testable import PocketCastsServer
@testable import PocketCastsUtils
import Synchronization
import XCTest

final class SharingServerHandlerTests: XCTestCase {
    private var previousKeychainStore: KeychainStoring!

    override func setUp() {
        super.setUp()
        previousKeychainStore = KeychainHelper.store
        KeychainHelper.store = InMemoryKeychainStore()
    }

    override func tearDown() {
        FeatureFlagMock().reset()
        KeychainHelper.store = previousKeychainStore
        super.tearDown()
    }

    // M3: this legacy-signature contract test is deleted together with
    // legacySharingServerSignature when the sharing server's dual-accept window
    // closes — plans/API Auth Hardening Plan.md §3.4.
    func testLegacySharingServerSignatureMatchesServerContract() {
        XCTAssertEqual(
            SharingServerHandler.legacySharingServerSignature(
                for: "20240601123456",
                credential: "legacy-shared-secret"
            ),
            "d802d44e483484bf621d7e165bc3dc9d5a160415"
        )
    }

    // MARK: - Bearer path (FeatureFlag.sharingListBearerAuth on)

    func testShareListWithBearerFlagOnSendsAuthorizationAndNoLegacyParams() throws {
        FeatureFlagMock().set(.sharingListBearerAuth, value: true)
        signIn(token: "test-access-token")

        let capturedRequest = Mutex<URLRequest?>(nil)
        let handler = SharingServerHandler(
            tokenHelper: TokenHelper(urlConnection: URLConnection(mockHandler: { request in
                capturedRequest.withLock { $0 = request }
                return (Self.shareListResponseBody(shareUrl: "https://lists.pocketcasts.com/test-list"), Self.okResponse(for: request))
            })),
            urlConnection: URLConnection(mockHandler: { _ in
                XCTFail("The legacy transport must not be used while the bearer flag is on")
                throw URLError(.badURL)
            })
        )

        let shareUrl = shareList(with: handler)

        XCTAssertEqual(shareUrl, "https://lists.pocketcasts.com/test-list")

        let request = try XCTUnwrap(capturedRequest.withLock { $0 })
        XCTAssertEqual(request.url?.absoluteString.hasSuffix("share/list"), true)
        XCTAssertEqual(request.value(forHTTPHeaderField: ServerConstants.HttpHeaders.authorization), "Bearer test-access-token")

        let body = try Self.bodyJSON(of: request)
        XCTAssertEqual(body["title"] as? String, "My list")
        XCTAssertNil(body["datetime"], "The bearer path must not attach the legacy timestamp param")
        XCTAssertNil(body["h"], "The bearer path must not attach the legacy static-secret signature")
    }

    func testShareListWithBearerFlagOnFailsWithoutTouchingNetworkWhenSignedOut() {
        FeatureFlagMock().set(.sharingListBearerAuth, value: true)
        // No syncing email in the keychain: SyncManager.isUserLoggedIn() is false.

        let handler = SharingServerHandler(
            tokenHelper: TokenHelper(urlConnection: URLConnection(mockHandler: { _ in
                XCTFail("Signed-out sharing must not hit the network on the bearer path")
                throw URLError(.badURL)
            })),
            urlConnection: URLConnection(mockHandler: { _ in
                XCTFail("Signed-out sharing must not hit the network on the bearer path")
                throw URLError(.badURL)
            })
        )

        guard case .requiresSignIn = shareListResult(with: handler) else {
            XCTFail("Signed-out sharing on the bearer path must surface .requiresSignIn so the UI can route to sign-in")
            return
        }
    }

    // MARK: - Legacy path (FeatureFlag.sharingListBearerAuth off)

    func testShareListWithBearerFlagOffSendsLegacySignatureAndNoAuthorization() throws {
        FeatureFlagMock().set(.sharingListBearerAuth, value: false)
        signIn(token: "test-access-token")

        let capturedRequest = Mutex<URLRequest?>(nil)
        let handler = SharingServerHandler(
            tokenHelper: TokenHelper(urlConnection: URLConnection(mockHandler: { _ in
                XCTFail("The bearer transport must not be used while the flag is off")
                throw URLError(.badURL)
            })),
            urlConnection: URLConnection(mockHandler: { request in
                capturedRequest.withLock { $0 = request }
                return (Self.shareListResponseBody(shareUrl: "https://lists.pocketcasts.com/legacy-list"), Self.okResponse(for: request))
            })
        )

        let shareUrl = shareList(with: handler)

        XCTAssertEqual(shareUrl, "https://lists.pocketcasts.com/legacy-list")

        let request = try XCTUnwrap(capturedRequest.withLock { $0 })
        XCTAssertEqual(request.url?.absoluteString.hasSuffix("share/list"), true)
        XCTAssertNil(request.value(forHTTPHeaderField: ServerConstants.HttpHeaders.authorization), "The legacy path must not attach a bearer token")

        let body = try Self.bodyJSON(of: request)
        XCTAssertEqual(body["title"] as? String, "My list")

        let datetime = try XCTUnwrap(body["datetime"] as? String)
        XCTAssertEqual(datetime.count, 14, "Legacy timestamp param must keep the yyyyMMddHHmmss format")
        XCTAssertEqual(body["h"] as? String, SharingServerHandler.legacySharingServerSignature(for: datetime))
    }

    // MARK: - Helpers

    private func signIn(token: String) {
        KeychainHelper.save(string: "share-test@example.com", key: ServerConstants.Values.syncingEmailKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)
        KeychainHelper.save(string: token, key: ServerConstants.Values.syncingV2TokenKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    private func shareList(with handler: SharingServerHandler) -> String? {
        if case .shared(let url) = shareListResult(with: handler) {
            return url
        }
        return nil
    }

    private func shareListResult(with handler: SharingServerHandler) -> SharingServerHandler.PodcastShareListResult {
        let listInfo = SharingServerHandler.PodcastShareInfo(title: "My list", description: "A few favorites", podcasts: ["uuid-1", "uuid-2"])
        let received = Mutex<SharingServerHandler.PodcastShareListResult>(.failed)
        let shareCompleted = expectation(description: "share completes")

        handler.sharePodcastList(listInfo: listInfo) { result in
            received.withLock { $0 = result }
            shareCompleted.fulfill()
        }

        wait(for: [shareCompleted], timeout: 5)
        return received.withLock { $0 }
    }

    private static func okResponse(for request: URLRequest) -> HTTPURLResponse? {
        request.url.flatMap { HTTPURLResponse(url: $0, statusCode: 200, httpVersion: nil, headerFields: nil) }
    }

    private static func shareListResponseBody(shareUrl: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["status": "ok", "result": ["share_url": shareUrl]])
    }

    private static func bodyJSON(of request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}
