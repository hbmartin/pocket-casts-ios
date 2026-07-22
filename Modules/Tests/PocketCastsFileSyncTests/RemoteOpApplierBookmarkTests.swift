import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsFileSync

/// Regression tests for applying merged bookmark highlight enrichment
/// (excerpt/end_time): the applier must honor the merge engine's stamped
/// LWW decision instead of the old write-once fill-in, otherwise devices
/// with different local excerpts never converge.
final class RemoteOpApplierBookmarkTests: XCTestCase {
    private var deviceA: DataManager!
    private var deviceB: DataManager!
    private var testDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("filesync-tests")
            .appendingPathComponent(UUID().uuidString)
        deviceA = try makeDataManager(name: "applier_bookmarks_deviceA.sqlite3")
        deviceB = try makeDataManager(name: "applier_bookmarks_deviceB.sqlite3")
    }

    override func tearDown() {
        deviceA = nil
        deviceB = nil
        testDirectory = nil
        super.tearDown()
    }

    private func makeDataManager(name: String) throws -> DataManager {
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        let path = testDirectory.appendingPathComponent(name).path
        var config = Configuration()
        config.busyMode = .timeout(10)
        let pool = try DatabasePool(path: path, configuration: config)
        return DataManager(dbQueue: GRDBQueue(dbPool: pool))
    }

    private func seedBookmark(on dataManager: DataManager, uuid: String, excerpt: String?, endTime: TimeInterval?) {
        let added = dataManager.bookmarks.add(
            uuid: uuid,
            episodeUuid: "ep-1",
            podcastUuid: "pod-1",
            title: "Bookmark",
            time: 30,
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
            excerpt: excerpt,
            endTime: endTime)
        XCTAssertEqual(added, uuid)
    }

    private func bookmarkOp(
        uuid: String = "bm-1", device: String, seq: UInt64, wallClockMs: Int64,
        excerpt: String? = nil, endTime: Double? = nil
    ) -> Filesync_OpEnvelope {
        var bookmark = Api_SyncUserBookmark()
        bookmark.bookmarkUuid = uuid
        bookmark.episodeUuid = "ep-1"
        bookmark.podcastUuid = "pod-1"
        if let excerpt { bookmark.excerpt = .with { $0.value = excerpt } }
        if let endTime { bookmark.endTime = .with { $0.value = endTime } }
        var record = Api_Record()
        record.bookmark = bookmark
        var envelope = Filesync_OpEnvelope()
        envelope.opID = "op-\(device)-\(seq)"
        envelope.deviceID = device
        envelope.seq = seq
        envelope.wallClockMs = wallClockMs
        envelope.record = record
        return envelope
    }

    func testDivergentExcerptsConvergeToLastWriterOnBothDevices() async {
        // Each device computed its own highlight for the same bookmark, so
        // both hold a non-nil excerpt when the other's op arrives.
        seedBookmark(on: deviceA, uuid: "bm-1", excerpt: "from device a", endTime: 10)
        seedBookmark(on: deviceB, uuid: "bm-1", excerpt: "from device b", endTime: 20)

        let ops = [
            bookmarkOp(device: "device-a", seq: 1, wallClockMs: 1000, excerpt: "from device a", endTime: 10),
            bookmarkOp(device: "device-b", seq: 1, wallClockMs: 2000, excerpt: "from device b", endTime: 20),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)

        _ = await RemoteOpApplier(dataManager: deviceA, delegate: nil).apply(state)
        _ = await RemoteOpApplier(dataManager: deviceB, delegate: nil).apply(state)

        let rowA = deviceA.bookmarks.bookmark(for: "bm-1")!
        let rowB = deviceB.bookmarks.bookmark(for: "bm-1")!
        XCTAssertEqual(rowA.excerpt, "from device b",
                       "device a must adopt the LWW winner even though it has its own excerpt")
        XCTAssertEqual(rowA.endTime, 20)
        XCTAssertEqual(rowB.excerpt, "from device b")
        XCTAssertEqual(rowB.endTime, 20)
    }

    func testEndTimeOnlyChangeWithSameExcerptIsApplied() async {
        seedBookmark(on: deviceA, uuid: "bm-2", excerpt: "same quote", endTime: 5)

        let ops = [
            bookmarkOp(uuid: "bm-2", device: "device-b", seq: 1, wallClockMs: 2000,
                       excerpt: "same quote", endTime: 9),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        _ = await RemoteOpApplier(dataManager: deviceA, delegate: nil).apply(state)

        let row = deviceA.bookmarks.bookmark(for: "bm-2")!
        XCTAssertEqual(row.excerpt, "same quote")
        XCTAssertEqual(row.endTime, 9,
                       "an end-time-only change must be applied even when the excerpt is unchanged")
    }

    func testEndTimeAppliesIndependentlyWithoutClearingLocalExcerpt() async {
        seedBookmark(on: deviceA, uuid: "bm-3", excerpt: "local excerpt", endTime: 5)

        let ops = [
            bookmarkOp(uuid: "bm-3", device: "device-b", seq: 1, wallClockMs: 2000, endTime: 12),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        _ = await RemoteOpApplier(dataManager: deviceA, delegate: nil).apply(state)

        let row = deviceA.bookmarks.bookmark(for: "bm-3")!
        XCTAssertEqual(row.endTime, 12)
        XCTAssertEqual(row.excerpt, "local excerpt",
                       "a merged record without an excerpt must not clear the local one")
    }
}
