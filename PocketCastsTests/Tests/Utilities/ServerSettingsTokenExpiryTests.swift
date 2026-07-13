import Foundation
import XCTest
@testable import PocketCastsServer
@testable import PocketCastsUtils

final class ServerSettingsTokenExpiryTests: XCTestCase {
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

    func testSetTokenExpiryAppliesSkew() throws {
        ServerSettings.setTokenExpiry(expiresIn: 3600)

        let expiry = try XCTUnwrap(ServerSettings.tokenExpiryDate())
        // now + 3600s − 5 minutes of skew.
        XCTAssertEqual(expiry.timeIntervalSinceNow, 3300, accuracy: 5)
    }

    func testNilExpiresInClearsStoredHint() {
        ServerSettings.setTokenExpiry(expiresIn: 3600)
        XCTAssertNotNil(ServerSettings.tokenExpiryDate())

        ServerSettings.setTokenExpiry(expiresIn: nil)
        XCTAssertNil(ServerSettings.tokenExpiryDate(), "Absent expires_in must clear a stale hint so it can't apply to a newer token")
    }

    func testTinyTTLIsTreatedAsNoHint() {
        // A TTL at or below the skew would compute an already-past expiry and force a
        // refresh before every request — treat it as "no hint" instead.
        ServerSettings.setTokenExpiry(expiresIn: 60)
        XCTAssertNil(ServerSettings.tokenExpiryDate())
    }

    func testValidTokenReturnedWhenNoExpiryHint() {
        ServerSettings.syncingV2Token = "stored-token"
        XCTAssertEqual(ServerSettings.validSyncingV2Token(), "stored-token")
    }

    func testValidTokenReturnedBeforeExpiry() {
        ServerSettings.syncingV2Token = "stored-token"
        ServerSettings.setTokenExpiryDate(Date(timeIntervalSinceNow: 600))
        XCTAssertEqual(ServerSettings.validSyncingV2Token(), "stored-token")
    }

    func testExpiredTokenTreatedAsAbsent() {
        ServerSettings.syncingV2Token = "stored-token"
        ServerSettings.setTokenExpiryDate(Date(timeIntervalSinceNow: -1))
        XCTAssertNil(ServerSettings.validSyncingV2Token(), "A past-expiry token counts as absent so callers refresh proactively")
    }

    func testNoTokenReturnsNilRegardlessOfExpiry() {
        ServerSettings.setTokenExpiryDate(Date(timeIntervalSinceNow: 600))
        XCTAssertNil(ServerSettings.validSyncingV2Token())
    }
}
