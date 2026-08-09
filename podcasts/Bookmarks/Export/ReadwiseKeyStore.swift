import Foundation
import PocketCastsUtils

/// Keychain storage for the user's Readwise access token (Highlights S6).
///
/// Same policy as `ProviderKeyStore`: this is the user's own third-party
/// credential, entered by hand — it is DELIBERATELY NOT cleared on sign-out
/// (signing out of Pocket Casts shouldn't cost the user their Readwise setup).
/// Do not add this key to any sign-out cleanup path. Token material must never
/// be logged. `AfterFirstUnlock` so background pushes can read it.
nonisolated enum ReadwiseKeyStore {
    private static let key = "readwise.accesstoken"

    static func token() -> String? {
        guard let value = try? KeychainHelper.string(for: key), !value.isEmpty else { return nil }
        return value
    }

    @discardableResult
    static func setToken(_ token: String?) -> Bool {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return KeychainHelper.save(
                string: trimmed,
                key: key,
                accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            )
        } else {
            return KeychainHelper.removeKey(key)
        }
    }
}
