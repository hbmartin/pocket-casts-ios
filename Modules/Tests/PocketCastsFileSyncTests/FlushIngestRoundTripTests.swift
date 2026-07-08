import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsFileSync

/// End-to-end engine test: device A journals local changes, flushes them to
/// a shared (in-memory) folder, and device B ingests + applies — the two
/// databases converge.
final class FlushIngestRoundTripTests: XCTestCase {
    private var deviceA: DataManager!
    private var deviceB: DataManager!
    private var folder: InMemorySyncFolder!

    override func setUp() {
        super.setUp()
        deviceA = makeDataManager(name: "roundtrip_deviceA.sqlite3")
        deviceB = makeDataManager(name: "roundtrip_deviceB.sqlite3")
        folder = InMemorySyncFolder()
    }

    private func makeDataManager(name: String) -> DataManager {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("filesync-tests")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try? FileManager.default.removeItem(atPath: path)
        var config = Configuration()
        config.busyMode = .timeout(10)
        let pool = try! DatabasePool(path: path, configuration: config)
        return try! DataManager(dbQueue: GRDBQueue(dbPool: pool))
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
        // Device A: user listens and stars.
        let episodeA = seedEpisode(on: deviceA, uuid: "ep-1", podcastUuid: "pod-1")
        deviceA.saveEpisode(playedUpTo: 300, episode: episodeA, updateSyncFlag: true)
        deviceA.saveEpisode(starred: true, episode: episodeA, updateSyncFlag: true)

        // Device A flushes to the shared folder.
        let flusherA = OpJournalFlusher(folder: folder, dataManager: deviceA, deviceID: "device-a")
        let flushResult = try await flusherA.flush(settings: [], stats: nil)
        XCTAssertGreaterThan(flushResult.flushedOps, 0)
        XCTAssertEqual(deviceA.unflushedFileSyncCount(), 0, "flushed entries must be marked")

        // Device B knows the same episode (same podcast subscribed) but has
        // no listening state yet.
        _ = seedEpisode(on: deviceB, uuid: "ep-1", podcastUuid: "pod-1")

        let ingestorB = RemoteOpIngestor(folder: folder, dataManager: deviceB, deviceID: "device-b")
        let ingest = try await ingestorB.ingest()
        XCTAssertGreaterThan(ingest.opsRead, 0, "device B must see device A's ops")

        let applierB = RemoteOpApplier(dataManager: deviceB, delegate: nil)
        _ = await applierB.apply(ingest.state)
        ingestorB.commit(ingest)

        let converged = deviceB.findEpisode(uuid: "ep-1")!
        XCTAssertEqual(converged.playedUpTo, 300, accuracy: 0.5)
        XCTAssertTrue(converged.keepEpisode, "star must sync")

        // Second ingest is a no-op (cursor advanced).
        let again = try await ingestorB.ingest()
        XCTAssertEqual(again.opsRead, 0, "cursors must prevent re-reading applied ops")
    }

    func testAppliedChangesDoNotEchoBack() async throws {
        let episodeA = seedEpisode(on: deviceA, uuid: "ep-2", podcastUuid: "pod-2")
        deviceA.saveEpisode(playedUpTo: 100, episode: episodeA, updateSyncFlag: true)
        let flusherA = OpJournalFlusher(folder: folder, dataManager: deviceA, deviceID: "device-a")
        _ = try await flusherA.flush(settings: [], stats: nil)

        _ = seedEpisode(on: deviceB, uuid: "ep-2", podcastUuid: "pod-2")
        deviceB.deleteAllFileSyncJournalEntries() // drop the seed noise

        let ingestorB = RemoteOpIngestor(folder: folder, dataManager: deviceB, deviceID: "device-b")
        let ingest = try await ingestorB.ingest()
        _ = await RemoteOpApplier(dataManager: deviceB, delegate: nil).apply(ingest.state)

        XCTAssertEqual(deviceB.unflushedFileSyncCount(), 0,
                       "applying remote ops must not journal new local changes")
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

        // Device B has the episodes locally (no server backfill needed).
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
        XCTAssertEqual(queue, ["ep-q1", "ep-q2"], "queue replace must apply in order")
    }

    func testFlusherCoalescesRepeatedPositionUpdates() async throws {
        let episode = seedEpisode(on: deviceA, uuid: "ep-3", podcastUuid: "pod-3")
        for position in [10.0, 20.0, 30.0] {
            deviceA.saveEpisode(playedUpTo: position, episode: episode, updateSyncFlag: true)
        }
        let flusher = OpJournalFlusher(folder: folder, dataManager: deviceA, deviceID: "device-a")
        let result = try await flusher.flush(settings: [], stats: nil)

        // One podcast op (from the seed hook) + one coalesced episode op.
        let logPath = "\(FileSyncFormat.deviceDirectory(deviceID: "device-a"))/\(FileSyncFormat.logFileName(index: 1))"
        let data = await folder.contents(of: logPath)
        let decoded = try OpLogFile.decode(data ?? Data())
        let episodeOps = decoded.envelopes.filter {
            if case .record(let record)? = $0.payload, case .episode? = record.record { return true }
            return false
        }
        XCTAssertEqual(episodeOps.count, 1, "heartbeat updates must flush as one op")
        if case .record(let record)? = episodeOps.first?.payload {
            XCTAssertEqual(record.episode.playedUpTo.value, 30, "latest position wins")
        }
        XCTAssertGreaterThan(result.headSeq, 0)
    }
}
