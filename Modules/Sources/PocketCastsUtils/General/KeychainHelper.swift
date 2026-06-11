import Foundation

public final class KeychainHelper: Sendable {

    public enum KeychainError: Error {
        case status(OSStatus)
    }

    private let prefix = "au.com.shiftyjelly.podcasts."

    private static let shared = KeychainHelper()

    @discardableResult
    public class func save(string: String?, key: String, accessibility: CFTypeRef) -> Bool {
        KeychainHelper.shared.save(value: string, key: key, accessibility: accessibility)
    }

    @discardableResult
    public class func removeKey(_ key: String) -> Bool {
        // the accessibility flag is ignored on saving a nil value, so it's safe for this helper to put whatever in that field
        KeychainHelper.shared.save(value: nil, key: key, accessibility: kSecAttrAccessibleAfterFirstUnlock)
    }

    public class func string(for key: String) throws -> String? {
        try KeychainHelper.shared.string(for: key)
    }

    private func save(string: String?, key: String, accessibility: CFTypeRef) -> Bool {
        save(value: string, key: key, accessibility: accessibility)
    }

    private func string(for key: String) throws -> String? {
        let fullKey = prefix + key

        var query = createQuery()
        query[kSecAttrService as String] = fullKey

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

    private func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool {
        let fullKey = prefix + key

        // If the value is nil, delete the item
        guard let value else {
            var query = createService()
            query[kSecAttrService as String] = fullKey
            let status = SecItemDelete(query as CFDictionary)

            return status == errSecSuccess
        }

        guard let data = value.data(using: String.Encoding.utf8) else { return false }

        var query = createService()
        query[kSecAttrService as String] = fullKey

        let attributesToUpdate: [String: Any] = [
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: data
        ]

        var status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if status == errSecItemNotFound {
            var saveParams = query
            saveParams.merge(attributesToUpdate) { _, new in new }

            status = SecItemAdd(saveParams as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            }
        }

        return status == errSecSuccess
    }

    private func createQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecReturnData as String: kCFBooleanTrue as Any]
    }

    private func createService() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword]
    }
}
