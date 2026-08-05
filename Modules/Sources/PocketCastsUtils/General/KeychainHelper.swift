import Foundation

/// Abstraction over keychain storage so unit tests can substitute an in-memory store.
/// The real implementation is `KeychainHelper`; keep a focused integration test
/// on the real keychain to catch environment issues such as missing code-signing
/// entitlements (-34018) in CI.
public protocol KeychainStoring: Sendable {
    @discardableResult
    func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool
    func string(for key: String) throws -> String?
}

public final class KeychainHelper: Sendable, KeychainStoring {

    public enum KeychainError: Error {
        case status(OSStatus)
    }

    private let service = "au.com.shiftyjelly.podcasts"
    private let legacyServicePrefix = "au.com.shiftyjelly.podcasts."

    private static let shared = KeychainHelper()

    // nonisolated(unsafe): swapped only by tests (in-memory store in setUp, restored in tearDown); the app always uses the real keychain.
    // The swap is unsynchronized, so background work still in flight from a previous test
    // (download delegate callbacks, sync, analytics) can race it. If CI ever shows flaky
    // keychain reads mid-suite, suspect this seam first.
    nonisolated(unsafe) public static var store: KeychainStoring = KeychainHelper.shared

    @discardableResult
    public class func save(string: String?, key: String, accessibility: CFTypeRef) -> Bool {
        store.save(value: string, key: key, accessibility: accessibility)
    }

    @discardableResult
    public class func removeKey(_ key: String) -> Bool {
        // the accessibility flag is ignored on saving a nil value, so it's safe for this helper to put whatever in that field
        store.save(value: nil, key: key, accessibility: kSecAttrAccessibleAfterFirstUnlock)
    }

    public class func string(for key: String) throws -> String? {
        try store.string(for: key)
    }

    public func string(for key: String) throws -> String? {
        let scopedResult = try string(for: createQuery(key: key), key: key)
        if scopedResult != nil {
            return scopedResult
        }

        return try string(for: createLegacyQuery(key: key), key: key)
    }

    private func string(for query: [String: Any], key: String) throws -> String? {
        var queryResult: AnyObject?
        let status = withUnsafeMutablePointer(to: &queryResult) {
            SecItemCopyMatching(query as CFDictionary, $0)
        }
        switch status {
        case errSecItemNotFound, errSecSuccess:
            ()
        default:
            FileLog.shared.addMessage("KeychainHelper: Failed to fetch \(key) osstatus: \(status)")
            throw KeychainError.status(status)
        }

        guard let data = queryResult as? Data else { return nil }

        return String(data: data, encoding: String.Encoding.utf8)
    }

    @discardableResult
    public func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool {
        // If the value is nil, delete the item
        guard let value else {
            let scopedStatus = SecItemDelete(createService(key: key) as CFDictionary)
            let legacyStatus = SecItemDelete(createLegacyService(key: key) as CFDictionary)

            for status in [scopedStatus, legacyStatus] where status != errSecSuccess && status != errSecItemNotFound {
                FileLog.shared.addMessage("KeychainHelper: Failed to delete \(key) osstatus: \(status)")
            }

            return [scopedStatus, legacyStatus].allSatisfy { $0 == errSecSuccess || $0 == errSecItemNotFound }
        }

        guard let data = value.data(using: String.Encoding.utf8) else { return false }

        let query = createService(key: key)

        let attributesToUpdate: [String: Any] = [
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: data
        ]

        var saveParams = query
        saveParams.merge(attributesToUpdate) { _, new in new }

        var status = SecItemAdd(saveParams as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        }

        if status == errSecSuccess {
            let legacyDeleteStatus = SecItemDelete(createLegacyService(key: key) as CFDictionary)
            if legacyDeleteStatus != errSecSuccess && legacyDeleteStatus != errSecItemNotFound {
                FileLog.shared.addMessage("KeychainHelper: Failed to delete legacy \(key) osstatus: \(legacyDeleteStatus)")
            }
        }

        if status != errSecSuccess {
            FileLog.shared.addMessage("KeychainHelper: Failed to save \(key) osstatus: \(status)")
        }

        return status == errSecSuccess
    }

    /// One-shot cleanup: deletes every generic-password item whose account
    /// (current scoped-service shape) or service suffix (legacy per-key-service
    /// shape) begins with the given key prefix. Bypasses the `store` seam on
    /// purpose — it enumerates the real keychain, which the seam cannot do.
    public class func removeAllItems(withKeyPrefix prefix: String) {
        let helper = shared

        // Current shape: service = app service, account = key.
        var scopedQuery = helper.baseQuery()
        scopedQuery[kSecAttrService as String] = helper.service
        scopedQuery[kSecMatchLimit as String] = kSecMatchLimitAll
        scopedQuery[kSecReturnAttributes as String] = kCFBooleanTrue as Any

        var scopedResult: AnyObject?
        var status = withUnsafeMutablePointer(to: &scopedResult) {
            SecItemCopyMatching(scopedQuery as CFDictionary, $0)
        }
        if status == errSecSuccess, let items = scopedResult as? [[String: Any]] {
            for item in items {
                guard let account = item[kSecAttrAccount as String] as? String,
                      account.hasPrefix(prefix) else { continue }
                var deleteQuery = helper.baseQuery()
                deleteQuery[kSecAttrService as String] = helper.service
                deleteQuery[kSecAttrAccount as String] = account
                let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
                if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
                    FileLog.shared.addMessage("KeychainHelper: sweep failed to delete \(account) osstatus: \(deleteStatus)")
                }
            }
        } else if status != errSecItemNotFound, status != errSecSuccess {
            FileLog.shared.addMessage("KeychainHelper: sweep enumeration failed osstatus: \(status)")
        }

        // Legacy shape: service = app service prefix + key, no account.
        var legacyQuery = helper.baseQuery()
        legacyQuery[kSecMatchLimit as String] = kSecMatchLimitAll
        legacyQuery[kSecReturnAttributes as String] = kCFBooleanTrue as Any

        var legacyResult: AnyObject?
        status = withUnsafeMutablePointer(to: &legacyResult) {
            SecItemCopyMatching(legacyQuery as CFDictionary, $0)
        }
        guard status == errSecSuccess, let items = legacyResult as? [[String: Any]] else { return }
        for item in items {
            guard let itemService = item[kSecAttrService as String] as? String,
                  itemService.hasPrefix(helper.legacyServicePrefix + prefix) else { continue }
            var deleteQuery = helper.baseQuery()
            deleteQuery[kSecAttrService as String] = itemService
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
                FileLog.shared.addMessage("KeychainHelper: sweep failed to delete legacy \(itemService) osstatus: \(deleteStatus)")
            }
        }
    }

    private func createQuery(key: String) -> [String: Any] {
        var query = createService(key: key)
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private func createService(key: String) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrService as String] = service
        query[kSecAttrAccount as String] = key
        return query
    }

    private func createLegacyQuery(key: String) -> [String: Any] {
        var query = createLegacyService(key: key)
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private func createLegacyService(key: String) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrService as String] = legacyServicePrefix + key
        return query
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}
