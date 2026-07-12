import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsFileSync

final class FlushIngestRoundTripTests: XCTestCase {
    private var deviceA: DataManager!
    private var deviceB: DataManager!
    private var folder: InMemorySyncFolder!
    private var testDirectory: URL!

    override func setUp() {
        super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("filesync-tests")
            .appendingPathComponent(UUID().uuidString)
        deviceA = makeDataManager(name: "roundtrip_deviceA.sqlite3")
        deviceB = makeDataManager(name: "roundtrip_deviceB.sqlite3")
        folder = InMemorySyncFolder()
    }

    override func tearDown() {
        deviceA = nil
        deviceB = nil
        folder = nil
        testDirectory = nil
        super.tearDown()
    }

    private func makeDataManager(name: String) -> DataManager {
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        let path = testDirectory.appendingPathComponent(name).path
        var config = Configuration()
        config.busyMode = .timeout(10)
        let pool = try! DatabasePool(path: path, configuration: config)
        return DataManager(dbQueue: GRDBQueue(dbPool: pool))
    }

    private func seedEpisode(on dataManager: DataManager, uuid: String, podcastUuid: String) -> Episode {
        var podcast = Podcast()
        podcast.uuid = podcastUuid
        podcast.subscribed = 1
        podcast.addedDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = dataManager.save(podcast: podcast)

        var episode = Episode()
        episode.uuid = uuid
        episode.podcastUuid = podcastUuid
        episode.addedDate = Date()
        dataManager.save(episode: episode)
        return dataManager.findEpisode(uuid: uuid)!
    }

    func testEpisodeStateConvergesAcrossDevices() async throws {
        let episodeA = seedEpisode(on: deviceA, uuid: "ep-1", podcastUuid: "pod-1")
        deviceA.saveEpisode(playedUpTo: 300, episode: episodeA, updateSyncFlag: true)
        deviceA.saveEpisode(starred: true, episode: episodeA, updateSyncFlag: true)

        let flusherA = OpJournalFlusher(folder: folder, dataManager: deviceA, deviceID: "device-a")
        let flushResult = try await flusherA.flush(settings: [], stats: nil)
        XCTAssertGreaterThan(flushResult.flushedOps, 0)
        XCTAssertEqual(deviceA.unflushedFileSyncCount(), 0)

        _ = seedEpisode(on: deviceB, uuid: "ep-1", podcastUuid: "pod-1")

        let ingestorB = RemoteOpIngestor(folder: folder, dataManager: deviceB, deviceID: "device-b")
        let ingest = try await ingestorB.ingest()
        XCTAssertGreaterThan(ingest.opsRead, 0)

        let applierB = RemoteOpApplier(dataManager: deviceB, delegate: nil)
        _ = await applierB.apply(ingest.state)
        ingestorB.commit(ingest)

        let converged = deviceB.findEpisode(uuid: "ep-1")!
        XCTAssertEqual(converged.playedUpTo, 300, accuracy: 0.5)
        XCTAssertTrue(converged.keepEpisode)

        let again = try await ingestorB.ingest()
        XCTAssertEqual(again.opsRead, 0)
    }

    func testAppliedChangesDoNotEchoBack() async throws {
        let episodeA = seedEpisode(on: deviceA, uuid: "ep-2", podcastUuid: "pod-2")
        deviceA.saveEpisode(playedUpTo: 100, episode: episodeA, updateSyncFlag: true)
        let flusherA = OpJournalFlusher(folder: folder, dataManager: deviceA, deviceID: "device-a")
        _ = try await flusherA.flush(settings: [], stats: nil)

        _ = seedEpisode(on: deviceB, uuid: "ep-2", podcastUuid: "pod-2")
        deviceB.deleteAllFileSyncJournalEntries()

        let ingestorB = RemoteOpIngestor(folder: folder, dataManager: deviceB, deviceID: "device-b")
        let ingest = try await ingestorB.ingest()
        _ = await RemoteOpApplier(dataManager: deviceB, delegate: nil).apply(ingest.state)

        XCTAssertEqual(deviceB.unflushedFileSyncCount(), 0)
    }

