import Foundation
import PocketCastsUtils

/// A `KeychainStoring` backed by a dictionary, so unit tests don't depend on real
/// keychain state (which can fail wholesale in CI, e.g. OSStatus -34018 when the
/// test host isn't code signed). Install in `setUp` via `KeychainHelper.store` and
/// restore the previous store in `tearDown`.
final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    @discardableResult
    func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
        return true
    }

    func string(for key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }
}
