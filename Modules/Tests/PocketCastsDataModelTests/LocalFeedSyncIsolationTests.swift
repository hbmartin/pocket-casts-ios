import Foundation
import Testing
@testable import PocketCastsDataModel

/// The coexistence contract: `.localFeed` podcasts (deterministic hash UUIDs, refreshed
/// on device) must never surface in the queries that feed account sync.
@Suite("Local feed sync isolation")
struct LocalFeedSyncIsolationTests {
    private func makePodcast(uuid: String, source: PodcastRefreshSource, feedURL: String? = nil) -> Podcast {
        var podcast = Podcast()
        podcast.uuid = uuid
        podcast.title = uuid
        podcast.addedDate = Date()
        podcast.podcastUrl = feedURL
        podcast.subscribed = 1
        podcast.syncStatus = SyncStatus.notSynced.rawValue
        podcast.feedRefreshSource = source
        return podcast
    }

    @Test("allUnsyncedPodcasts excludes local-feed podcasts")
    func unsyncedPodcasts() {
        let dataManager = DataManager.newTestDataManager()

        dataManager.save(podcast: makePodcast(uuid: "server-1", source: .server))
        dataManager.save(podcast: makePodcast(uuid: "local-1", source: .localFeed))

        let unsynced = dataManager.allUnsyncedPodcasts().map(\.uuid)
        #expect(unsynced == ["server-1"])
    }

    @Test("unsyncedEpisodes excludes episodes of local-feed podcasts")
    func unsyncedEpisodes() {
        let dataManager = DataManager.newTestDataManager()

        let serverPodcast = dataManager.save(podcast: makePodcast(uuid: "server-1", source: .server))
        let localPodcast = dataManager.save(podcast: makePodcast(uuid: "local-1", source: .localFeed))

        for (index, podcast) in [serverPodcast, localPodcast].enumerated() {
            var episode = Episode()
            episode.uuid = "episode-\(index)"
            episode.addedDate = Date()
            episode.podcastUuid = podcast.uuid
            episode.podcast_id = podcast.id
            episode.playingStatusModified = 1000
            dataManager.save(episode: episode)
        }

        let unsynced = dataManager.unsyncedEpisodes(limit: 100).map(\.podcastUuid)
        #expect(unsynced == ["server-1"])
    }

    @Test("findPodcast(feedURL:) matches regardless of scheme/host case and trailing slash")
    func feedURLLookup() {
        let dataManager = DataManager.newTestDataManager()

        dataManager.save(podcast: makePodcast(uuid: "p-1", source: .server, feedURL: "https://Example.com/feed.xml"))

        #expect(dataManager.findPodcast(feedURL: "https://example.com/feed.xml")?.uuid == "p-1")
        #expect(dataManager.findPodcast(feedURL: "HTTPS://EXAMPLE.com/feed.xml")?.uuid == "p-1")
        #expect(dataManager.findPodcast(feedURL: "https://example.com/feed.xml/")?.uuid == "p-1")
        #expect(dataManager.findPodcast(feedURL: "https://example.com/other.xml") == nil)
        #expect(dataManager.findPodcast(feedURL: "") == nil)
    }

    @Test("refreshSource round-trips through the database")
    func refreshSourcePersistence() {
        let dataManager = DataManager.newTestDataManager()

        dataManager.save(podcast: makePodcast(uuid: "local-1", source: .localFeed))

        let reloaded = dataManager.findPodcast(uuid: "local-1", includeUnsubscribed: true)
        #expect(reloaded?.feedRefreshSource == .localFeed)
        #expect(reloaded?.isLocalFeedSourced == true)
    }
}
