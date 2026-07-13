import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Refreshes `.localFeed` podcasts by fetching and parsing each feed on device, emitting
/// a `PodcastRefreshResponse` shaped exactly like the server's so the entire downstream
/// pipeline (`RefreshOperation`, sync, notifications) is reused unchanged.
///
/// Cursor note: the server needs `forceRefreshEpisodeFrom ?? latestEpisodeUuid` because
/// it returns incremental windows. A feed *is* the full source of truth, so the local
/// equivalent is simply "every parsed episode not already in the database" — which also
/// covers force-refresh-from for free.
public struct LocalFeedRefreshProvider: FeedRefreshProviding {
    /// Feeds fetched concurrently per refresh; keeps a large library from opening
    /// hundreds of simultaneous connections.
    private static let maxConcurrentFetches = 5

    private let fetcher: LocalFeedFetcher

    public init(fetcher: LocalFeedFetcher = LocalFeedFetcher()) {
        self.fetcher = fetcher
    }

    public func refresh(podcasts: [Podcast], completion: @escaping @Sendable (PodcastRefreshResponse?) -> Void) {
        let fetcher = fetcher
        Task {
            let updates = await Self.fetchUpdates(podcasts: podcasts, fetcher: fetcher)

            var response = PodcastRefreshResponse()
            response.status = "ok"
            response.result = RefreshResult(podcastUpdates: updates)
            completion(response)
        }
    }

    private static func fetchUpdates(podcasts: [Podcast], fetcher: LocalFeedFetcher) async -> [String: [RefreshEpisode]] {
        let refreshable = podcasts.filter { !($0.podcastUrl ?? "").isEmpty }
        guard !refreshable.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, [RefreshEpisode])?.self) { group in
            var updates = [String: [RefreshEpisode]]()
            var iterator = refreshable.makeIterator()

            func addNextFetch() {
                guard let podcast = iterator.next(), let feedURL = podcast.podcastUrl else { return }
                let podcastUuid = podcast.uuid
                let podcastId = podcast.id
                group.addTask {
                    do {
                        let feed = try await fetcher.fetchFeed(url: feedURL, credentials: LocalFeedCredentials.credentials(podcastUuid: podcastUuid))

                        // One fetch of the existing catalog per podcast; the matcher
                        // resolves every parsed item against it in memory, so podcasts
                        // whose back catalog carries server-canonical UUIDs (signed-out
                        // subscribes of server-sourced podcasts) never duplicate.
                        let existing = DataManager.sharedManager.allEpisodesForPodcast(id: podcastId)
                        let resolution = resolve(feed: feed, existing: existing)

                        // Keep the offline show-notes/chapters/transcripts cache fresh —
                        // the whole feed was parsed anyway. Entries must be keyed by the
                        // *resolved* UUIDs or the back catalog's show notes disappear
                        // (ShowInfoCoordinator reads cache-only for .localFeed podcasts).
                        if let showInfoData = LocalFeedShowInfo.data(from: feed, podcastUuid: podcastUuid, resolvedUuidOverrides: resolution.uuidOverrides) {
                            await ShowInfoDataRetriever.localFeedSeeder.storeLocalShowInfo(data: showInfoData, for: podcastUuid)
                        }

                        return resolution.newEpisodes.isEmpty ? nil : (podcastUuid, resolution.newEpisodes)
                    } catch {
                        FileLog.shared.addMessage("LocalFeedRefresh: failed to refresh \(podcastUuid) from \(LocalFeedURL.redactedForLogging(feedURL)): \(error)")
                        return nil
                    }
                }
            }

            for _ in 0 ..< maxConcurrentFetches { addNextFetch() }

            while let result = await group.next() {
                if let (uuid, episodes) = result {
                    updates[uuid] = episodes
                }
                addNextFetch()
            }

            return updates
        }
    }

    /// Splits a parsed feed against the existing catalog: items the matcher marks new
    /// become `RefreshEpisode`s (keeping the feed's newest-first document order —
    /// `RefreshOperation` reverses before saving, matching the server's contract);
    /// matched items whose hash UUID differs from the stored UUID are collected so
    /// show-info seeding can key their entries under the stored identity.
    static func resolve(feed: ParsedFeed, existing: [Episode]) -> (newEpisodes: [RefreshEpisode], uuidOverrides: [String: String]) {
        let matches = LocalFeedEpisodeMatcher.match(items: feed.items, existing: existing)
        var newEpisodes = [RefreshEpisode]()
        var uuidOverrides = [String: String]()

        for (item, match) in zip(feed.items, matches) {
            switch match {
            case .new(let hashUuid):
                newEpisodes.append(RefreshEpisode(item: item, uuid: hashUuid))
            case .existing(let uuid):
                if let hashUuid = LocalFeedIdentity.episodeUuid(guid: item.guid, enclosureURL: item.enclosureURL), hashUuid != uuid {
                    uuidOverrides[hashUuid] = uuid
                }
            case nil:
                continue
            }
        }

        return (newEpisodes, uuidOverrides)
    }
}

extension RefreshEpisode {
    /// Builds the server-refresh episode shape from a parsed feed item. `publishedDate`
    /// uses the `yyyy-MM-dd HH:mm:ss` GMT format `Episode.populate(fromEpisode:)` parses
    /// via `JsonUtil.convert(jsonDate:)`.
    init(item: ParsedFeedItem, uuid: String) {
        self.init()
        self.uuid = uuid
        title = item.title
        url = item.enclosureURL
        episodeDescription = item.itemDescription
        detailedDescription = item.itemDescriptionHTML
        fileType = item.enclosureType
        sizeInBytes = item.enclosureLength
        duration = item.duration
        episodeType = item.episodeType
        seasonNumber = item.seasonNumber
        episodeNumber = item.episodeNumber
        if let publishedDate = item.publishedDate {
            self.publishedDate = DateFormatHelper.sharedHelper.jsonFormat(publishedDate)
        }
    }
}
