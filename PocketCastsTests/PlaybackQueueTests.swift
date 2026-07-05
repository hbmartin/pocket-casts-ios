import XCTest
@testable import podcasts
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

final class PlaybackQueueTests: XCTestCase {

    private let featureFlagMock = FeatureFlagMock()
    private var originalDataManager: DataManager!

    override func setUp() {
        super.setUp()
        originalDataManager = DataManager.sharedManager
    }

    func testOverrideAllEpisodesWith_shouldNotIncludeStaleEpisodesInReplace() {
        featureFlagMock.set(.replaceSpecificEpisode, value: true)

        let playbackQueue = PlaybackQueue()
        let mockDataManager = MockDataManager()
        DataManager.sharedManager = mockDataManager

        let staleEpisode = PlaylistEpisode()
        staleEpisode.episodeUuid = "stale-uuid"
        staleEpisode.title = "Stale Episode"
        mockDataManager.upNextEpisodes = [staleEpisode]
        mockDataManager.delayCacheClearUntilManuallyCalled()

        let newEpisode = UserEpisode()
        newEpisode.uuid = "current-uuid"
        newEpisode.title = "Current Episode"

        playbackQueue.overrideAllEpisodesWith(episode: newEpisode)

        // Simulate delayed clearing of the cache
        mockDataManager.manuallyClearCache()

        // The replacement list should only contain the current episode (added later), not the stale one
        XCTAssertFalse(mockDataManager.savedReplaceEpisodes.contains("stale-uuid"),
                       "Should not include stale episode UUID in replacement list")
    }

    func testAddPostsToTopFlagWhenAddingToTop() throws {
        try assertAddPostsToTopFlag(toTop: true)
    }

    func testAddPostsToTopFlagWhenAddingToBottom() throws {
        try assertAddPostsToTopFlag(toTop: false)
    }

    func testReorderUpNextPersistsNewOrderAndKeepsMissingEntriesAtBottom() {
        let playbackQueue = PlaybackQueue()
        let mockDataManager = MockDataManager()
        DataManager.sharedManager = mockDataManager

        // Position 0 is the now playing episode, which stays pinned and isn't reordered.
        mockDataManager.upNextEpisodes = [
            playlistEpisode(uuid: "now-playing", position: 0),
            playlistEpisode(uuid: "a", position: 1),
            playlistEpisode(uuid: "b", position: 2),
            playlistEpisode(uuid: "missing", position: 3) // no matching episode in sortedEpisodes
        ]

        // Desired new order for the known episodes.
        playbackQueue.reorderUpNext(sortedEpisodes: [episode("b"), episode("a")])

        let savedUuids = mockDataManager.savedPlaylistEpisodes.map { $0.episodeUuid }
        let savedPositions = mockDataManager.savedPlaylistEpisodes.map { $0.episodePosition }

        // The known episodes follow the sorted order, the missing entry sinks to the bottom...
        XCTAssertEqual(savedUuids, ["b", "a", "missing"])
        // ...and positions start at 1 since position 0 is reserved for the now playing episode.
        XCTAssertEqual(savedPositions, [1, 2, 3])
    }

    func testReorderUpNextDoesNothingWithFewerThanTwoSortedEpisodes() {
        let playbackQueue = PlaybackQueue()
        let mockDataManager = MockDataManager()
        DataManager.sharedManager = mockDataManager

        mockDataManager.upNextEpisodes = [
            playlistEpisode(uuid: "now-playing", position: 0),
            playlistEpisode(uuid: "a", position: 1)
        ]

        playbackQueue.reorderUpNext(sortedEpisodes: [episode("a")])

        XCTAssertTrue(mockDataManager.savedPlaylistEpisodes.isEmpty, "Reordering one episode should be a no-op")
    }

    private func playlistEpisode(uuid: String, position: Int32) -> PlaylistEpisode {
        let playlistEpisode = PlaylistEpisode()
        playlistEpisode.episodeUuid = uuid
        playlistEpisode.episodePosition = position
        return playlistEpisode
    }

    private func episode(_ uuid: String) -> Episode {
        let episode = Episode()
        episode.uuid = uuid
        return episode
    }

    func testRecentUserInteractionReturnsFalseWhenNoPreviousInteraction() {
        let playbackQueue = PlaybackQueue()

        XCTAssertFalse(playbackQueue.recentUserInteraction(now: Date(timeIntervalSince1970: 15)))
    }

