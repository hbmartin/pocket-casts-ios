import PocketCastsUtils
import XCTest

@testable import podcasts

/// Runs against the real keychain (possible here because the app-hosted test
/// runner carries the keychain entitlement; module test bundles fail with
/// -34018): the sweep enumerates SecItem storage directly, which no in-memory
/// store can exercise.
final class KeychainHelperSweepTests: XCTestCase {
    private let prefix = "sweepTest-"
    private let unrelatedKey = "sweepTestUnrelatedKey"
    private var legacyService: String { "au.com.shiftyjelly.podcasts.\(prefix)legacy" }

    override func tearDown() {
        KeychainHelper.removeKey("\(prefix)one")
        KeychainHelper.removeKey("\(prefix)two")
        KeychainHelper.removeKey(unrelatedKey)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: ""
        ] as CFDictionary)
        super.tearDown()
    }

    func testSweepRemovesOnlyPrefixedItems() throws {
        XCTAssertTrue(KeychainHelper.save(string: "secret-1", key: "\(prefix)one", accessibility: kSecAttrAccessibleAfterFirstUnlock))
        XCTAssertTrue(KeychainHelper.save(string: "secret-2", key: "\(prefix)two", accessibility: kSecAttrAccessibleAfterFirstUnlock))
        XCTAssertTrue(KeychainHelper.save(string: "keep-me", key: unrelatedKey, accessibility: kSecAttrAccessibleAfterFirstUnlock))

        // The retired shape encoded the key in service rather than account.
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: ""
        ]
        var legacyItem = legacyQuery
        legacyItem.merge([
            kSecValueData as String: Data("legacy-secret".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]) { _, new in new }
        let legacyStatus = SecItemAdd(legacyItem as CFDictionary, nil)
        XCTAssertEqual(legacyStatus, errSecSuccess)

        XCTAssertTrue(KeychainHelper.removeAllItems(withKeyPrefix: prefix))

        XCTAssertNil(try KeychainHelper.string(for: "\(prefix)one"))
        XCTAssertNil(try KeychainHelper.string(for: "\(prefix)two"))
        XCTAssertEqual(try KeychainHelper.string(for: unrelatedKey), "keep-me")
        XCTAssertEqual(SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: ""
        ] as CFDictionary, nil), errSecItemNotFound)
    }

    func testSweepWithNoMatchesIsANoop() throws {
        XCTAssertTrue(KeychainHelper.save(string: "keep-me", key: unrelatedKey, accessibility: kSecAttrAccessibleAfterFirstUnlock))

        XCTAssertTrue(KeychainHelper.removeAllItems(withKeyPrefix: "\(prefix)nothing-matches-"))

        XCTAssertEqual(try KeychainHelper.string(for: unrelatedKey), "keep-me")
    }
}
