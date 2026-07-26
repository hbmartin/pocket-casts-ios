import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Base test class for DataManager tests. Historically this ran each test twice
/// (raw SQL and GRDB); the raw-SQL paths were deleted with the grdbQueryInterface
/// flag, so `runWithBothImplementations` keeps its name for the 500+ call sites
/// but now runs once against the GRDB implementation.
///
/// Subclasses should:
/// 1. Override `setUpWithDataManager(_:)` to set up test data
/// 2. Override `tearDownWithDataManager(_:)` if additional cleanup is needed
/// 3. Call `runWithBothImplementations { ... }` in test methods
///
/// Example:
/// ```
/// final class EpisodeDataManagerTests: DataManagerTestCase {
///     func testFindEpisodeByUuid() async throws {
///         try await runWithBothImplementations { dataManager, implementationName in
///             let podcast = self.createTestPodcast(dataManager: dataManager)
///             var episode = self.createTestEpisode(podcast: podcast, dataManager: dataManager)
///             let found = dataManager.findEpisode(uuid: episode.uuid)
///             XCTAssertNotNil(found, "\(implementationName) should find episode")
///         }
///     }
/// }
/// ```
class DataManagerTestCase: XCTestCase {
    /// Runs the provided test block against the GRDB implementation.
    ///
    /// - Parameter testBlock: A closure that receives a fresh DataManager and the
    ///                        implementation name ("GRDB").
    func runWithBothImplementations(_ testBlock: (DataManager, String) throws -> Void) throws {
        let grdbDataManager = DataManager.newTestDataManager()
        try testBlock(grdbDataManager, "GRDB")
    }

    /// Async version of runWithBothImplementations
    func runWithBothImplementations(_ testBlock: (DataManager, String) async throws -> Void) async throws {
        let grdbDataManager = DataManager.newTestDataManager()
        try await testBlock(grdbDataManager, "GRDB")
    }

    // MARK: - Common Test Helpers

    /// Creates a test podcast with the given properties
    func createTestPodcast(
        uuid: String = UUID().uuidString,
        title: String = "Test Podcast",
        subscribed: Int32 = 1,
        sortOrder: Int32 = 0,
        folderUuid: String? = nil,
        dataManager: DataManager
    ) -> Podcast {
        var podcast = Podcast()
        podcast.uuid = uuid
        podcast.title = title
        podcast.subscribed = subscribed
        podcast.sortOrder = sortOrder
        podcast.folderUuid = folderUuid
        podcast.addedDate = Date()
        // Return the saved value (mirrors createTestFolder/createTestPlaylist) so callers see the
        // assigned id and stay correct once Podcast becomes a value-type struct.
        return dataManager.save(podcast: podcast)
    }

    /// Creates a test episode with the given properties
    @discardableResult
    func createTestEpisode(
        uuid: String = UUID().uuidString,
        podcast: Podcast,
        title: String = "Test Episode",
        publishedDate: Date? = Date(),
        episodeStatus: Int32 = 0,
        playingStatus: Int32 = 0,
        playedUpTo: Double = 0,
        archived: Bool = false,
        wasDeleted: Bool = false,
        lastPlaybackInteractionDate: Date? = nil,
        downloadTaskId: String? = nil,
        dataManager: DataManager
    ) -> Episode {
        var episode = Episode()
        episode.uuid = uuid
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.title = title
        episode.publishedDate = publishedDate
        episode.addedDate = Date()
        episode.episodeStatus = episodeStatus
        episode.playingStatus = playingStatus
        episode.playedUpTo = playedUpTo
        episode.archived = archived
        episode.wasDeleted = wasDeleted
        episode.lastPlaybackInteractionDate = lastPlaybackInteractionDate
        episode.downloadTaskId = downloadTaskId
        episode = dataManager.save(episode: episode)
        return episode
    }

    /// Creates a test playlist with the given properties
    func createTestPlaylist(
        uuid: String = UUID().uuidString,
        name: String = "Test Playlist",
        manual: Bool = false,
        sortPosition: Int32 = 0,
        syncStatus: Int32 = SyncStatus.notSynced.rawValue,
        wasDeleted: Bool = false,
        dataManager: DataManager
    ) -> EpisodeFilter {
        var playlist = EpisodeFilter()
        playlist.uuid = uuid
        playlist.playlistName = name
        playlist.manual = manual
        playlist.sortPosition = sortPosition
        playlist.syncStatus = syncStatus
        playlist.wasDeleted = wasDeleted
        // Return the saved value (mirrors createTestFolder) so callers see the assigned id and stay
        // correct once EpisodeFilter becomes a value-type struct.
        return dataManager.save(playlist: playlist)
    }

    /// Creates a test user episode with the given properties
    func createTestUserEpisode(
        uuid: String = UUID().uuidString,
        title: String = "Test User Episode",
        episodeStatus: Int32 = DownloadStatus.notDownloaded.rawValue,
        uploadStatus: Int32 = 0,
        addedDate: Date = Date(),
        duration: Double = 3600,
        dataManager: DataManager
    ) -> UserEpisode {
        var episode = UserEpisode()
        episode.uuid = uuid
        episode.title = title
        episode.episodeStatus = episodeStatus
        episode.uploadStatus = uploadStatus
        episode.addedDate = addedDate
        episode.duration = duration
        episode = dataManager.save(episode: episode)
        return episode
    }

    /// Creates a test folder with the given properties
    func createTestFolder(
        uuid: String = UUID().uuidString,
        name: String = "Test Folder",
        color: Int32 = 0,
        sortOrder: Int32 = 0,
        dataManager: DataManager
    ) -> Folder {
        var folder = Folder()
        folder.uuid = uuid
        folder.name = name
        folder.color = color
        folder.sortOrder = sortOrder
        folder.addedDate = Date()
        return dataManager.save(folder: folder)
    }

    /// Adds an episode to the Up Next playlist at the bottom
    func addToUpNextBottom(
        episodeUuid: String,
        title: String = "Test Episode",
        podcastUuid: String = "",
        dataManager: DataManager
    ) {
        let playlistEpisode = PlaylistEpisode(
            episodePosition: dataManager.positionForPlaylistEpisode(bottomOfList: true),
            episodeUuid: episodeUuid,
            title: title,
            podcastUuid: podcastUuid
        )
        dataManager.save(playlistEpisode: playlistEpisode)
    }

    /// Adds an episode to the Up Next playlist at the top
    func addToUpNextTop(
        episodeUuid: String,
        title: String = "Test Episode",
        podcastUuid: String = "",
        dataManager: DataManager
    ) {
        let playlistEpisode = PlaylistEpisode(
            episodePosition: dataManager.positionForPlaylistEpisode(bottomOfList: false),
            episodeUuid: episodeUuid,
            title: title,
            podcastUuid: podcastUuid
        )
        dataManager.save(playlistEpisode: playlistEpisode)
    }
}
