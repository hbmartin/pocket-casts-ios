import GRDB
@testable import PocketCastsDataModel
import XCTest

final class TranscriptionDataManagerTests: XCTestCase {
    private var dataManager: DataManager!

    override func setUp() {
        super.setUp()
        dataManager = DataManager.newTestDataManager()
    }

    override func tearDown() {
        dataManager = nil
        super.tearDown()
    }

    // MARK: - Migration

    func testMigrationCreatesTranscriptionSchemaOnFreshDatabase() throws {
        try dataManager.testDbQueue.dbPool.read { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1
            XCTAssertGreaterThanOrEqual(version, 78, "Migration 78 should have run on a fresh database")
            XCTAssertEqual(version, Int(DatabaseHelper.currentSchemaVersion(for: DatabaseHelper.migrations)))

            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")
            XCTAssertTrue(names.contains("EpisodeTranscription"))
            XCTAssertTrue(names.contains("episode_transcription_status"))
        }
    }

    // MARK: - Upsert / Find

    func testFindReturnsNilForUnknownEpisode() {
        XCTAssertNil(dataManager.transcriptions.find(episodeUuid: "nope"))
    }

    func testUpsertInsertAndUpdateRoundTripsAllColumns() {
        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = "ep-1"
        record.podcastUuid = "pod-1"
        record.transcriptionStatus = .processing
        record.engineMode = 2
        record.provider = "assemblyai"
        record.modelId = "large-v3-turbo"
        record.language = "en"
        record.createdAt = 100
        record.updatedAt = 200
        record.durationSecs = 3600.5
        record.speakerCount = 3
        record.speakerNames = #"{"Speaker 1":"Alice"}"#
        record.errorMessage = "transient failure"
        record.remoteJobId = "job-1"
        record.filePath = "generated_transcripts/ep-1.vtt"

        XCTAssertTrue(dataManager.transcriptions.upsert(record))
        XCTAssertEqual(dataManager.transcriptions.find(episodeUuid: "ep-1"), record)

        record.transcriptionStatus = .completed
        record.errorMessage = nil
        record.remoteJobId = nil
        record.speakerCount = 2
        record.updatedAt = 300

        XCTAssertTrue(dataManager.transcriptions.upsert(record))
        XCTAssertEqual(dataManager.transcriptions.find(episodeUuid: "ep-1"), record)
        XCTAssertEqual(recordCount(), 1, "Upserting the same episode twice should keep a single row")
    }

    // MARK: - Field updates

