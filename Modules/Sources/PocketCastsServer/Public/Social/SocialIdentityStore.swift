import Foundation

/// Local cache of the signed-in user's own social profile. The server is the
/// source of truth; this cache lets the app know whether the account has joined
/// and render its own profile offline without a round-trip. Device-local, not
/// synced; cleared on logout and on account erase. See docs/Social.md.
public enum SocialIdentityStore {
    private static let cacheKey = "SocialProfileCache"

    /// The cached own-profile, or nil when the account hasn't joined (or the
    /// cache was cleared).
    public static var cachedProfile: SocialProfile? {
        get {
            guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
            return try? JSONDecoder().decode(SocialProfile.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: cacheKey)
                return
            }
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    /// Whether this account has joined social (claimed a handle).
    public static var isJoined: Bool {
        cachedProfile != nil
    }

    /// The claimed handle, when joined.
    public static var handle: String? {
        cachedProfile?.handle
    }

    /// Clears the cached profile — call on logout and on account erase.
    public static func clear() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
