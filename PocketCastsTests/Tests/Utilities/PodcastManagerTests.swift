import XCTest
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
@testable import podcasts

final class PodcastManagerTests: DBTestCase {
    func testSetNotificationsEnabledUpdatesNewSettingsStoragePayload() throws {
        let store = FeatureFlagOverrideStore()
        defer { store.resetOverrides() }
        try store.override(FeatureFlag.newSettingsStorage, withValue: true)

        var podcast = self.podcast!
        let persistedTitle = "Persisted title"
        podcast.title = persistedTitle
        podcast = dataManager.save(podcast: podcast)
        podcast.pushEnabled = true
        podcast.title = "Stale local title"
        podcast.settings.notification = true
        podcast.syncStatus = SyncStatus.synced.rawValue

        let podcastManager = PodcastManager(dataManager: dataManager, downloadManager: downloadManager)
        let savedPodcast = podcastManager.setNotificationsEnabled(podcast: podcast, enabled: false)
        let reloadedPodcast = try XCTUnwrap(dataManager.findPodcast(uuid: podcast.uuid, includeUnsubscribed: true))

        XCTAssertFalse(savedPodcast.pushEnabled)
        XCTAssertFalse(savedPodcast.settings.notification)
        XCTAssertEqual(savedPodcast.syncStatus, SyncStatus.notSynced.rawValue)
        XCTAssertFalse(reloadedPodcast.pushEnabled)
        XCTAssertFalse(reloadedPodcast.settings.notification)
        XCTAssertEqual(reloadedPodcast.syncStatus, SyncStatus.notSynced.rawValue)
        XCTAssertEqual(reloadedPodcast.title, persistedTitle)
    }

    func testTaskCancellationForUnusednDeletion() async throws {
        let (podcastManager, task) = try await setUpQueuedDownload()

        // Create a predicate + expectation to check when task state is completed
        let predicate = NSPredicate(block: { _, _ -> Bool in
            return task.state == .completed
        })
        let publishExpectation = XCTNSPredicateExpectation(predicate: predicate, object: task)

        // This should delete the podcast given the mock data
        await podcastManager.deletePodcastIfUnused(podcast)

        // Verify the podcast has been removed from the data manager
        XCTAssertNil(dataManager.findPodcast(uuid: podcast.uuid))

        // Wait for the task to fulfill the completion expectation: that it is completed
        await fulfillment(of: [publishExpectation])

        // Check that the download task has been cancelled as a result of deleting the podcast
        let error = task.error as? NSError
        XCTAssertEqual(error?.domain, NSURLErrorDomain, "Task should be cancelled")
        XCTAssertEqual(error?.code, NSURLErrorCancelled, "Task should be cancelled")
    }

    func testCleanupKeepsDownloadsInPlaylist() async throws {
        let (_, episode) = makeDownloadedPodcastAndEpisode()
        var playlist = EpisodeFilter()
        playlist.uuid = UUID().uuidString
        playlist.playlistName = "Keep Downloads"
        playlist.manual = true
        dataManager.save(playlist: playlist)
        dataManager.add(episodes: [episode], to: playlist)

        let podcastManager = PodcastManager(dataManager: dataManager, downloadManager: downloadManager)
        await podcastManager.checkForUnusedPodcasts()

        let refreshedEpisode = try XCTUnwrap(dataManager.findEpisode(uuid: episode.uuid))
        XCTAssertEqual(refreshedEpisode.episodeStatus, DownloadStatus.downloaded.rawValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadManager.pathForEpisode(refreshedEpisode)))
    }

    func testGhostCleanupDeletesGhostEpisode() throws {
        let ghostEpisode = Episode()
        ghostEpisode.uuid = "ghost-\(UUID().uuidString)"
        ghostEpisode.podcastUuid = "missing-\(UUID().uuidString)"
        ghostEpisode.podcast_id = Int64.max
        ghostEpisode.addedDate = Date()
        ghostEpisode.playingStatus = PlayingStatus.notPlayed.rawValue
        dataManager.save(episode: ghostEpisode)

        let podcastManager = PodcastManager(dataManager: dataManager, downloadManager: downloadManager)
        podcastManager.deleteGhostEpisodesIfNeeded()

        XCTAssertNil(dataManager.findEpisode(uuid: ghostEpisode.uuid))
    }

    func testCleanupKeepsDownloadsNotInPlaylist() async throws {
        let (_, episode) = makeDownloadedPodcastAndEpisode()

        let podcastManager = PodcastManager(dataManager: dataManager, downloadManager: downloadManager)
        await podcastManager.checkForUnusedPodcasts()

        let refreshedEpisode = try XCTUnwrap(dataManager.findEpisode(uuid: episode.uuid))
        XCTAssertEqual(refreshedEpisode.episodeStatus, DownloadStatus.downloaded.rawValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadManager.pathForEpisode(refreshedEpisode)))
    }

    func testUnsubscribeRemovesDownloadsInPlaylist() throws {
        let (podcast, episode) = makeDownloadedPodcastAndEpisode()
        var playlist = EpisodeFilter()
        playlist.uuid = UUID().uuidString
        playlist.playlistName = "Keep Downloads"
        playlist.manual = true
        dataManager.save(playlist: playlist)
        dataManager.add(episodes: [episode], to: playlist)

        let podcastManager = PodcastManager(dataManager: dataManager, downloadManager: downloadManager, isLoggedIn: { true })
        podcastManager.unsubscribe(podcast: podcast)

        let refreshedEpisode = try XCTUnwrap(dataManager.findEpisode(uuid: episode.uuid))
        XCTAssertEqual(refreshedEpisode.episodeStatus, DownloadStatus.notDownloaded.rawValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadManager.pathForEpisode(refreshedEpisode)))
    }

    func testUnsubscribeRemovesDownloadsNotInPlaylist() throws {
        let (podcast, episode) = makeDownloadedPodcastAndEpisode()
        let podcastManager = PodcastManager(dataManager: dataManager, downloadManager: downloadManager, isLoggedIn: { true })

        podcastManager.unsubscribe(podcast: podcast)

        let refreshedEpisode = try XCTUnwrap(dataManager.findEpisode(uuid: episode.uuid))
        XCTAssertEqual(refreshedEpisode.episodeStatus, DownloadStatus.notDownloaded.rawValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadManager.pathForEpisode(refreshedEpisode)))
    }

    private func makeDownloadedPodcastAndEpisode() -> (Podcast, Episode) {
        var podcast = Podcast()
        podcast.uuid = UUID().uuidString
        podcast.subscribed = 0
        podcast.addedDate = Date().addingTimeInterval(-2.weeks)
        podcast.syncStatus = SyncStatus.synced.rawValue
        podcast = dataManager.save(podcast: podcast)

        let episode = Episode()
        episode.uuid = UUID().uuidString
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.addedDate = podcast.addedDate
        episode.downloadUrl = "http://example.com/audio"
        episode.playingStatus = PlayingStatus.notPlayed.rawValue
        episode.episodeStatus = DownloadStatus.downloaded.rawValue
        dataManager.save(episode: episode)

        createDownloadedFile(for: episode)

        track(podcast: podcast)
        track(episode: episode)

        return (podcast, episode)
    }

    private func createDownloadedFile(for episode: Episode) {
        let path = downloadManager.pathForEpisode(episode)
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data())
    }
}
