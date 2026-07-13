import GRDB
@testable import PocketCastsDataModel
import XCTest

final class TranscriptSearchDataManagerTests: XCTestCase {
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

    func testMigrationCreatesUnifiedIndexSchemaOnFreshDatabase() throws {
        try dataManager.testDbQueue.dbPool.read { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1
            XCTAssertGreaterThanOrEqual(version, 82, "Migration 82 should have run on a fresh database")
            XCTAssertEqual(version, Int(DatabaseHelper.currentSchemaVersion(for: DatabaseHelper.migrations)))

            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")
            XCTAssertTrue(names.contains("TranscriptSegmentIndex"))
            XCTAssertTrue(names.contains("TranscriptSearchIndexMeta"))
            XCTAssertFalse(names.contains("TranscriptionSegmentFTS"), "Migration 82 must drop the old generated corpus")
            XCTAssertFalse(names.contains("TranscriptCueIndex"), "Migration 82 must drop the old provided corpus")
            XCTAssertFalse(names.contains("TranscriptIndexMeta"), "Migration 82 must drop the old bookkeeping table")

            // The FTS5 virtual table is actually queryable, not just present in sqlite_master
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM TranscriptSegmentIndex"), 0)
        }
        XCTAssertTrue(dataManager.transcriptSearch.isAvailable)
    }

