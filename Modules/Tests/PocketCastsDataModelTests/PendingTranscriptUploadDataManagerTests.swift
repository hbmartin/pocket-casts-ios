import GRDB
@testable import PocketCastsDataModel
import XCTest

final class PendingTranscriptUploadDataManagerTests: XCTestCase {
    private var dataManager: DataManager!

    override func setUp() {
        super.setUp()
        dataManager = DataManager.newTestDataManager()
    }

    override func tearDown() {
        dataManager = nil
        super.tearDown()
    }

    private func makeRecord(episodeUuid: String = "ep-1",
                            podcastUuid: String = "pod-1",
                            kind: PendingTranscriptUploadKind = .contribution,
                            payloadJson: String = "{}",
                            addedDate: Double = 0,
                            nextAttemptAt: Double? = nil) -> PendingTranscriptUploadRecord {
        var record = PendingTranscriptUploadRecord()
        record.episodeUuid = episodeUuid
        record.podcastUuid = podcastUuid
        record.uploadKind = kind
        record.payloadJson = payloadJson
        record.addedDate = addedDate
        record.nextAttemptAt = nextAttemptAt
        return record
    }

    // MARK: - Migration

    func testMigrationCreatesPendingTranscriptUploadSchemaOnFreshDatabase() throws {
        try dataManager.testDbQueue.dbPool.read { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1
            XCTAssertGreaterThanOrEqual(version, 83, "Migration 83 should have run on a fresh database")

            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")
            XCTAssertTrue(names.contains("PendingTranscriptUpload"))
            XCTAssertTrue(names.contains("pending_transcript_upload_episode_kind"))
            XCTAssertTrue(names.contains("pending_transcript_upload_due"))
        }
    }

    // MARK: - Insert

    func testInsertAssignsIdAndStampsAddedDate() throws {
        XCTAssertTrue(dataManager.pendingTranscriptUploads.insert(makeRecord()))

        let row = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first)
        XCTAssertNotNil(row.id, "SQLite must assign the AUTOINCREMENT primary key")
        XCTAssertEqual(row.episodeUuid, "ep-1")
        XCTAssertEqual(row.podcastUuid, "pod-1")
        XCTAssertEqual(row.uploadKind, .contribution)
        XCTAssertEqual(row.attempts, 0)
        XCTAssertNil(row.nextAttemptAt)
        XCTAssertEqual(row.addedDate, Date().timeIntervalSince1970, accuracy: 5)
    }

    func testInsertAllowsMultipleContributionsForTheSameEpisode() {
        XCTAssertTrue(dataManager.pendingTranscriptUploads.insert(makeRecord()))
        XCTAssertTrue(dataManager.pendingTranscriptUploads.insert(makeRecord()))
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 2)
    }

    func testInsertIfAbsentDeduplicatesOnEpisodeAndKind() {
        XCTAssertTrue(dataManager.pendingTranscriptUploads.insertIfAbsent(makeRecord(kind: .sighting)))
        XCTAssertFalse(dataManager.pendingTranscriptUploads.insertIfAbsent(makeRecord(kind: .sighting)),
                       "The same (episodeUuid, kind) must not insert twice")
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 1)

        // A different kind for the same episode is a different pending upload.
        XCTAssertTrue(dataManager.pendingTranscriptUploads.insertIfAbsent(makeRecord(kind: .contribution)))
        // And a different episode with the same kind is too.
        XCTAssertTrue(dataManager.pendingTranscriptUploads.insertIfAbsent(makeRecord(episodeUuid: "ep-2", kind: .sighting)))
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 3)
    }

    // MARK: - nextDue

    func testNextDueReturnsOldestDueRow() {
        let now = Date()
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-late", addedDate: 200))
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-early", addedDate: 100))
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-backed-off",
                                                               addedDate: 50,
                                                               nextAttemptAt: now.timeIntervalSince1970 + 3600))

        let due = dataManager.pendingTranscriptUploads.nextDue(at: now)
        XCTAssertEqual(due?.episodeUuid, "ep-early",
                       "Oldest addedDate wins among due rows; future nextAttemptAt rows are skipped")
    }

    func testNextDueIncludesRowsWhoseNextAttemptHasPassed() {
        let now = Date()
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-due",
                                                               addedDate: 100,
                                                               nextAttemptAt: now.timeIntervalSince1970 - 1))

        XCTAssertEqual(dataManager.pendingTranscriptUploads.nextDue(at: now)?.episodeUuid, "ep-due")
    }

    func testNextDueReturnsNilWhenEverythingIsBackedOff() {
        let now = Date()
        dataManager.pendingTranscriptUploads.insert(makeRecord(nextAttemptAt: now.timeIntervalSince1970 + 60))

        XCTAssertNil(dataManager.pendingTranscriptUploads.nextDue(at: now))
    }

    // MARK: - Retry state

    func testSetRetryStateUpdatesAttemptsAndNextAttempt() throws {
        dataManager.pendingTranscriptUploads.insert(makeRecord())
        let id = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first?.id)

        let nextAttempt = Date().addingTimeInterval(120)
        XCTAssertTrue(dataManager.pendingTranscriptUploads.setRetryState(id: id, attempts: 3, nextAttemptAt: nextAttempt))

        let row = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first)
        XCTAssertEqual(row.attempts, 3)
        XCTAssertEqual(try XCTUnwrap(row.nextAttemptAt), nextAttempt.timeIntervalSince1970, accuracy: 0.001)

        // Clearing the date makes the row due immediately again.
        XCTAssertTrue(dataManager.pendingTranscriptUploads.setRetryState(id: id, attempts: 3, nextAttemptAt: nil))
        XCTAssertNil(dataManager.pendingTranscriptUploads.allRecords().first?.nextAttemptAt)
    }

    // MARK: - Deletes

    func testDeleteByIdRemovesOnlyThatRow() throws {
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-1"))
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-2"))
        let id = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first { $0.episodeUuid == "ep-1" }?.id)

        XCTAssertTrue(dataManager.pendingTranscriptUploads.delete(id: id))

        XCTAssertEqual(dataManager.pendingTranscriptUploads.allRecords().map(\.episodeUuid), ["ep-2"])
    }

    func testDeleteContributionsLeavesSightingsAndOtherEpisodesAlone() {
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-1", kind: .contribution))
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-1", kind: .contribution))
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-1", kind: .sighting))
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-2", kind: .contribution))

        XCTAssertTrue(dataManager.pendingTranscriptUploads.deleteContributions(episodeUuid: "ep-1"))

        let remaining = dataManager.pendingTranscriptUploads.allRecords()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.contains { $0.episodeUuid == "ep-1" && $0.uploadKind == .sighting })
        XCTAssertTrue(remaining.contains { $0.episodeUuid == "ep-2" && $0.uploadKind == .contribution })
    }

    // MARK: - Count

    func testCountReflectsAllRowsRegardlessOfDueTime() {
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
        dataManager.pendingTranscriptUploads.insert(makeRecord())
        dataManager.pendingTranscriptUploads.insert(makeRecord(episodeUuid: "ep-2",
                                                               nextAttemptAt: Date().timeIntervalSince1970 + 3600))
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 2)
    }

    // MARK: - Round trip

    func testPayloadJsonRoundTrips() throws {
        let payload = #"{"url":"https://example.com/t.vtt","format":"text/vtt","language":"en"}"#
        dataManager.pendingTranscriptUploads.insert(makeRecord(kind: .sighting, payloadJson: payload))

        let row = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first)
        XCTAssertEqual(row.payloadJson, payload)
    }
}
