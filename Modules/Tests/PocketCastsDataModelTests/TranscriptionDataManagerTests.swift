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
            XCTAssertTrue(names.contains("TranscriptionSegmentFTS"))

            // The FTS5 virtual table is actually queryable, not just present in sqlite_master
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM TranscriptionSegmentFTS"), 0)
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

    // MARK: - Segments

    func testReplaceSegmentsIsIdempotent() {
        let segments = [
            TranscriptionSegment(index: 0, text: "hello world", startTime: 0, speaker: "Speaker 1"),
            TranscriptionSegment(index: 1, text: "goodbye moon", startTime: 5.5, speaker: "Speaker 2")
        ]

        XCTAssertTrue(dataManager.transcriptions.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", segments: segments))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 2)

        XCTAssertTrue(dataManager.transcriptions.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", segments: segments))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 2, "Re-running replaceSegments must not duplicate rows")

        XCTAssertTrue(dataManager.transcriptions.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", segments: [segments[0]]))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 1, "Replacing with fewer segments should shrink the set")
    }

    func testReplaceSegmentsLeavesOtherEpisodesUntouched() {
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(
            episodeUuid: "ep-1", podcastUuid: "pod-1",
            segments: [TranscriptionSegment(index: 0, text: "alpha", startTime: 0)]))
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(
            episodeUuid: "ep-2", podcastUuid: "pod-1",
            segments: [TranscriptionSegment(index: 0, text: "beta", startTime: 0)]))

        XCTAssertTrue(dataManager.transcriptions.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", segments: []))

        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 0)
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-2"), 1)
    }

    // MARK: - Search

    func testSearchSegmentsReturnsHighlightedSnippetAndFields() throws {
        let segments = [
            TranscriptionSegment(index: 3, text: "The quick brown fox jumps over the lazy dog", startTime: 12.5, speaker: "Speaker 1")
        ]
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", segments: segments))

        let results = dataManager.transcriptions.searchSegments(query: "fox")
        XCTAssertEqual(results.count, 1)

        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.episodeUuid, "ep-1")
        XCTAssertEqual(result.podcastUuid, "pod-1")
        XCTAssertEqual(result.segmentIndex, 3)
        XCTAssertEqual(result.startTime, 12.5)
        XCTAssertEqual(result.speaker, "Speaker 1")
        let highlighted = TranscriptionSearchResult.highlightStart + "fox" + TranscriptionSearchResult.highlightEnd
        XCTAssertTrue(result.snippet.contains(highlighted), "Snippet should wrap the match in highlight markers: \(result.snippet)")
    }

    func testSearchSegmentsMatchesLastTokenAsPrefix() throws {
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(
            episodeUuid: "ep-1", podcastUuid: "pod-1",
            segments: [TranscriptionSegment(index: 0, text: "The quick brown fox", startTime: 0)]))

        let results = dataManager.transcriptions.searchSegments(query: "qui")
        XCTAssertEqual(results.count, 1, "The final query token should match as a prefix while the user is typing")
        let highlighted = TranscriptionSearchResult.highlightStart + "quick" + TranscriptionSearchResult.highlightEnd
        XCTAssertTrue(try XCTUnwrap(results.first).snippet.contains(highlighted))
    }

    func testSearchSegmentsOrdersByRelevance() {
        // ep-dense mentions the term repeatedly in a short segment; ep-sparse mentions it
        // once diluted by many other words, so BM25 must rank ep-dense first.
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(
            episodeUuid: "ep-dense", podcastUuid: "pod-1",
            segments: [TranscriptionSegment(index: 0, text: "swift swift swift swift", startTime: 0)]))
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(
            episodeUuid: "ep-sparse", podcastUuid: "pod-2",
            segments: [TranscriptionSegment(index: 0, text: "swift is mentioned only once in a much longer rambling segment full of unrelated words about the weather and lunch", startTime: 0)]))

        let results = dataManager.transcriptions.searchSegments(query: "swift")
        XCTAssertEqual(results.map(\.episodeUuid), ["ep-dense", "ep-sparse"])
    }

    func testSearchSegmentsRespectsLimit() {
        let segments = (0..<5).map { TranscriptionSegment(index: $0, text: "apple pie number \($0)", startTime: Double($0)) }
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", segments: segments))

        XCTAssertEqual(dataManager.transcriptions.searchSegments(query: "apple", limit: 3).count, 3)
        XCTAssertEqual(dataManager.transcriptions.searchSegments(query: "apple").count, 5)
    }

    // MARK: - Delete

    func testDeleteRemovesRecordRowAndFTSRows() {
        upsertRecord(episodeUuid: "ep-1", status: .completed)
        upsertRecord(episodeUuid: "ep-2", status: .completed)
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(
            episodeUuid: "ep-1", podcastUuid: "pod-1",
            segments: [TranscriptionSegment(index: 0, text: "delete me", startTime: 0)]))
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(
            episodeUuid: "ep-2", podcastUuid: "pod-1",
            segments: [TranscriptionSegment(index: 0, text: "keep me", startTime: 0)]))

        XCTAssertTrue(dataManager.transcriptions.delete(episodeUuid: "ep-1"))

        XCTAssertNil(dataManager.transcriptions.find(episodeUuid: "ep-1"))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 0)
        XCTAssertNotNil(dataManager.transcriptions.find(episodeUuid: "ep-2"))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-2"), 1)
    }

    // MARK: - FTS query sanitizing

    func testSanitizeFTSQueryQuotesTokensAndAddsPrefixStar() {
        XCTAssertEqual(TranscriptionDataManager.sanitizeFTSQuery("swift"), "\"swift\"*")
        XCTAssertEqual(TranscriptionDataManager.sanitizeFTSQuery("hello world"), "\"hello\" \"world\"*")
    }

    func testSanitizeFTSQueryNeutralizesHostileInput() {
        XCTAssertEqual(TranscriptionDataManager.sanitizeFTSQuery("\"quoted\""), "\"quoted\"*")
        XCTAssertEqual(TranscriptionDataManager.sanitizeFTSQuery("a AND b"), "\"a\" \"AND\" \"b\"*")
        XCTAssertEqual(TranscriptionDataManager.sanitizeFTSQuery("weird(paren"), "\"weird(paren\"*")
        XCTAssertEqual(TranscriptionDataManager.sanitizeFTSQuery("NEAR/2"), "\"NEAR/2\"*")
        XCTAssertEqual(TranscriptionDataManager.sanitizeFTSQuery("naïve café"), "\"naïve\" \"café\"*")

        // Nothing searchable: whitespace, bare operators/punctuation, emoji-only input
        // (unicode61 has no emoji tokens), and quote-only strings all collapse to nil.
        XCTAssertNil(TranscriptionDataManager.sanitizeFTSQuery(""))
        XCTAssertNil(TranscriptionDataManager.sanitizeFTSQuery("   "))
        XCTAssertNil(TranscriptionDataManager.sanitizeFTSQuery("🔥🔥"))
        XCTAssertNil(TranscriptionDataManager.sanitizeFTSQuery("\"\"\""))
        XCTAssertNil(TranscriptionDataManager.sanitizeFTSQuery("* ( ) -"))
    }

    func testSearchSegmentsSurvivesHostileQueries() {
        XCTAssertTrue(dataManager.transcriptions.replaceSegments(
            episodeUuid: "ep-1", podcastUuid: "pod-1",
            segments: [TranscriptionSegment(index: 0, text: "a and b walked into a bar", startTime: 0)]))

        // Operators are treated as plain (case-folded) terms, so this still matches sensibly.
        XCTAssertEqual(dataManager.transcriptions.searchSegments(query: "a AND b").count, 1)

        // The rest must not crash or throw a MATCH syntax error; empty results are fine.
        let hostileQueries = ["\"quoted\"", "weird(paren", "NEAR/2", "NOT", "-bar", "col:val", "🔥", "", "(((", "*", "bar\"", "b OR nothing"]
        for query in hostileQueries {
            _ = dataManager.transcriptions.searchSegments(query: query)
        }

        XCTAssertEqual(dataManager.transcriptions.searchSegments(query: "").count, 0)
        XCTAssertEqual(dataManager.transcriptions.searchSegments(query: "🔥").count, 0)
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

    private func ftsRowCount(episodeUuid: String) -> Int {
        let count = try? dataManager.testDbQueue.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(TranscriptionDataManager.ftsTableName) WHERE episodeUuid = ?",
                arguments: [episodeUuid]
            )
        }
        return count.flatMap { $0 } ?? 0
    }
}
