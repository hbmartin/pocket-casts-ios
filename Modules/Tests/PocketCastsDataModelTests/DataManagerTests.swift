@testable import PocketCastsDataModel
@testable import PocketCastsUtils
import XCTest

/// Tests for DataManager methods that have complex logic combining data from multiple managers.
/// These tests focus on functionality unique to DataManager that isn't covered by
/// EpisodeDataManagerTests.
final class DataManagerTests: DataManagerTestCase {

    // MARK: - allUpNextEpisodes

    func testAllUpNextEpisodesReturnsEmptyWhenNoEpisodes() throws {
        try runWithBothImplementations { dataManager, impl in
            let result = dataManager.allUpNextEpisodes()
            XCTAssertTrue(result.isEmpty, "\(impl): should return empty array when no up next episodes")
        }
    }

    func testAllUpNextEpisodesReturnsOnlyEpisodes() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode1 = createTestEpisode(uuid: "episode-1", podcast: podcast, dataManager: dataManager)
            let episode2 = createTestEpisode(uuid: "episode-2", podcast: podcast, dataManager: dataManager)

            addToUpNextBottom(episodeUuid: episode1.uuid, podcastUuid: podcast.uuid, dataManager: dataManager)
            addToUpNextBottom(episodeUuid: episode2.uuid, podcastUuid: podcast.uuid, dataManager: dataManager)

