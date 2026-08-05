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

    override func tearDown() {
        KeychainHelper.removeKey("\(prefix)one")
        KeychainHelper.removeKey("\(prefix)two")
        KeychainHelper.removeKey(unrelatedKey)
        super.tearDown()
    }

    func testSweepRemovesOnlyPrefixedItems() throws {
        KeychainHelper.save(string: "secret-1", key: "\(prefix)one", accessibility: kSecAttrAccessibleAfterFirstUnlock)
        KeychainHelper.save(string: "secret-2", key: "\(prefix)two", accessibility: kSecAttrAccessibleAfterFirstUnlock)
        KeychainHelper.save(string: "keep-me", key: unrelatedKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)

        KeychainHelper.removeAllItems(withKeyPrefix: prefix)

        XCTAssertNil(try KeychainHelper.string(for: "\(prefix)one"))
        XCTAssertNil(try KeychainHelper.string(for: "\(prefix)two"))
        XCTAssertEqual(try KeychainHelper.string(for: unrelatedKey), "keep-me")
    }

    func testSweepWithNoMatchesIsANoop() throws {
        KeychainHelper.save(string: "keep-me", key: unrelatedKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)

        KeychainHelper.removeAllItems(withKeyPrefix: "\(prefix)nothing-matches-")

        XCTAssertEqual(try KeychainHelper.string(for: unrelatedKey), "keep-me")
    }
}
