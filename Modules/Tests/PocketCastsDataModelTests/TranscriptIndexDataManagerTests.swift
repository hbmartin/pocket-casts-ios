import GRDB
@testable import PocketCastsDataModel
import XCTest

final class TranscriptIndexDataManagerTests: XCTestCase {
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

    func testMigrationCreatesTranscriptIndexSchemaOnFreshDatabase() throws {
        try dataManager.testDbQueue.dbPool.read { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1
            XCTAssertGreaterThanOrEqual(version, 81, "Migration 81 should have run on a fresh database")
            XCTAssertEqual(version, Int(DatabaseHelper.currentSchemaVersion(for: DatabaseHelper.migrations)))

            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")
            XCTAssertTrue(names.contains("TranscriptCueIndex"))
            XCTAssertTrue(names.contains("TranscriptIndexMeta"))

            // The FTS5 virtual table is actually queryable, not just present in sqlite_master
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM TranscriptCueIndex"), 0)
        }
        XCTAssertTrue(dataManager.transcriptIndex.isAvailable)
    }

    /// The self-disable path documented on migration 81: without the meta table
    /// (FTS5 creation failed, so neither table exists) the manager reports
    /// unavailable and every operation no-ops.
    func testManagerSelfDisablesWhenMetaTableIsMissing() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))
        let queue = GRDBQueue(dbPool: dbPool)
        let priorMigrations = DatabaseHelper.migrations.filter { $0.toVersion <= 80 }
        XCTAssertTrue(DatabaseHelper.setup(queue: queue, migrations: priorMigrations))

        let index = TranscriptIndexDataManager(dbQueue: queue)

        XCTAssertFalse(index.isAvailable)
        XCTAssertFalse(index.index(episodeUuid: "ep-1", podcastUuid: "pod-1", cues: [cue(0, "hello world")]))
        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-1"))
        XCTAssertEqual(index.search(term: "hello"), [])
        XCTAssertEqual(index.indexedEpisodeCount(), 0)
        XCTAssertFalse(index.removeAll())
    }

    // MARK: - Indexing

    func testIndexWritesSegmentsAndMetaRow() throws {
        let cues = [
            cue(0, "The quick brown fox jumps over the lazy dog", start: 1.5, end: 4),
            cue(1, "Another sentence about something else entirely", start: 4, end: 9)
        ]
        XCTAssertTrue(dataManager.transcriptIndex.index(episodeUuid: "ep-1", podcastUuid: "pod-1", cues: cues))

        XCTAssertTrue(dataManager.transcriptIndex.isIndexed(episodeUuid: "ep-1"))
        XCTAssertFalse(dataManager.transcriptIndex.isIndexed(episodeUuid: "ep-2"))
        XCTAssertEqual(dataManager.transcriptIndex.indexedEpisodeCount(), 1)
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 2)

        let meta = try XCTUnwrap(metaRecord(episodeUuid: "ep-1"))
        XCTAssertEqual(meta.podcastUuid, "pod-1")
        XCTAssertEqual(meta.cueCount, 2)
        XCTAssertEqual(meta.textBytes, Int64(cues.reduce(0) { $0 + $1.text.utf8.count }))
        XCTAssertGreaterThan(meta.indexedDate, 0)
    }

    func testIndexIsIdempotentAndReplaces() {
        let cues = [cue(0, "hello world"), cue(1, "goodbye moon")]

        XCTAssertTrue(dataManager.transcriptIndex.index(episodeUuid: "ep-1", podcastUuid: "pod-1", cues: cues))
        XCTAssertTrue(dataManager.transcriptIndex.index(episodeUuid: "ep-1", podcastUuid: "pod-1", cues: cues))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 2, "Re-running index must not duplicate rows")
        XCTAssertEqual(dataManager.transcriptIndex.indexedEpisodeCount(), 1)

        XCTAssertTrue(dataManager.transcriptIndex.index(episodeUuid: "ep-1", podcastUuid: "pod-1", cues: [cues[0]]))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 1, "Replacing with fewer segments should shrink the set")
    }

    // MARK: - Search

    func testSearchReturnsHighlightedSnippetAndFields() throws {
        XCTAssertTrue(dataManager.transcriptIndex.index(
            episodeUuid: "ep-1", podcastUuid: "pod-1",
            cues: [cue(3, "The quick brown fox jumps over the lazy dog", start: 12.5, end: 16)]))

        let results = dataManager.transcriptIndex.search(term: "fox")
        XCTAssertEqual(results.count, 1)

        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.episodeUuid, "ep-1")
        XCTAssertEqual(result.podcastUuid, "pod-1")
        XCTAssertEqual(result.cueIndex, 3)
        XCTAssertEqual(result.startTime, 12.5)
        XCTAssertEqual(result.endTime, 16)
        let highlighted = TranscriptSearchHit.highlightStart + "fox" + TranscriptSearchHit.highlightEnd
        XCTAssertTrue(result.snippet.contains(highlighted), "Snippet should wrap the match in highlight markers: \(result.snippet)")
    }

    func testSearchMatchesLastTokenAsPrefix() throws {
        XCTAssertTrue(dataManager.transcriptIndex.index(
            episodeUuid: "ep-1", podcastUuid: "pod-1",
            cues: [cue(0, "The quick brown fox")]))

        let results = dataManager.transcriptIndex.search(term: "qui")
        XCTAssertEqual(results.count, 1, "The final query token should match as a prefix while the user is typing")
        let highlighted = TranscriptSearchHit.highlightStart + "quick" + TranscriptSearchHit.highlightEnd
        XCTAssertTrue(try XCTUnwrap(results.first).snippet.contains(highlighted))
    }

    func testSearchOrdersByRelevance() {
        // ep-dense mentions the term repeatedly in a short segment; ep-sparse mentions it
        // once diluted by many other words, so BM25 must rank ep-dense first.
        XCTAssertTrue(dataManager.transcriptIndex.index(
            episodeUuid: "ep-dense", podcastUuid: "pod-1",
            cues: [cue(0, "swift swift swift swift")]))
        XCTAssertTrue(dataManager.transcriptIndex.index(
            episodeUuid: "ep-sparse", podcastUuid: "pod-2",
            cues: [cue(0, "swift is mentioned only once in a much longer rambling segment full of unrelated words about the weather and lunch")]))

        let results = dataManager.transcriptIndex.search(term: "swift")
        XCTAssertEqual(results.map(\.episodeUuid), ["ep-dense", "ep-sparse"])
    }

    func testSearchRespectsLimit() {
        let cues = (0 ..< 5).map { cue($0, "apple pie number \($0)", start: Double($0), end: Double($0) + 1) }
        XCTAssertTrue(dataManager.transcriptIndex.index(episodeUuid: "ep-1", podcastUuid: "pod-1", cues: cues))

        XCTAssertEqual(dataManager.transcriptIndex.search(term: "apple", limit: 3).count, 3)
        XCTAssertEqual(dataManager.transcriptIndex.search(term: "apple").count, 5)
    }

    func testSearchIsDiacriticsInsensitive() throws {
        XCTAssertTrue(dataManager.transcriptIndex.index(
            episodeUuid: "ep-1", podcastUuid: "pod-1",
            cues: [cue(0, "a naïve café conversation")]))

        // remove_diacritics 2 folds both directions: plain query matches accented
        // text and accented query matches it too.
        XCTAssertEqual(dataManager.transcriptIndex.search(term: "cafe").count, 1)
        XCTAssertEqual(dataManager.transcriptIndex.search(term: "café").count, 1)
        XCTAssertEqual(dataManager.transcriptIndex.search(term: "naive").count, 1)
    }

    func testSearchSurvivesHostileQueries() {
        XCTAssertTrue(dataManager.transcriptIndex.index(
            episodeUuid: "ep-1", podcastUuid: "pod-1",
            cues: [cue(0, "a and b walked into a bar")]))

        // Operators are treated as plain (case-folded) terms, so this still matches sensibly.
        XCTAssertEqual(dataManager.transcriptIndex.search(term: "a AND b").count, 1)

        // The rest must not crash or throw a MATCH syntax error; empty results are fine.
        let hostileQueries = ["\"quoted\"", "weird(paren", "NEAR/2", "NOT", "-bar", "col:val", "🔥", "", "(((", "*", "bar\"", "b OR nothing"]
        for query in hostileQueries {
            _ = dataManager.transcriptIndex.search(term: query)
        }

        XCTAssertEqual(dataManager.transcriptIndex.search(term: "").count, 0)
        XCTAssertEqual(dataManager.transcriptIndex.search(term: "🔥").count, 0)
    }

    // MARK: - Eviction

    func testEvictionByEpisodeCountRemovesOldestIndexedFirst() {
        let index = TranscriptIndexDataManager(dbQueue: dataManager.testDbQueue, maxIndexedEpisodes: 2)

        XCTAssertTrue(index.index(episodeUuid: "ep-old", podcastUuid: "pod-1", cues: [cue(0, "oldest words")], indexedDate: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(index.index(episodeUuid: "ep-mid", podcastUuid: "pod-1", cues: [cue(0, "middle words")], indexedDate: Date(timeIntervalSince1970: 200)))
        XCTAssertTrue(index.index(episodeUuid: "ep-new", podcastUuid: "pod-1", cues: [cue(0, "newest words")], indexedDate: Date(timeIntervalSince1970: 300)))

        XCTAssertEqual(index.indexedEpisodeCount(), 2)
        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-old"), "The least recently indexed episode should be evicted")
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-mid"))
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-new"))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-old"), 0, "Eviction must also drop the FTS rows")
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-new"), 1)
    }

    func testEvictionByTotalTextBytes() {
        // Each segment is 30 bytes; the cap fits two episodes but not three.
        let text = String(repeating: "a", count: 30)
        let index = TranscriptIndexDataManager(dbQueue: dataManager.testDbQueue, maxTotalTextBytes: 65)

        XCTAssertTrue(index.index(episodeUuid: "ep-old", podcastUuid: "pod-1", cues: [cue(0, text)], indexedDate: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(index.index(episodeUuid: "ep-mid", podcastUuid: "pod-1", cues: [cue(0, text)], indexedDate: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(index.indexedEpisodeCount(), 2, "60 bytes fits under the 65 byte cap")

        XCTAssertTrue(index.index(episodeUuid: "ep-new", podcastUuid: "pod-1", cues: [cue(0, text)], indexedDate: Date(timeIntervalSince1970: 300)))

        XCTAssertEqual(index.indexedEpisodeCount(), 2)
        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-old"))
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-mid"))
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-new"))
    }

    func testEvictionNeverEvictsTheJustIndexedEpisode() {
        // A single episode larger than the whole byte cap: everything else is
        // evicted, but the fresh episode itself gets a grace pass (and the
        // eviction loop terminates).
        let index = TranscriptIndexDataManager(dbQueue: dataManager.testDbQueue, maxTotalTextBytes: 20)

        XCTAssertTrue(index.index(episodeUuid: "ep-old", podcastUuid: "pod-1", cues: [cue(0, "tiny")], indexedDate: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(index.index(episodeUuid: "ep-huge", podcastUuid: "pod-1", cues: [cue(0, String(repeating: "b", count: 50))], indexedDate: Date(timeIntervalSince1970: 200)))

        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-old"))
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-huge"))
        XCTAssertEqual(index.indexedEpisodeCount(), 1)
    }

    // MARK: - Remove all

    func testRemoveAllDropsSegmentsAndMeta() {
        XCTAssertTrue(dataManager.transcriptIndex.index(episodeUuid: "ep-1", podcastUuid: "pod-1", cues: [cue(0, "delete me")]))
        XCTAssertTrue(dataManager.transcriptIndex.index(episodeUuid: "ep-2", podcastUuid: "pod-2", cues: [cue(0, "delete me too")]))

        XCTAssertTrue(dataManager.transcriptIndex.removeAll())

        XCTAssertEqual(dataManager.transcriptIndex.indexedEpisodeCount(), 0)
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 0)
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-2"), 0)
        XCTAssertEqual(dataManager.transcriptIndex.search(term: "delete").count, 0)
    }

    // MARK: - Helpers

    private func cue(_ index: Int, _ text: String, start: Double = 0, end: Double = 1) -> TranscriptIndexCue {
        TranscriptIndexCue(index: index, text: text, startTime: start, endTime: end)
    }

    private func ftsRowCount(episodeUuid: String) -> Int {
        let count = try? dataManager.testDbQueue.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(TranscriptIndexDataManager.ftsTableName) WHERE episodeUuid = ?",
                arguments: [episodeUuid]
            )
        }
        return count.flatMap { $0 } ?? 0
    }

    private func metaRecord(episodeUuid: String) -> TranscriptIndexMetaRecord? {
        try? dataManager.testDbQueue.dbPool.read { db in
            try TranscriptIndexMetaRecord.fetchOne(db, key: episodeUuid)
        }
    }
}