            let result = dataManager.allUpNextEpisodes()
            XCTAssertEqual(result.count, 2, "\(impl): should return 2 episodes")
            XCTAssertEqual(result.map(\.uuid), [episode1.uuid, episode2.uuid], "\(impl): should return episodes in order")
        }
    }

    // MARK: - findBaseEpisode(uuid:)

    func testFindBaseEpisodeByUuidFindsRegularEpisode() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode = createTestEpisode(uuid: "test-episode", podcast: podcast, dataManager: dataManager)

            let found = dataManager.findBaseEpisode(uuid: episode.uuid)
            XCTAssertNotNil(found, "\(impl): should find regular episode")
            XCTAssertEqual(found?.uuid, episode.uuid, "\(impl): should have correct uuid")
            XCTAssertTrue(found is Episode, "\(impl): should be an Episode type")
        }
    }

    func testFindBaseEpisodeByUuidReturnsNilForNonexistent() throws {
        try runWithBothImplementations { dataManager, impl in
            let found = dataManager.findBaseEpisode(uuid: "nonexistent-uuid")
            XCTAssertNil(found, "\(impl): should return nil for nonexistent uuid")
        }
    }

    // MARK: - findBaseEpisode(downloadTaskId:)

    func testFindBaseEpisodeByDownloadTaskIdFindsRegularEpisode() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode = createTestEpisode(uuid: "test-episode", podcast: podcast, downloadTaskId: "task-123", dataManager: dataManager)

            let found = dataManager.findBaseEpisode(downloadTaskId: "task-123")
            XCTAssertNotNil(found, "\(impl): should find regular episode by download task id")
            XCTAssertEqual(found?.uuid, episode.uuid, "\(impl): should have correct uuid")
        }
    }

    func testFindBaseEpisodeByDownloadTaskIdReturnsNilForNonexistent() throws {
        try runWithBothImplementations { dataManager, impl in
            let found = dataManager.findBaseEpisode(downloadTaskId: "nonexistent-task")
            XCTAssertNil(found, "\(impl): should return nil for nonexistent download task id")
        }
    }

    // MARK: - downloadedEpisodeCount

    func testDownloadedEpisodeCountCountsDownloadedEpisodes() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)

            createTestEpisode(uuid: "ep-1", podcast: podcast, episodeStatus: DownloadStatus.downloaded.rawValue, dataManager: dataManager)
            createTestEpisode(uuid: "ep-2", podcast: podcast, episodeStatus: DownloadStatus.downloaded.rawValue, dataManager: dataManager)
            createTestEpisode(uuid: "ep-3", podcast: podcast, episodeStatus: DownloadStatus.notDownloaded.rawValue, dataManager: dataManager)

            let count = dataManager.downloadedEpisodeCount()
            XCTAssertEqual(count, 2, "\(impl): should return downloaded episode count")
        }
    }

    // MARK: - findDownloadedEpisodes

    func testFindDownloadedEpisodesReturnsEmptyWhenNone() throws {
        try runWithBothImplementations { dataManager, impl in
            let episodes = dataManager.findDownloadedEpisodes()
            XCTAssertTrue(episodes.isEmpty, "\(impl): should return empty when no downloaded episodes")
        }
    }

    func testFindDownloadedEpisodesReturnsDownloadedEpisodes() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)

            let episode = Episode()
            episode.uuid = "downloaded-ep"
            episode.podcastUuid = podcast.uuid
            episode.podcast_id = podcast.id
            episode.addedDate = Date()
            episode.episodeStatus = DownloadStatus.downloaded.rawValue
            episode.lastDownloadAttemptDate = Date(timeIntervalSince1970: 1000)
            dataManager.save(episode: episode)

            let episodes = dataManager.findDownloadedEpisodes()
            XCTAssertEqual(episodes.count, 1, "\(impl): should return downloaded episode")
            XCTAssertEqual(episodes[0].uuid, episode.uuid, "\(impl): should return the downloaded episode")
        }
    }

    // MARK: - findEpisodesWhereNotNull

    func testFindEpisodesWhereNotNullReturnsMatchingEpisodes() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)

            let episode = createTestEpisode(uuid: "ep-with-error", podcast: podcast, dataManager: dataManager)
            dataManager.saveEpisode(playbackError: "Test error", episode: episode)
            createTestEpisode(uuid: "ep-no-error", podcast: podcast, dataManager: dataManager)

            let episodes = dataManager.findEpisodesWhereNotNull(propertyName: "playbackErrorDetails")
            XCTAssertEqual(episodes.count, 1, "\(impl): should return episodes with non-null playbackErrorDetails")
            let uuids = episodes.map(\.uuid)
            XCTAssertTrue(uuids.contains("ep-with-error"), "\(impl): should include matching episode")
        }
    }

    // MARK: - bulkUserFileDelete

    func testBulkUserFileDeleteMarksEpisodesAsNotDownloaded() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode = createTestEpisode(uuid: "ep-1", podcast: podcast, episodeStatus: DownloadStatus.downloaded.rawValue, dataManager: dataManager)

            dataManager.bulkUserFileDelete(baseEpisodes: [episode])

            let foundEp = dataManager.findEpisode(uuid: "ep-1")
            XCTAssertEqual(foundEp?.episodeStatus, DownloadStatus.notDownloaded.rawValue, "\(impl): episode should be not downloaded")
        }
    }

    // MARK: - episodeInUpNextAt (looks up in Up Next and matches to correct episode table)

    func testEpisodeInUpNextAtReturnsRegularEpisode() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode = createTestEpisode(uuid: "test-episode", podcast: podcast, dataManager: dataManager)
            addToUpNextBottom(episodeUuid: episode.uuid, podcastUuid: podcast.uuid, dataManager: dataManager)

            let found = dataManager.episodeInUpNextAt(index: 0)
            XCTAssertNotNil(found, "\(impl): should find episode at index 0")
            XCTAssertEqual(found?.uuid, episode.uuid, "\(impl): should have correct uuid")
            XCTAssertTrue(found is Episode, "\(impl): should be Episode type")
        }
    }

    func testEpisodeInUpNextAtReturnsNilForEmptyList() throws {
        try runWithBothImplementations { dataManager, impl in
            let found = dataManager.episodeInUpNextAt(index: 0)
            XCTAssertNil(found, "\(impl): should return nil for empty up next")
        }
    }

    func testEpisodeInUpNextAtReturnsNilForOutOfBoundsIndex() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode = createTestEpisode(uuid: "test-episode", podcast: podcast, dataManager: dataManager)
            addToUpNextBottom(episodeUuid: episode.uuid, podcastUuid: podcast.uuid, dataManager: dataManager)

            let found = dataManager.episodeInUpNextAt(index: 5)
            XCTAssertNil(found, "\(impl): should return nil for out of bounds index")
        }
    }

    // MARK: - count(query:values:) (direct SQL execution)

    func testCountQueryReturnsCorrectCount() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            createTestEpisode(uuid: "ep-1", podcast: podcast, dataManager: dataManager)
            createTestEpisode(uuid: "ep-2", podcast: podcast, dataManager: dataManager)
            createTestEpisode(uuid: "ep-3", podcast: podcast, dataManager: dataManager)

            let count = dataManager.count(
                query: "SELECT COUNT(*) FROM \(DataManager.episodeTableName) WHERE podcast_id = ?",
                values: [podcast.id]
            )
            XCTAssertEqual(count, 3, "\(impl): should return count of 3")
        }
    }

    func testCountQueryReturnsZeroForNoMatches() throws {
        try runWithBothImplementations { dataManager, impl in
            let count = dataManager.count(
                query: "SELECT COUNT(*) FROM \(DataManager.episodeTableName) WHERE podcast_id = ?",
                values: [999]
            )
            XCTAssertEqual(count, 0, "\(impl): should return 0 for no matches")
        }
    }

    // MARK: - findEpisodeCount

    func testFindEpisodeCountReturnsPodcastEpisodeCount() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            createTestEpisode(uuid: "ep-1", podcast: podcast, dataManager: dataManager)
            createTestEpisode(uuid: "ep-2", podcast: podcast, dataManager: dataManager)
            createTestEpisode(uuid: "ep-3", podcast: podcast, dataManager: dataManager)

            // Create another podcast with episodes that shouldn't be counted
            let otherPodcast = createTestPodcast(uuid: "other-podcast", dataManager: dataManager)
            createTestEpisode(uuid: "other-ep", podcast: otherPodcast, dataManager: dataManager)

            let count = dataManager.findEpisodeCount(podcastId: podcast.id)
            XCTAssertEqual(count, 3, "\(impl): should return 3 episodes for the podcast")
        }
    }

    // MARK: - playlistEpisodeCount (Up Next count)

    func testPlaylistEpisodeCountReturnsZeroForEmpty() throws {
        try runWithBothImplementations { dataManager, impl in
            let count = dataManager.playlistEpisodeCount()
            XCTAssertEqual(count, 0, "\(impl): should return 0 for empty playlist")
        }
    }

    func testPlaylistEpisodeCountReturnsCorrectCount() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode1 = createTestEpisode(uuid: "ep-1", podcast: podcast, dataManager: dataManager)
            let episode2 = createTestEpisode(uuid: "ep-2", podcast: podcast, dataManager: dataManager)

            addToUpNextBottom(episodeUuid: episode1.uuid, podcastUuid: podcast.uuid, dataManager: dataManager)
            addToUpNextBottom(episodeUuid: episode2.uuid, podcastUuid: podcast.uuid, dataManager: dataManager)

            let count = dataManager.playlistEpisodeCount()
            XCTAssertEqual(count, 2, "\(impl): should return 2 for playlist with 2 episodes")
        }
    }

    // MARK: - positionForPlaylistEpisode (Up Next position calculation)

    func testPositionForPlaylistEpisodeBottomOfList() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode = createTestEpisode(uuid: "ep-1", podcast: podcast, dataManager: dataManager)
            addToUpNextBottom(episodeUuid: episode.uuid, podcastUuid: podcast.uuid, dataManager: dataManager)

            let position = dataManager.positionForPlaylistEpisode(bottomOfList: true)
            XCTAssertEqual(position, 1, "\(impl): should return position 1 for bottom of list when 1 episode exists")
        }
    }

    func testPositionForPlaylistEpisodeTopOfList() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode = createTestEpisode(uuid: "ep-1", podcast: podcast, dataManager: dataManager)
            addToUpNextBottom(episodeUuid: episode.uuid, podcastUuid: podcast.uuid, dataManager: dataManager)

            let position = dataManager.positionForPlaylistEpisode(bottomOfList: false)
            XCTAssertEqual(position, 1, "\(impl): should return position 1 for top of list. Currently playing is 0")
        }
    }

    // MARK: - updateEpisodePlaybackInteractionDate

    func testUpdateEpisodePlaybackInteractionDateUpdatesForEpisode() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = createTestPodcast(dataManager: dataManager)
            let episode = createTestEpisode(uuid: "test-episode", podcast: podcast, lastPlaybackInteractionDate: nil, dataManager: dataManager)

            dataManager.updateEpisodePlaybackInteractionDate(episode: episode)

            let found = dataManager.findEpisode(uuid: episode.uuid)
            XCTAssertNotNil(found?.lastPlaybackInteractionDate, "\(impl): should set playback interaction date")
        }
    }
}
