import Foundation
import XCTest
@testable import podcasts
@testable import PocketCastsServer
@testable import PocketCastsUtils

private final class RejectingRefreshTokenKeychainStore: KeychainStoring, Sendable {
    private let underlying = InMemoryKeychainStore()

    @discardableResult
    func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool {
        guard key != ServerConstants.Values.refreshTokenKey else {
            return false
        }

        return underlying.save(value: value, key: key, accessibility: accessibility)
    }

    func string(for key: String) throws -> String? {
        try underlying.string(for: key)
    }
}

/// Covers the credential-persistence guards in AuthenticationHelper (plan C.0-1/C.0-2):
/// an omitted/empty refresh token from the server must never clobber the stored one,
/// and expires_in must round-trip into the expiry hint.
@MainActor
final class AuthenticationHelperTests: XCTestCase {
    private var previousKeychainStore: KeychainStoring!
    private let flagMock = FeatureFlagMock()

    override func setUp() {
        super.setUp()
        previousKeychainStore = KeychainHelper.store
        KeychainHelper.store = InMemoryKeychainStore()
        ServerSettings.userId = nil
        ServerSettings.setTokenExpiryDate(nil)
        ServerSettings.accountAuthMethod = nil
    }

    override func tearDown() {
        SyncManager.clearTokensFromKeyChain()
        ServerSettings.userId = nil
        ServerSettings.setTokenExpiryDate(nil)
        ServerSettings.accountAuthMethod = nil
        flagMock.reset()
        KeychainHelper.store = previousKeychainStore
        super.tearDown()
    }

    func testFlagOnRequiresNonEmptyRefreshTokenBeforePasswordSignInCanSucceed() {
        flagMock.set(.refreshTokenForPasswordAuth, value: true)

        let valid = AuthenticationResponse(
            token: "access",
            uuid: "uuid",
            email: "test@example.com",
            refreshToken: "refresh",
            isNewAccount: false,
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        XCTAssertNoThrow(try AuthenticationHelper.validatePasswordSignInResponse(valid))

        let omitted = AuthenticationResponse(token: "access", uuid: "uuid", email: "test@example.com", refreshToken: nil, isNewAccount: false, expiresIn: nil, tokenType: nil)
        XCTAssertThrowsError(try AuthenticationHelper.validatePasswordSignInResponse(omitted)) { error in
            XCTAssertEqual(error as? APIError, .TOKEN_DEAUTH)
        }

        let empty = AuthenticationResponse(token: "access", uuid: "uuid", email: "test@example.com", refreshToken: "", isNewAccount: false, expiresIn: nil, tokenType: nil)
        XCTAssertThrowsError(try AuthenticationHelper.validatePasswordSignInResponse(empty)) { error in
            XCTAssertEqual(error as? APIError, .TOKEN_DEAUTH)
        }
    }

    func testFlagOnRefusesPasswordPersistenceAtHelperAndStorageBoundary() {
        flagMock.set(.refreshTokenForPasswordAuth, value: true)

        AuthenticationHelper.persistPasswordForLegacyAuthenticationIfNeeded("new-password")
        XCTAssertNil(ServerSettings.syncingPassword())
        XCTAssertEqual(ServerSettings.accountAuthMethod, .password)

        // Defense in depth: even a future caller that bypasses AuthenticationHelper cannot
        // write the legacy password while refresh-token password auth is selected.
        ServerSettings.saveSyncingPassword("bypass-password")
        XCTAssertNil(ServerSettings.syncingPassword())
    }

    func testFlagOffAcceptsLegacyResponseAndPersistsPassword() throws {
        flagMock.set(.refreshTokenForPasswordAuth, value: false)
        let response = AuthenticationResponse(token: "access", uuid: "uuid", email: "test@example.com", refreshToken: nil, isNewAccount: false, expiresIn: nil, tokenType: nil)

        XCTAssertNoThrow(try AuthenticationHelper.validatePasswordSignInResponse(response))
        AuthenticationHelper.persistPasswordForLegacyAuthenticationIfNeeded("legacy-password")

        XCTAssertEqual(ServerSettings.syncingPassword(), "legacy-password")
        XCTAssertNil(ServerSettings.accountAuthMethod)
    }

    func testRefreshTokenPersistenceFailureIsObservable() throws {
        KeychainHelper.store = RejectingRefreshTokenKeychainStore()
        let response = AuthenticationResponse(
            token: "access",
            uuid: "uuid",
            email: "test@example.com",
            refreshToken: "refresh",
            isNewAccount: false,
            expiresIn: 3600,
            tokenType: "Bearer"
        )

        XCTAssertFalse(AuthenticationHelper.persistSignInCredentials(from: response))
        XCTAssertNil(try ServerSettings.refreshToken())
    }

    func testRequiredRefreshTokenPersistenceFailureClearsEntireIdentityState() throws {
        KeychainHelper.store = RejectingRefreshTokenKeychainStore()
        let response = AuthenticationResponse(
            token: "access",
            uuid: "user-id",
            email: "test@example.com",
            refreshToken: "refresh",
            isNewAccount: false,
            expiresIn: 3600,
            tokenType: "Bearer"
        )

        XCTAssertThrowsError(
            try AuthenticationHelper.handleSuccessfulSignIn(
                response,
                requireRefreshTokenPersistence: true
            )
        ) { error in
            XCTAssertEqual(error as? APIError, .TOKEN_DEAUTH)
        }
        XCTAssertNil(ServerSettings.syncingV2Token)
        XCTAssertNil(try ServerSettings.refreshToken())
        XCTAssertNil(ServerSettings.userId)
        XCTAssertNil(ServerSettings.tokenExpiryDate())
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

        XCTAssertTrue(AuthenticationHelper.persistSignInCredentials(from: AuthenticationResponse(from: proto)))

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
