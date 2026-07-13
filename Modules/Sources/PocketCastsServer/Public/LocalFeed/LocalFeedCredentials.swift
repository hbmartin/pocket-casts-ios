import Foundation
import PocketCastsUtils

/// Keychain-backed storage for private-feed HTTP Basic credentials, keyed by
/// podcast UUID. Populated at subscribe time from the userinfo of the URL the
/// user entered; the stored feed URL itself stays credential-free, so every
/// later refresh reattaches the credential from here.
public enum LocalFeedCredentials {
    private static func key(podcastUuid: String) -> String {
        "localFeedBasicAuth-\(podcastUuid)"
    }

    @discardableResult
    public static func save(user: String, password: String, podcastUuid: String) -> Bool {
        // The user part cannot contain ':' in a valid userinfo, so the joined
        // form splits back unambiguously on the first ':'.
        KeychainHelper.save(string: "\(user):\(password)",
                            key: key(podcastUuid: podcastUuid),
                            accessibility: kSecAttrAccessibleAfterFirstUnlock)
    }

    public static func credentials(podcastUuid: String) -> (user: String, password: String)? {
        guard let stored = try? KeychainHelper.string(for: key(podcastUuid: podcastUuid)),
              let separator = stored.firstIndex(of: ":") else { return nil }
        return (String(stored[..<separator]), String(stored[stored.index(after: separator)...]))
    }

    public static func delete(podcastUuid: String) {
        KeychainHelper.removeKey(key(podcastUuid: podcastUuid))
    }
}
