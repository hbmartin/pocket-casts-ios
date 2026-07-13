import XCTest
@testable import PocketCastsDataModel

/// Tests for the B6 ValueObservation pilot API (`DatabaseObserving`): streams
/// must emit an initial value and then re-emit when a write changes the observed
/// region, with unchanged results deduplicated away.
final class ValueObservationTests: DataManagerTestCase {

    // MARK: - Badge count (subscribed unplayed)

    func testBadgeCountObservationEmitsInitialAndUpdatedValues() async throws {
        let dataManager = DataManager.newTestDataManager()
        let podcast = createTestPodcast(dataManager: dataManager)
        createTestEpisode(podcast: podcast, playingStatus: PlayingStatus.notPlayed.rawValue, dataManager: dataManager)

        let recorder = StreamRecorder(dataManager.observeBadgeCount(.subscribedUnplayed(addedAfter: nil)))

        let initial = try await recorder.value(at: 0)
        XCTAssertEqual(initial, 1, "initial emission should carry the current unplayed count")

        createTestEpisode(podcast: podcast, playingStatus: PlayingStatus.notPlayed.rawValue, dataManager: dataManager)

        let updated = try await recorder.value(at: 1)
        XCTAssertEqual(updated, 2, "an insert into the observed region should re-emit the count")
    }

    // MARK: - Playlist episode counts

    func testPlaylistEpisodeCountsObservationReflectsEpisodeInserts() async throws {
        let dataManager = DataManager.newTestDataManager()
        // PlaylistQueryBuilder reads the unsubscribed-podcast list off the shared
        // manager's cache; point it at the observed database (parity-test pattern).
        let originalSharedManager = DataManager.sharedManager
        DataManager.sharedManager = dataManager
        defer { DataManager.sharedManager = originalSharedManager }

        // Select every download status so the download rule drops out and the
        // count covers all unarchived episodes (filterDownloading is always true).
        var playlist = createTestPlaylist(dataManager: dataManager)
        playlist.filterDownloaded = true
        playlist.filterNotDownloaded = true
        playlist = dataManager.save(playlist: playlist)

        let podcast = createTestPodcast(dataManager: dataManager)
        createTestEpisode(podcast: podcast, playingStatus: PlayingStatus.notPlayed.rawValue, dataManager: dataManager)

        let recorder = StreamRecorder(dataManager.observePlaylistEpisodeCounts())

        let initial = try await recorder.value(at: 0)
        XCTAssertEqual(initial, [playlist.uuid: 1])

        createTestEpisode(podcast: podcast, playingStatus: PlayingStatus.notPlayed.rawValue, dataManager: dataManager)

        let updated = try await recorder.value(at: 1)
        XCTAssertEqual(updated, [playlist.uuid: 2])
    }

    // MARK: - Home grid

    func testHomeGridObservationEmitsOnSubscribeAndUnsubscribe() async throws {
        let dataManager = DataManager.newTestDataManager()

        let recorder = StreamRecorder(dataManager.observeHomeGrid())

        let initial = try await recorder.value(at: 0)
        XCTAssertTrue(initial.podcasts.isEmpty)
        XCTAssertTrue(initial.folders.isEmpty)

        var podcast = createTestPodcast(uuid: "grid-podcast", dataManager: dataManager)

        let afterSubscribe = try await recorder.value(at: 1)
        XCTAssertEqual(afterSubscribe.podcasts.map(\.uuid), ["grid-podcast"])

        podcast.subscribed = 0
        _ = dataManager.save(podcast: podcast)

        let afterUnsubscribe = try await recorder.value(at: 2)
        XCTAssertTrue(afterUnsubscribe.podcasts.isEmpty, "unsubscribed podcasts should leave the grid snapshot")
    }

    func testHomeGridObservationEmitsOnFolderAndBadgeChanges() async throws {
        let dataManager = DataManager.newTestDataManager()
        let podcast = createTestPodcast(dataManager: dataManager)

        let recorder = StreamRecorder(dataManager.observeHomeGrid())

        let initial = try await recorder.value(at: 0)
        XCTAssertEqual(initial.podcasts.first?.unfinishedCount, 0)

        _ = createTestFolder(uuid: "grid-folder", dataManager: dataManager)

        let afterFolder = try await recorder.value(at: 1)
        XCTAssertEqual(afterFolder.folders.map(\.uuid), ["grid-folder"])

        createTestEpisode(podcast: podcast, playingStatus: PlayingStatus.notPlayed.rawValue, dataManager: dataManager)

        let afterEpisode = try await recorder.value(at: 2)
        XCTAssertEqual(afterEpisode.podcasts.first?.unfinishedCount, 1, "unplayed-badge input changes should re-emit the snapshot")
    }
}

// MARK: - Stream recording

/// Collects a stream's emissions on a background task so tests can await "the
/// value at index N" with a timeout instead of hanging on a broken observation.
// @unchecked Sendable: `values` is only touched under `lock`; the task handle is set once in init.
private final class StreamRecorder<Value: Sendable>: @unchecked Sendable {
    enum RecorderError: Error {
        case timedOutWaitingForValue
    }

    private let lock = NSLock()
    private var values: [Value] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<Value>) {
        // Weak capture: when the test drops the recorder, the loop ends and the
        // observation is cancelled instead of living for the rest of the process.
        task = Task { [weak self] in
            for await value in stream {
                guard let self else { return }
                self.lock.withLock { self.values.append(value) }
            }
        }
    }

    deinit {
        task?.cancel()
    }

    /// Returns the `index`-th recorded value, polling until it arrives or the
    /// timeout elapses. Writes in these tests happen only after the previous
    /// value has been observed, so indices map 1:1 onto expected emissions.
    func value(at index: Int, timeout: TimeInterval = 10) async throws -> Value {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            let recorded = lock.withLock { values }
            if recorded.count > index {
                return recorded[index]
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw RecorderError.timedOutWaitingForValue
    }
}
