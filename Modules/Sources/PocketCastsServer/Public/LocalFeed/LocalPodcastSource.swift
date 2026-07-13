import Foundation
import PocketCastsUtils

/// The on-device counterpart of `CacheServerHandler.loadPodcastInfo`: fetches and parses
/// a feed (following pages to back-fill history) and returns the same canonical
/// `{"podcast": {..., "episodes": [...]}}` dictionary, so the entire existing
/// add/update/merge pipeline (`ServerPodcastManager.addFromJson` → `Podcast.from` /
/// `Episode.from`) is reused unchanged. Identity is deterministic (`LocalFeedIdentity`),
/// never server-issued.
public struct LocalPodcastSource: Sendable {
    private let fetcher: LocalFeedFetcher

    public init(fetcher: LocalFeedFetcher = LocalFeedFetcher()) {
        self.fetcher = fetcher
    }

    public func loadPodcastInfo(feedURL: String) async -> [String: Any]? {
        guard let feed = try? await fetcher.fetchFeed(url: feedURL, followingPages: true) else {
            FileLog.shared.addMessage("LocalPodcastSource: failed to fetch or parse feed \(LocalFeedURL.redactedForLogging(feedURL))")
            return nil
        }

        let podcastUuid = LocalFeedIdentity.uuid(seed: LocalFeedURL.removingCredentials(from: feedURL))

        // The podcast row stores the credential-stripped URL, so basic-auth
        // userinfo would be lost after this point — persist it for refreshes.
        if let credentials = LocalFeedURL.credentials(from: feedURL) {
            LocalFeedCredentials.save(user: credentials.user, password: credentials.password, podcastUuid: podcastUuid)
        }

        // Seed the offline show-notes/chapters/transcripts cache while the parsed feed
        // is in hand — the display path reads it cache-only for local podcasts.
        if let showInfoData = LocalFeedShowInfo.data(from: feed, podcastUuid: podcastUuid) {
            await ShowInfoDataRetriever.localFeedSeeder.storeLocalShowInfo(data: showInfoData, for: podcastUuid)
        }

        return podcastInfoDict(from: feed, podcastUuid: podcastUuid, feedURL: feedURL)
    }

    func podcastInfoDict(from feed: ParsedFeed, podcastUuid: String, feedURL: String) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()

        let episodes: [[String: Any]] = feed.items.compactMap { item in
            guard let uuid = LocalFeedIdentity.episodeUuid(guid: item.guid, enclosureURL: item.enclosureURL) else { return nil }

            var episode: [String: Any] = ["uuid": uuid]
            episode["title"] = item.title
            episode["url"] = item.enclosureURL
            episode["file_type"] = item.enclosureType
            episode["file_size"] = item.enclosureLength
            episode["duration"] = item.duration
            episode["number"] = item.episodeNumber
            episode["season"] = item.seasonNumber
            episode["type"] = item.episodeType
            if let publishedDate = item.publishedDate {
                episode["published"] = isoFormatter.string(from: publishedDate)
            }
            // Feed-authored transcripts only; nothing here is Pocket Casts-generated.
            episode["has_generated_transcript"] = false
            return episode
        }

        var podcastJson: [String: Any] = [
            "uuid": podcastUuid,
            "url": LocalFeedURL.removingCredentials(from: feedURL),
            "episodes": episodes
        ]
        podcastJson["title"] = feed.title
        podcastJson["author"] = feed.author
        podcastJson["description"] = feed.feedDescription
        podcastJson["description_html"] = feed.feedDescriptionHTML
        podcastJson["category"] = feed.category
        podcastJson["show_type"] = feed.showType
        podcastJson["explicit"] = feed.isExplicit
        if let fundingURL = feed.fundingURL {
            podcastJson["fundings"] = [["url": fundingURL]]
        }

        return ["podcast": podcastJson]
    }
}
