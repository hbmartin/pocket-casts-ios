import Foundation
import PocketCastsUtils

/// Deterministic identity for podcasts and episodes ingested from feeds parsed on device.
///
/// Local-feed entities never receive a server-issued UUID, so identity is derived by
/// hashing a stable seed (feed URL for podcasts; item guid — falling back to enclosure
/// URL — for episodes) into a UUIDv5-style string. The same seed always produces the
/// same UUID on every device, which is what lets FileSync reconcile local-feed libraries
/// across devices without any coordination service.
public enum LocalFeedIdentity {
    /// Fixed namespace so local-feed UUIDs can never be confused with (or collide into)
    /// seeds hashed by any other feature. Changing this invalidates every local-feed
    /// identity, so it must stay stable forever.
    private static let namespace = "au.com.pocketcasts.localfeed:"

    /// Derives the deterministic UUID for a seed. The output is formatted like a
    /// version-5 UUID (SHA-based, variant 10xx) so it is well-formed anywhere a UUID
    /// string is expected while remaining distinguishable from the server's UUIDs.
    public static func uuid(seed: String) -> String {
        let digest = (namespace + seed).sha256 // 64 hex chars

        var hex = Array(digest.prefix(32))
        hex[12] = "5" // version nibble: SHA-based
        hex[16] = variantNibble(for: hex[16]) // variant nibble: RFC 4122 (10xx)

        let groups = [hex[0..<8], hex[8..<12], hex[12..<16], hex[16..<20], hex[20..<32]]
        return groups.map { String($0) }.joined(separator: "-")
    }

    /// Derives the episode UUID from the feed item's stable identity: its guid when the
    /// feed provides one, otherwise the enclosure URL.
    public static func episodeUuid(guid: String?, enclosureURL: String?) -> String? {
        let trimmedGuid = guid?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedGuid, !trimmedGuid.isEmpty {
            return uuid(seed: trimmedGuid)
        }
        if let enclosureURL, !enclosureURL.isEmpty {
            return uuid(seed: enclosureURL)
        }
        return nil
    }

    private static func variantNibble(for nibble: Character) -> Character {
        let value = nibble.hexDigitValue ?? 0
        let variant = (value & 0x3) | 0x8
        return Character(String(variant, radix: 16))
    }
}
