import XCTest
@testable import PocketCastsServer
@testable import PocketCastsUtils
import Security

final class ServerSettingsPushTokenTests: XCTestCase {
    private var previousKeychainStore: KeychainStoring!

    override func setUp() {
        super.setUp()
        // Keep these push-token tests unit-style; KeychainHelperIntegrationTests
        // below is the focused real-keychain canary for CI environment issues.
        previousKeychainStore = KeychainHelper.store
        KeychainHelper.store = InMemoryKeychainStore()
        clearPushTokenStorage()
    }

    override func tearDown() {
        clearPushTokenStorage()
        if let previousKeychainStore {
            KeychainHelper.store = previousKeychainStore
        }
        previousKeychainStore = nil
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

final class KeychainHelperIntegrationTests: XCTestCase {
    private let keychain = KeychainHelper()
    private var key: String!

    override func setUp() {
        super.setUp()
        key = "PocketCastsTests.KeychainHelperIntegrationTests.\(UUID().uuidString)"
        keychain.save(value: nil, key: key, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    override func tearDown() {
        keychain.save(value: nil, key: key, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        key = nil
        super.tearDown()
    }

    func testRealKeychainRoundTripsString() throws {
        let value = "real-keychain-\(UUID().uuidString)"

        XCTAssertTrue(keychain.save(value: value, key: key, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly))
        XCTAssertEqual(try keychain.string(for: key), value)
    }
}