    func testRecentUserInteractionReturnsTrueWithinGracePeriod() {
        let playbackQueue = PlaybackQueue()
        let interactionTime = Date(timeIntervalSince1970: 1_000)
        playbackQueue.recordUpNextUserInteraction(at: interactionTime)

        XCTAssertTrue(playbackQueue.recentUserInteraction(now: interactionTime.addingTimeInterval(3)))
    }

    func testRecentUserInteractionReturnsFalseAtGracePeriodBoundary() {
        let playbackQueue = PlaybackQueue()
        let interactionTime = Date(timeIntervalSince1970: 1_000)
        playbackQueue.recordUpNextUserInteraction(at: interactionTime)

        XCTAssertFalse(playbackQueue.recentUserInteraction(now: interactionTime.addingTimeInterval(10)))
    }

    func testRecentUserInteractionReturnsFalseOutsideGracePeriod() {
        let playbackQueue = PlaybackQueue()
        let interactionTime = Date(timeIntervalSince1970: 1_000)
        playbackQueue.recordUpNextUserInteraction(at: interactionTime)

        XCTAssertFalse(playbackQueue.recentUserInteraction(now: interactionTime.addingTimeInterval(11)))
    }

    override func tearDown() {
        DataManager.sharedManager = originalDataManager
        featureFlagMock.reset()
        super.tearDown()
    }

    private func assertAddPostsToTopFlag(toTop: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let playbackQueue = PlaybackQueue()
        let mockDataManager = MockDataManager()
        DataManager.sharedManager = mockDataManager

        let episode = Episode()
        episode.uuid = "episode-\(toTop ? "top" : "bottom")"
        episode.title = "Queue Episode"
        episode.podcastUuid = "podcast-uuid"

        let expectation = XCTNSNotificationExpectation(name: Constants.Notifications.upNextEpisodeAdded)
        expectation.handler = { notification in
            XCTAssertEqual(notification.object as? String, episode.uuid, file: file, line: line)
            XCTAssertEqual(
                notification.userInfo?[Constants.Notifications.upNextEpisodeAddedToTopKey] as? Bool,
                toTop,
                file: file,
                line: line
            )
            return true
        }

        playbackQueue.add(episode: episode, fireNotification: true, toTop: toTop)

        wait(for: [expectation], timeout: 1)
    }
}

// @unchecked Sendable: restates DataManager's conformance, as Swift requires of subclasses; test-only stub state.
fileprivate class MockDataManager: DataManager, @unchecked Sendable {
    var savedReplaceEpisodes: [String] = []
    var savedPlaylistEpisodes: [PlaylistEpisode] = []
    var upNextEpisodes: [PlaylistEpisode] = []
    var deleteCalled = false
    var cacheManuallyDelayed = false

    override func findPlaylistEpisode(uuid: String) -> PlaylistEpisode? {
        upNextEpisodes.first { $0.episodeUuid == uuid }
    }

    override func positionForPlaylistEpisode(bottomOfList: Bool) -> Int32 {
        if bottomOfList, let lastEpisode = upNextEpisodes.last {
            return lastEpisode.episodePosition + 1
        }

        return 1
    }

    override func save(playlistEpisode: PlaylistEpisode) {
        upNextEpisodes.removeAll { $0.episodeUuid == playlistEpisode.episodeUuid }
        upNextEpisodes.append(playlistEpisode)
        upNextEpisodes.sort { $0.episodePosition < $1.episodePosition }
    }

    override func allUpNextEpisodes() -> [BaseEpisode] {
        upNextEpisodes.map {
            let episode = Episode()
            episode.uuid = $0.episodeUuid
            episode.title = $0.title
            episode.podcastUuid = $0.podcastUuid
            return episode
        }
    }

    override func allUpNextPlaylistEpisodes() -> [PlaylistEpisode] {
        return upNextEpisodes
    }

    override func save(playlistEpisodes: [PlaylistEpisode]) {
        savedPlaylistEpisodes = playlistEpisodes
    }

    override func deleteAllUpNextEpisodes() {
        deleteCalled = true
        if !cacheManuallyDelayed {
            upNextEpisodes.removeAll()
        }
    }

    override func saveReplace(episodeList: [String]) {
        savedReplaceEpisodes = episodeList
    }

    // Allows simulating delay in cache clearing
    func delayCacheClearUntilManuallyCalled() {
        cacheManuallyDelayed = true
    }

    func manuallyClearCache() {
        upNextEpisodes.removeAll()
    }
}