    func testSetStatusUpdatesStatusErrorMessageAndUpdatedAt() throws {
        upsertRecord(episodeUuid: "ep-1", status: .queued)

        XCTAssertTrue(dataManager.transcriptions.setStatus(episodeUuid: "ep-1", status: .failed, errorMessage: "network down"))
        var found = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "ep-1"))
        XCTAssertEqual(found.transcriptionStatus, .failed)
        XCTAssertEqual(found.errorMessage, "network down")
        XCTAssertGreaterThan(found.updatedAt, 0, "setStatus should bump updatedAt")

        XCTAssertTrue(dataManager.transcriptions.setStatus(episodeUuid: "ep-1", status: .completed))
        found = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "ep-1"))
        XCTAssertEqual(found.transcriptionStatus, .completed)
        XCTAssertNil(found.errorMessage, "Moving to a new status without an error should clear the old error")
    }

    func testSetRemoteJobId() throws {
        upsertRecord(episodeUuid: "ep-1", status: .processing)

        XCTAssertTrue(dataManager.transcriptions.setRemoteJobId(episodeUuid: "ep-1", jobId: "job-42"))
        var found = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "ep-1"))
        XCTAssertEqual(found.remoteJobId, "job-42")
        XCTAssertGreaterThan(found.updatedAt, 0)

        XCTAssertTrue(dataManager.transcriptions.setRemoteJobId(episodeUuid: "ep-1", jobId: nil))
        found = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "ep-1"))
        XCTAssertNil(found.remoteJobId)
    }

    func testSetSpeakerNames() throws {
        upsertRecord(episodeUuid: "ep-1", status: .completed)

        let namesJSON = #"{"Speaker 1":"Alice","Speaker 2":"Bob"}"#
        XCTAssertTrue(dataManager.transcriptions.setSpeakerNames(episodeUuid: "ep-1", namesJSON: namesJSON))
        var found = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "ep-1"))
        XCTAssertEqual(found.speakerNames, namesJSON)
        XCTAssertGreaterThan(found.updatedAt, 0)

        XCTAssertTrue(dataManager.transcriptions.setSpeakerNames(episodeUuid: "ep-1", namesJSON: nil))
        found = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "ep-1"))
        XCTAssertNil(found.speakerNames)
    }

    // MARK: - Pending / counts

    func testPendingRecordsReturnsQueuedAndProcessingOldestFirst() {
        upsertRecord(episodeUuid: "ep-queued", status: .queued, createdAt: 20)
        upsertRecord(episodeUuid: "ep-processing", status: .processing, createdAt: 10)
        upsertRecord(episodeUuid: "ep-completed", status: .completed, createdAt: 1)
        upsertRecord(episodeUuid: "ep-failed", status: .failed, createdAt: 2)
        upsertRecord(episodeUuid: "ep-cancelled", status: .cancelled, createdAt: 3)

        let pending = dataManager.transcriptions.pendingRecords()
        XCTAssertEqual(pending.map(\.episodeUuid), ["ep-processing", "ep-queued"])
    }

    func testCompletedCount() {
        XCTAssertEqual(dataManager.transcriptions.completedCount(), 0)

        upsertRecord(episodeUuid: "ep-1", status: .completed)
        upsertRecord(episodeUuid: "ep-2", status: .completed)
        upsertRecord(episodeUuid: "ep-3", status: .queued)
        upsertRecord(episodeUuid: "ep-4", status: .failed)

        XCTAssertEqual(dataManager.transcriptions.completedCount(), 2)
    }

    func testExistingEpisodeUuidsResolvesPodcastAndUserEpisodesAsOneBatch() {
        var podcastEpisode = Episode()
        podcastEpisode.uuid = "podcast-episode"
        dataManager.save(episode: podcastEpisode)
        var userEpisode = UserEpisode()
        userEpisode.uuid = "user-episode"
        dataManager.save(episode: userEpisode)

        let existing = dataManager.transcriptions.existingEpisodeUuids([
            "podcast-episode",
            "user-episode",
            "missing",
            "podcast-episode"
        ])

        XCTAssertEqual(existing, ["podcast-episode", "user-episode"])
        XCTAssertTrue(dataManager.transcriptions.existingEpisodeUuids([]).isEmpty)
    }

    // MARK: - Delete

    func testDeleteRemovesOnlyTheGivenRecord() {
        upsertRecord(episodeUuid: "ep-1", status: .completed)
        upsertRecord(episodeUuid: "ep-2", status: .completed)

        XCTAssertTrue(dataManager.transcriptions.delete(episodeUuid: "ep-1"))

        XCTAssertNil(dataManager.transcriptions.find(episodeUuid: "ep-1"))
        XCTAssertNotNil(dataManager.transcriptions.find(episodeUuid: "ep-2"))
    }

    // MARK: - Helpers

    @discardableResult
    private func upsertRecord(episodeUuid: String, status: TranscriptionStatus, createdAt: Double = 0) -> EpisodeTranscriptionRecord {
        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = episodeUuid
        record.podcastUuid = "pod-1"
        record.transcriptionStatus = status
        record.createdAt = createdAt
        XCTAssertTrue(dataManager.transcriptions.upsert(record))
        return record
    }

    private func recordCount() -> Int {
        dataManager.count(query: "SELECT COUNT(*) FROM \(TranscriptionDataManager.tableName)", values: nil)
    }
}
