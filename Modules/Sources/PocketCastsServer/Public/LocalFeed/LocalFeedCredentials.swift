import Foundation
import PocketCastsDataModel
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

    /// The HTTP Basic `Authorization` header value to attach when fetching an episode's
    /// media (download or playback), or nil when none applies. Only episodes of a
    /// `.localFeed` podcast with a stored credential qualify, and only when the media
    /// URL shares the feed URL's origin — the credential must never reach a
    /// third-party host such as a CDN.
    public static func mediaAuthorizationHeader(for episode: BaseEpisode, mediaURL: URL) -> String? {
        guard let episode = episode as? Episode,
              let podcast = DataManager.sharedManager.findPodcast(uuid: episode.podcastUuid, includeUnsubscribed: true),
              podcast.isLocalFeedSourced,
              let feedURL = (podcast.podcastUrl).flatMap(URL.init(string:)),
              LocalFeedURL.isSameOrigin(mediaURL, feedURL),
              let stored = credentials(podcastUuid: podcast.uuid),
              let encoded = "\(stored.user):\(stored.password)".data(using: .utf8)
        else { return nil }

        return "Basic \(encoded.base64EncodedString())"
    }
}
