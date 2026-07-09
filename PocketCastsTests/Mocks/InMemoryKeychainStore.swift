import Foundation
import PocketCastsUtils
import Synchronization

/// A `KeychainStoring` backed by a dictionary, so unit tests don't depend on real
/// keychain state (which can fail wholesale in CI, e.g. OSStatus -34018 when the
/// test host isn't code signed). Install in `setUp` via `KeychainHelper.store` and
/// restore the previous store in `tearDown`.
final class InMemoryKeychainStore: KeychainStoring, Sendable {
    private let values = Mutex<[String: String]>([:])

    @discardableResult
    func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool {
        values.withLock { values in
            guard let value else {
                // Match the real keychain: deleting a missing key fails (errSecItemNotFound).
                return values.removeValue(forKey: key) != nil
            }
            values[key] = value
            return true
        }
    }

    func string(for key: String) throws -> String? {
        values.withLock { $0[key] }
    }
}
