import Foundation

/// Synthesizes the cache server's show-notes JSON (`{"podcast": {..., "episodes": [...]}}`,
/// snake_case keys, matching what `Episode.Metadata` decodes) from a locally parsed feed.
/// Seeded into `ShowInfoDataRetriever`'s cache so show notes, `<podcast:chapters>` and
/// `<podcast:transcript>` resolve for local-feed podcasts without any server.
public enum LocalFeedShowInfo {
    /// `resolvedUuidOverrides` maps an item's deterministic hash UUID to the UUID the
    /// episode is actually stored under (server-canonical for signed-out subscribes of
    /// server-sourced podcasts). Entries must be keyed by the stored identity or the
    /// cache-only read path (`ShowInfoCoordinator` for `.localFeed` podcasts) can never
    /// find them. The default identity mapping covers pure-local podcasts.
    public static func data(from feed: ParsedFeed, podcastUuid: String, resolvedUuidOverrides: [String: String] = [:]) -> Data? {
        let episodes: [[String: Any]] = feed.items.compactMap { item in
            guard let hashUuid = LocalFeedIdentity.episodeUuid(guid: item.guid, enclosureURL: item.enclosureURL) else { return nil }
            let uuid = resolvedUuidOverrides[hashUuid] ?? hashUuid

            var episode: [String: Any] = ["uuid": uuid]
            if let showNotes = item.itemDescriptionHTML ?? item.itemDescription {
                episode["show_notes"] = showNotes
            }
            if let chaptersURL = item.chaptersURL {
                episode["chapters_url"] = chaptersURL
            }
            // "transcripts" must always be present: Episode.Metadata declares it
            // non-optional, so a missing key fails the whole episode's decode. Entries
            // without a type are dropped for the same reason (Transcript.type is
            // non-optional, and one bad element fails the whole array).
            episode["transcripts"] = item.transcripts.compactMap { transcript -> [String: Any]? in
                guard let type = transcript.type else { return nil }
                return ["url": transcript.url, "type": type]
            }
            return episode
        }

        let showInfo: [String: Any] = [
            "podcast": [
                "uuid": podcastUuid,
                "episodes": episodes
            ] as [String: Any]
        ]

        return try? JSONSerialization.data(withJSONObject: showInfo)
    }
}
