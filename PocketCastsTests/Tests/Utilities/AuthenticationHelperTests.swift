import Foundation
import XCTest
@testable import podcasts
@testable import PocketCastsServer
@testable import PocketCastsUtils

/// Covers the credential-persistence guards in AuthenticationHelper (plan C.0-1/C.0-2):
/// an omitted/empty refresh token from the server must never clobber the stored one,
/// and expires_in must round-trip into the expiry hint.
@MainActor
final class AuthenticationHelperTests: XCTestCase {
    private var previousKeychainStore: KeychainStoring!

    override func setUp() {
        super.setUp()
        previousKeychainStore = KeychainHelper.store
        KeychainHelper.store = InMemoryKeychainStore()
        ServerSettings.setTokenExpiryDate(nil)
    }

    override func tearDown() {
        ServerSettings.setTokenExpiryDate(nil)
        KeychainHelper.store = previousKeychainStore
        super.tearDown()
    }

    func testEmptyRefreshTokenIsNotPersisted() throws {
        ServerSettings.setRefreshToken("keep-me")

        // An Api_TokenLoginResponse with an omitted refresh_token decodes to "" and maps to nil.
        var proto = Api_TokenLoginResponse()
        proto.accessToken = "fresh-token"
        proto.refreshToken = ""
        proto.uuid = "uuid"
        let response = AuthenticationResponse(from: proto)
        XCTAssertNil(response.refreshToken, "An empty proto refresh token must map to nil")

        AuthenticationHelper.persistSignInCredentials(from: response)

        XCTAssertEqual(ServerSettings.syncingV2Token, "fresh-token")
        XCTAssertEqual(try ServerSettings.refreshToken(), "keep-me", "The guarded write must keep the previous refresh token")
    }

    func testNonEmptyRefreshTokenIsPersisted() throws {
        ServerSettings.setRefreshToken("old-refresh")

        var proto = Api_TokenLoginResponse()
        proto.accessToken = "fresh-token"
        proto.refreshToken = "new-refresh"
        proto.uuid = "uuid"

        AuthenticationHelper.persistSignInCredentials(from: AuthenticationResponse(from: proto))

        XCTAssertEqual(try ServerSettings.refreshToken(), "new-refresh")
    }

    func testExpiresInPersistsExpiryHintAndAbsenceClearsIt() throws {
        var proto = Api_TokenLoginResponse()
        proto.accessToken = "fresh-token"
        proto.expiresIn = 3600

        AuthenticationHelper.persistSignInCredentials(from: AuthenticationResponse(from: proto))

        let expiry = try XCTUnwrap(ServerSettings.tokenExpiryDate())
        XCTAssertEqual(expiry.timeIntervalSinceNow, 3300, accuracy: 5)

        // A later response without expires_in clears the stale hint (today's behavior).
        var protoWithoutExpiry = Api_TokenLoginResponse()
        protoWithoutExpiry.accessToken = "newer-token"

        AuthenticationHelper.persistSignInCredentials(from: AuthenticationResponse(from: protoWithoutExpiry))

        XCTAssertNil(ServerSettings.tokenExpiryDate())
    }
}