    func testUpNextReplaceConverges() async throws {
        _ = seedEpisode(on: deviceA, uuid: "ep-q1", podcastUuid: "pod-q")
        var second = Episode()
        second.uuid = "ep-q2"
        second.podcastUuid = "pod-q"
        second.addedDate = Date()
        deviceA.save(episode: second)

        deviceA.saveReplace(episodeList: ["ep-q1", "ep-q2"])
        let flusherA = OpJournalFlusher(folder: folder, dataManager: deviceA, deviceID: "device-a")
        _ = try await flusherA.flush(settings: [], stats: nil)

        _ = seedEpisode(on: deviceB, uuid: "ep-q1", podcastUuid: "pod-q")
        var secondB = Episode()
        secondB.uuid = "ep-q2"
        secondB.podcastUuid = "pod-q"
        secondB.addedDate = Date()
        deviceB.save(episode: secondB)

        let ingestorB = RemoteOpIngestor(folder: folder, dataManager: deviceB, deviceID: "device-b")
        let ingest = try await ingestorB.ingest()
        _ = await RemoteOpApplier(dataManager: deviceB, delegate: nil).apply(ingest.state)

        let queue = deviceB.allUpNextEpisodes().map(\.uuid)
        XCTAssertEqual(queue, ["ep-q1", "ep-q2"])
    }

    func testFlusherCoalescesRepeatedPositionUpdates() async throws {
        let episode = seedEpisode(on: deviceA, uuid: "ep-3", podcastUuid: "pod-3")
        for position in [10.0, 20.0, 30.0] {
            deviceA.saveEpisode(playedUpTo: position, episode: episode, updateSyncFlag: true)
        }
        let flusher = OpJournalFlusher(folder: folder, dataManager: deviceA, deviceID: "device-a")
        let result = try await flusher.flush(settings: [], stats: nil)

        let logPath = "\(FileSyncFormat.deviceDirectory(deviceID: "device-a"))/\(FileSyncFormat.logFileName(index: 1))"
        let data = await folder.contents(of: logPath)
        let decoded = try OpLogFile.decode(data ?? Data())
        let episodeOps = decoded.envelopes.filter {
            if case .record(let record)? = $0.payload, case .episode? = record.record { return true }
            return false
        }
        XCTAssertEqual(episodeOps.count, 1)
        if case .record(let record)? = episodeOps.first?.payload {
            XCTAssertEqual(record.episode.playedUpTo.value, 30)
        }
        XCTAssertGreaterThan(result.headSeq, 0)
    }

    func testFlusherStampsStatsEnvelopeWithInjectedClock() async throws {
        // Unique device id so the flush digest persisted in UserDefaults by
        // earlier runs can never suppress this flush.
        let deviceID = "device-clock-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "FileSync.flushDigest.\(deviceID)") }

        var stats = Filesync_StatsCumulative()
        stats.timeListened = 42

        let flusher = OpJournalFlusher(
            folder: folder, dataManager: deviceA, deviceID: deviceID,
            now: { 1_234_567 })
        let result = try await flusher.flush(settings: [], stats: stats)
        XCTAssertEqual(result.flushedOps, 1)

        let logPath = "\(FileSyncFormat.deviceDirectory(deviceID: deviceID))/\(FileSyncFormat.logFileName(index: 1))"
        let data = await folder.contents(of: logPath)
        let decoded = try OpLogFile.decode(data ?? Data())
        XCTAssertEqual(decoded.envelopes.count, 1)
        XCTAssertEqual(decoded.envelopes.first?.wallClockMs, 1_234_567,
                       "the stats envelope must be stamped by the injected clock, not Date()")
    }
}
