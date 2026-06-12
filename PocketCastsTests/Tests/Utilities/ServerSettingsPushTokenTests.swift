import XCTest
@testable import PocketCastsServer

/// Intentionally runs against the real keychain (no `InMemoryKeychainStore`) — this is
/// the integration canary for keychain availability. If it fails with OSStatus -34018
/// while other tests pass, the test host's code signing/entitlements are broken, not
/// the code under test. See ci_improvements.md.
final class ServerSettingsPushTokenTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearPushTokenStorage()
    }

    override func tearDown() {
        clearPushTokenStorage()
        super.tearDown()
    }

    func testSetPushTokenRoundTripsThroughKeychain() {
        ServerSettings.setPushToken(token: "test-push-token")

        XCTAssertEqual(ServerSettings.pushToken(), "test-push-token")
    }

    func testSetPushTokenRemovesLegacyUserDefaultsValue() {
        UserDefaults.standard.set("legacy-push-token", forKey: ServerConstants.UserDefaults.pushToken)

        ServerSettings.setPushToken(token: "new-push-token")

        XCTAssertNil(UserDefaults.standard.string(forKey: ServerConstants.UserDefaults.pushToken))
        XCTAssertEqual(ServerSettings.pushToken(), "new-push-token")
    }

    func testLegacyUserDefaultsPushTokenMigratesToKeychain() {
        UserDefaults.standard.set("legacy-push-token", forKey: ServerConstants.UserDefaults.pushToken)

        XCTAssertEqual(ServerSettings.pushToken(), "legacy-push-token")
        XCTAssertNil(UserDefaults.standard.string(forKey: ServerConstants.UserDefaults.pushToken))

        clearPushTokenStorage()
        XCTAssertNil(ServerSettings.pushToken())
    }

    func testRemovePushTokenClearsKeychainAndLegacyUserDefaults() {
        ServerSettings.setPushToken(token: "keychain-push-token")
        UserDefaults.standard.set("legacy-push-token", forKey: ServerConstants.UserDefaults.pushToken)

        ServerSettings.removePushToken()

        XCTAssertNil(UserDefaults.standard.string(forKey: ServerConstants.UserDefaults.pushToken))
        XCTAssertNil(ServerSettings.pushToken())
    }

    private func clearPushTokenStorage() {
        ServerSettings.removePushToken()
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.pushToken)
    }
}