    /// The self-disable path documented on migration 82: without the meta table
    /// (FTS5 creation failed, so neither table exists) the manager reports
    /// unavailable and every operation no-ops.
    func testManagerSelfDisablesWhenMetaTableIsMissing() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))
        let queue = GRDBQueue(dbPool: dbPool)
        let priorMigrations = DatabaseHelper.migrations.filter { $0.toVersion <= 81 }
        XCTAssertTrue(DatabaseHelper.setup(queue: queue, migrations: priorMigrations))
        // Simulate the FTS5-failure outcome of migration 82 (neither table created).
        try dbPool.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS TranscriptCueIndex")
            try db.execute(sql: "DROP TABLE IF EXISTS TranscriptIndexMeta")
        }

        let index = TranscriptSearchDataManager(dbQueue: queue)

        XCTAssertFalse(index.isAvailable)
        XCTAssertFalse(index.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided, segments: [segment(0, "hello world")]))
        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-1", source: .provided))
        XCTAssertEqual(index.search(term: "hello"), [])
        XCTAssertEqual(index.indexedEpisodeCount(), 0)
        XCTAssertFalse(index.removeAll())
    }

    // MARK: - Indexing

    func testReplaceSegmentsWritesSegmentsAndMetaRow() throws {
        let segments = [
            segment(0, "The quick brown fox jumps over the lazy dog", start: 1.5, end: 4),
            segment(1, "Another sentence about something else entirely", start: 4, end: 9)
        ]
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided, segments: segments))

        XCTAssertTrue(dataManager.transcriptSearch.isIndexed(episodeUuid: "ep-1", source: .provided))
        XCTAssertFalse(dataManager.transcriptSearch.isIndexed(episodeUuid: "ep-1", source: .generated), "Sources are separate corpora")
        XCTAssertFalse(dataManager.transcriptSearch.isIndexed(episodeUuid: "ep-2", source: .provided))
        XCTAssertEqual(dataManager.transcriptSearch.indexedEpisodeCount(), 1)
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 2)

        let meta = try XCTUnwrap(metaRecord(episodeUuid: "ep-1", source: .provided))
        XCTAssertEqual(meta.podcastUuid, "pod-1")
        XCTAssertEqual(meta.segmentCount, 2)
        XCTAssertEqual(meta.textBytes, Int64(segments.reduce(0) { $0 + $1.text.utf8.count }))
        XCTAssertGreaterThan(meta.indexedDate, 0)
    }

    func testReplaceSegmentsIsIdempotentAndReplacesPerSource() {
        let segments = [segment(0, "hello world"), segment(1, "goodbye moon")]

        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided, segments: segments))
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided, segments: segments))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 2, "Re-running replaceSegments must not duplicate rows")
        XCTAssertEqual(dataManager.transcriptSearch.indexedEpisodeCount(), 1)

        // The same episode can be indexed under both sources independently.
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated, segments: [segments[0]]))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 3, "Generated segments must not replace provided ones")
        XCTAssertEqual(dataManager.transcriptSearch.indexedEpisodeCount(), 2)
        XCTAssertEqual(dataManager.transcriptSearch.indexedEpisodeCount(source: .provided), 1)
        XCTAssertEqual(dataManager.transcriptSearch.indexedEpisodeCount(source: .generated), 1)

        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided, segments: [segments[0]]))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 2, "Replacing with fewer segments should shrink only that source's set")
    }

    // MARK: - Search

    func testSearchReturnsHighlightedSnippetAndFields() throws {
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated,
            segments: [segment(3, "The quick brown fox jumps over the lazy dog", start: 12.5, end: 16, speaker: "Speaker 1")]))

        let results = dataManager.transcriptSearch.search(term: "fox")
        XCTAssertEqual(results.count, 1)

        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.episodeUuid, "ep-1")
        XCTAssertEqual(result.podcastUuid, "pod-1")
        XCTAssertEqual(result.segmentIndex, 3)
        XCTAssertEqual(result.startTime, 12.5)
        XCTAssertEqual(result.endTime, 16)
        XCTAssertEqual(result.speaker, "Speaker 1")
        XCTAssertEqual(result.source, .generated)
        let highlighted = TranscriptSearchHit.highlightStart + "fox" + TranscriptSearchHit.highlightEnd
        XCTAssertTrue(result.snippet.contains(highlighted), "Snippet should wrap the match in highlight markers: \(result.snippet)")
    }

    func testSearchSpansBothSourcesAndFiltersBySource() {
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-provided", podcastUuid: "pod-1", source: .provided,
            segments: [segment(0, "kangaroo in the provided corpus")]))
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-generated", podcastUuid: "pod-2", source: .generated,
            segments: [segment(0, "kangaroo in the generated corpus")]))

        XCTAssertEqual(Set(dataManager.transcriptSearch.search(term: "kangaroo").map(\.episodeUuid)),
                       ["ep-provided", "ep-generated"], "An unfiltered search must span both corpora")
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "kangaroo", source: .provided).map(\.episodeUuid), ["ep-provided"])
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "kangaroo", source: .generated).map(\.episodeUuid), ["ep-generated"])
    }

    func testSearchMatchesLastTokenAsPrefix() throws {
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided,
            segments: [segment(0, "The quick brown fox")]))

        let results = dataManager.transcriptSearch.search(term: "qui")
        XCTAssertEqual(results.count, 1, "The final query token should match as a prefix while the user is typing")
        let highlighted = TranscriptSearchHit.highlightStart + "quick" + TranscriptSearchHit.highlightEnd
        XCTAssertTrue(try XCTUnwrap(results.first).snippet.contains(highlighted))
    }

    func testSearchOrdersByRelevance() {
        // ep-dense mentions the term repeatedly in a short segment; ep-sparse mentions it
        // once diluted by many other words, so BM25 must rank ep-dense first.
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-dense", podcastUuid: "pod-1", source: .provided,
            segments: [segment(0, "swift swift swift swift")]))
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-sparse", podcastUuid: "pod-2", source: .generated,
            segments: [segment(0, "swift is mentioned only once in a much longer rambling segment full of unrelated words about the weather and lunch")]))

        let results = dataManager.transcriptSearch.search(term: "swift")
        XCTAssertEqual(results.map(\.episodeUuid), ["ep-dense", "ep-sparse"])
    }

    func testSearchRespectsLimit() {
        let segments = (0 ..< 5).map { segment($0, "apple pie number \($0)", start: Double($0), end: Double($0) + 1) }
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided, segments: segments))

        XCTAssertEqual(dataManager.transcriptSearch.search(term: "apple", limit: 3).count, 3)
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "apple").count, 5)
    }

    func testSearchIsDiacriticsInsensitive() throws {
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided,
            segments: [segment(0, "a naïve café conversation")]))

        // remove_diacritics 2 folds both directions: plain query matches accented
        // text and accented query matches it too.
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "cafe").count, 1)
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "café").count, 1)
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "naive").count, 1)
    }

    func testSearchSurvivesHostileQueries() {
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided,
            segments: [segment(0, "a and b walked into a bar")]))

        // Operators are treated as plain (case-folded) terms, so this still matches sensibly.
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "a AND b").count, 1)

        // The rest must not crash or throw a MATCH syntax error; empty results are fine.
        let hostileQueries = ["\"quoted\"", "weird(paren", "NEAR/2", "NOT", "-bar", "col:val", "🔥", "", "(((", "*", "bar\"", "b OR nothing"]
        for query in hostileQueries {
            _ = dataManager.transcriptSearch.search(term: query)
        }

        XCTAssertEqual(dataManager.transcriptSearch.search(term: "").count, 0)
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "🔥").count, 0)
    }

    // MARK: - Eviction

    func testEvictionByTotalTextBytesRemovesOldestProvidedFirst() {
        // Each segment is 30 bytes; the cap fits two episodes but not three.
        let text = String(repeating: "a", count: 30)
        let index = TranscriptSearchDataManager(dbQueue: dataManager.testDbQueue, maxTotalTextBytes: 65)

        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-old", podcastUuid: "pod-1", source: .provided, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-mid", podcastUuid: "pod-1", source: .provided, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(index.indexedEpisodeCount(), 2, "60 bytes fits under the 65 byte cap")

        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-new", podcastUuid: "pod-1", source: .provided, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 300)))

        XCTAssertEqual(index.indexedEpisodeCount(), 2)
        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-old", source: .provided), "The least recently indexed provided episode should be evicted")
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-mid", source: .provided))
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-new", source: .provided))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-old"), 0, "Eviction must also drop the FTS rows")
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-new"), 1)
    }

    func testEvictionPrefersEpisodesNoLongerInTheLibrary() {
        // ep-departed has no SJEpisode row; ep-library does. Even though ep-library
        // was indexed earlier, the departed episode must be evicted first — its
        // hits could not be played anyway and its transcript is re-fetchable.
        var episode = Episode()
        episode.uuid = "ep-library"
        episode.podcastUuid = "pod-1"
        episode.addedDate = Date()
        dataManager.save(episode: episode)

        let text = String(repeating: "a", count: 30)
        let index = TranscriptSearchDataManager(dbQueue: dataManager.testDbQueue, maxTotalTextBytes: 65)

        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-library", podcastUuid: "pod-1", source: .provided, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-departed", podcastUuid: "pod-1", source: .provided, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 200)))

        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-new", podcastUuid: "pod-1", source: .provided, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 300)))

        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-departed", source: .provided), "Departed episodes are evicted before in-library LRU victims")
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-library", source: .provided))
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-new", source: .provided))
    }

    func testEvictionNeverEvictsGeneratedRows() {
        let text = String(repeating: "a", count: 30)
        let index = TranscriptSearchDataManager(dbQueue: dataManager.testDbQueue, maxTotalTextBytes: 65)

        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-gen-old", podcastUuid: "pod-1", source: .generated, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-provided", podcastUuid: "pod-1", source: .provided, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 200)))
        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-new", podcastUuid: "pod-1", source: .provided, segments: [segment(0, text)], indexedDate: Date(timeIntervalSince1970: 300)))

        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-gen-old", source: .generated), "Generated rows are never eviction victims, even as the oldest")
        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-provided", source: .provided), "The provided row is the only eligible victim")
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-new", source: .provided))
    }

    func testEvictionTerminatesWhenOnlyGeneratedRowsExceedTheCap() {
        // A generated corpus alone over the cap: nothing is evictable, and the
        // eviction loop must terminate (over cap) rather than spin.
        let index = TranscriptSearchDataManager(dbQueue: dataManager.testDbQueue, maxTotalTextBytes: 20)

        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-gen-1", podcastUuid: "pod-1", source: .generated, segments: [segment(0, String(repeating: "b", count: 50))], indexedDate: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-gen-2", podcastUuid: "pod-1", source: .generated, segments: [segment(0, String(repeating: "c", count: 50))], indexedDate: Date(timeIntervalSince1970: 200)))

        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-gen-1", source: .generated))
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-gen-2", source: .generated))
        XCTAssertEqual(index.indexedEpisodeCount(), 2)
    }

    func testEvictionNeverEvictsTheJustIndexedEpisode() {
        // A single provided episode larger than the whole byte cap: everything else
        // is evicted, but the fresh episode itself gets a grace pass (and the
        // eviction loop terminates).
        let index = TranscriptSearchDataManager(dbQueue: dataManager.testDbQueue, maxTotalTextBytes: 20)

        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-old", podcastUuid: "pod-1", source: .provided, segments: [segment(0, "tiny")], indexedDate: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(index.replaceSegments(episodeUuid: "ep-huge", podcastUuid: "pod-1", source: .provided, segments: [segment(0, String(repeating: "b", count: 50))], indexedDate: Date(timeIntervalSince1970: 200)))

        XCTAssertFalse(index.isIndexed(episodeUuid: "ep-old", source: .provided))
        XCTAssertTrue(index.isIndexed(episodeUuid: "ep-huge", source: .provided))
        XCTAssertEqual(index.indexedEpisodeCount(), 1)
    }

    // MARK: - Delete / remove all

    func testDeleteRemovesOnlyTheGivenSource() {
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided, segments: [segment(0, "provided words")]))
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated, segments: [segment(0, "generated words")]))

        XCTAssertTrue(dataManager.transcriptSearch.delete(episodeUuid: "ep-1", source: .generated))

        XCTAssertFalse(dataManager.transcriptSearch.isIndexed(episodeUuid: "ep-1", source: .generated))
        XCTAssertTrue(dataManager.transcriptSearch.isIndexed(episodeUuid: "ep-1", source: .provided))
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 1)
    }

    func testRemoveAllDropsSegmentsAndMeta() {
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .provided, segments: [segment(0, "delete me")]))
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "ep-2", podcastUuid: "pod-2", source: .generated, segments: [segment(0, "delete me too")]))

        XCTAssertTrue(dataManager.transcriptSearch.removeAll(source: .generated))
        XCTAssertEqual(dataManager.transcriptSearch.indexedEpisodeCount(), 1, "Source-scoped removeAll must keep the other corpus")

        XCTAssertTrue(dataManager.transcriptSearch.removeAll())

        XCTAssertEqual(dataManager.transcriptSearch.indexedEpisodeCount(), 0)
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-1"), 0)
        XCTAssertEqual(ftsRowCount(episodeUuid: "ep-2"), 0)
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "delete").count, 0)
    }

    // MARK: - FTS query sanitizing

    func testSanitizeFTSQueryQuotesTokensAndAddsPrefixStar() {
        XCTAssertEqual(TranscriptSearchDataManager.sanitizeFTSQuery("swift"), "\"swift\"*")
        XCTAssertEqual(TranscriptSearchDataManager.sanitizeFTSQuery("hello world"), "\"hello\" \"world\"*")
    }

    func testSanitizeFTSQueryNeutralizesHostileInput() {
        XCTAssertEqual(TranscriptSearchDataManager.sanitizeFTSQuery("\"quoted\""), "\"quoted\"*")
        XCTAssertEqual(TranscriptSearchDataManager.sanitizeFTSQuery("a AND b"), "\"a\" \"AND\" \"b\"*")
        XCTAssertEqual(TranscriptSearchDataManager.sanitizeFTSQuery("weird(paren"), "\"weird(paren\"*")
        XCTAssertEqual(TranscriptSearchDataManager.sanitizeFTSQuery("NEAR/2"), "\"NEAR/2\"*")
        XCTAssertEqual(TranscriptSearchDataManager.sanitizeFTSQuery("naïve café"), "\"naïve\" \"café\"*")

        // Nothing searchable: whitespace, bare operators/punctuation, emoji-only input
        // (unicode61 has no emoji tokens), and quote-only strings all collapse to nil.
        XCTAssertNil(TranscriptSearchDataManager.sanitizeFTSQuery(""))
        XCTAssertNil(TranscriptSearchDataManager.sanitizeFTSQuery("   "))
        XCTAssertNil(TranscriptSearchDataManager.sanitizeFTSQuery("🔥🔥"))
        XCTAssertNil(TranscriptSearchDataManager.sanitizeFTSQuery("\"\"\""))
        XCTAssertNil(TranscriptSearchDataManager.sanitizeFTSQuery("* ( ) -"))
    }

    // MARK: - Helpers

    private func segment(_ index: Int, _ text: String, start: Double = 0, end: Double? = 1, speaker: String? = nil) -> TranscriptSearchSegment {
        TranscriptSearchSegment(index: index, text: text, startTime: start, endTime: end, speaker: speaker)
    }

    private func ftsRowCount(episodeUuid: String) -> Int {
        let count = try? dataManager.testDbQueue.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(TranscriptSearchDataManager.ftsTableName) WHERE episodeUuid = ?",
                arguments: [episodeUuid]
            )
        }
        return count.flatMap { $0 } ?? 0
    }

    private func metaRecord(episodeUuid: String, source: TranscriptSource) -> TranscriptSearchIndexMetaRecord? {
        try? dataManager.testDbQueue.dbPool.read { db in
            try TranscriptSearchIndexMetaRecord.fetchOne(db, key: ["episodeUuid": episodeUuid, "source": source.rawValue])
        }
    }
}
