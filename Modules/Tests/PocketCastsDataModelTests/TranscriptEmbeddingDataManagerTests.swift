import GRDB
@testable import PocketCastsDataModel
import XCTest

/// The semantic-search sidecar: window storage, the eviction-race guard, model
/// versioning, corpus cascades (re-index/delete/removeAll/eviction), candidate
/// scans with filters, and the backfill work list.
final class TranscriptEmbeddingDataManagerTests: DataManagerTestCase {
    private var dataManager: DataManager!

    private let model = TranscriptEmbeddingModelInfo(identifier: "nl.latin.v1", revision: 3, dimension: 512, quantization: "float16")

    override func setUp() {
        super.setUp()
        dataManager = DataManager.newTestDataManager()
    }

    override func tearDown() {
        dataManager = nil
        super.tearDown()
    }

    private var embeddings: TranscriptEmbeddingDataManager { dataManager.transcriptEmbeddings }
    private var search: TranscriptSearchDataManager { dataManager.transcriptSearch }

    private func indexCorpus(episodeUuid: String, podcastUuid: String? = "pod-1", source: TranscriptSource = .generated, segmentCount: Int = 4) {
        let segments = (0 ..< segmentCount).map {
            TranscriptSearchSegment(index: $0, text: "segment number \($0) with some words", startTime: Double($0) * 10)
        }
        XCTAssertTrue(search.replaceSegments(episodeUuid: episodeUuid, podcastUuid: podcastUuid, source: source, segments: segments))
    }

    private func window(_ index: Int, vectorByte: UInt8 = 7) -> TranscriptEmbeddingWindow {
        TranscriptEmbeddingWindow(
            windowIndex: index,
            startSegmentIndex: index * 2,
            endSegmentIndex: index * 2 + 1,
            startTime: Double(index) * 20,
            endTime: Double(index) * 20 + 19,
            textPreview: "window \(index) preview",
            vector: Data(repeating: vectorByte, count: 16)
        )
    }

    // MARK: - Migration

    func testMigrationCreatesSidecarTables() throws {
        try dataManager.testDbQueue.dbPool.read { db in
            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")
            XCTAssertTrue(names.contains("TranscriptEmbedding"))
            XCTAssertTrue(names.contains("TranscriptEmbeddingMeta"))
            XCTAssertTrue(names.contains("transcript_embedding_podcast"))
        }
        XCTAssertTrue(embeddings.isAvailable)
    }

    // MARK: - Writes

    func testReplaceWindowsRoundTripsAndStampsMeta() {
        indexCorpus(episodeUuid: "ep-1")
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated,
                                                model: model, windows: [window(0), window(1)]))

        XCTAssertTrue(embeddings.isEmbedded(episodeUuid: "ep-1", source: .generated, model: model))
        XCTAssertEqual(embeddings.totalVectorBytes(), 32)

        var seen: [TranscriptEmbeddingCandidate] = []
        embeddings.candidates(model: model) { seen.append(contentsOf: $0) }
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen.map(\.windowIndex), [0, 1])
        XCTAssertEqual(seen.first?.textPreview, "window 0 preview")
        XCTAssertEqual(seen.first?.vector, Data(repeating: 7, count: 16))
        XCTAssertEqual(seen.first?.startSegmentIndex, 0)
        XCTAssertEqual(seen.first?.endSegmentIndex, 1)
    }

    func testReplaceWindowsRefusesWhenCorpusHasNoRow() {
        // The eviction race: an embed task finishing after its FTS rows were
        // evicted must not write orphans.
        XCTAssertFalse(embeddings.replaceWindows(episodeUuid: "ep-evicted", podcastUuid: nil, source: .generated,
                                                 model: model, windows: [window(0)]))
        var seen = 0
        embeddings.candidates(model: model) { seen += $0.count }
        XCTAssertEqual(seen, 0)
        XCTAssertEqual(embeddings.totalVectorBytes(), 0)
    }

    func testModelMismatchHidesRowsAndRelistsPair() {
        indexCorpus(episodeUuid: "ep-1")
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated,
                                                model: model, windows: [window(0)]))

        let bumped = TranscriptEmbeddingModelInfo(identifier: model.identifier, revision: model.revision + 1,
                                                  dimension: model.dimension, quantization: model.quantization)
        XCTAssertFalse(embeddings.isEmbedded(episodeUuid: "ep-1", source: .generated, model: bumped))

        var seen = 0
        embeddings.candidates(model: bumped) { seen += $0.count }
        XCTAssertEqual(seen, 0, "stale-model vectors never participate in scans")

        let pending = embeddings.pendingPairs(model: bumped)
        XCTAssertEqual(pending.map(\.episodeUuid), ["ep-1"], "the pair re-lists for lazy re-embedding")

        // Re-embedding under the new model replaces rows and satisfies the pair.
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated,
                                                model: bumped, windows: [window(0)]))
        XCTAssertTrue(embeddings.pendingPairs(model: bumped).isEmpty)
    }

    // MARK: - Corpus cascades

    func testReindexingCorpusDropsStaleWindows() {
        indexCorpus(episodeUuid: "ep-1")
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated,
                                                model: model, windows: [window(0)]))

        // Segment ordinals shift on re-index; windows must not survive it.
        indexCorpus(episodeUuid: "ep-1", segmentCount: 6)

        XCTAssertFalse(embeddings.isEmbedded(episodeUuid: "ep-1", source: .generated, model: model))
        XCTAssertEqual(embeddings.pendingPairs(model: model).map(\.episodeUuid), ["ep-1"])
    }

    func testCorpusDeleteAndRemoveAllCascade() {
        indexCorpus(episodeUuid: "ep-1", source: .generated)
        indexCorpus(episodeUuid: "ep-2", source: .provided)
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated,
                                                model: model, windows: [window(0)]))
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-2", podcastUuid: "pod-1", source: .provided,
                                                model: model, windows: [window(0)]))

        XCTAssertTrue(search.delete(episodeUuid: "ep-1", source: .generated))
        XCTAssertFalse(embeddings.isEmbedded(episodeUuid: "ep-1", source: .generated, model: model))
        XCTAssertTrue(embeddings.isEmbedded(episodeUuid: "ep-2", source: .provided, model: model))

        XCTAssertTrue(search.removeAll(source: .provided))
        XCTAssertFalse(embeddings.isEmbedded(episodeUuid: "ep-2", source: .provided, model: model))
        XCTAssertEqual(embeddings.totalVectorBytes(), 0)
    }

    func testByteCapEvictionCascadesToVectors() {
        // A tiny cap: indexing a second provided episode evicts the first.
        let cappedSearch = TranscriptSearchDataManager(dbQueue: dataManager.testDbQueue, maxTotalTextBytes: 60)
        let text = String(repeating: "words and more words ", count: 3) // > 30 bytes

        XCTAssertTrue(cappedSearch.replaceSegments(episodeUuid: "ep-old", podcastUuid: "pod-1", source: .provided,
                                                   segments: [TranscriptSearchSegment(index: 0, text: text, startTime: 0)]))
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-old", podcastUuid: "pod-1", source: .provided,
                                                model: model, windows: [window(0)]))

        XCTAssertTrue(cappedSearch.replaceSegments(episodeUuid: "ep-new", podcastUuid: "pod-1", source: .provided,
                                                   segments: [TranscriptSearchSegment(index: 0, text: text, startTime: 0)]))

        XCTAssertFalse(cappedSearch.isIndexed(episodeUuid: "ep-old", source: .provided), "the old pair was evicted")
        XCTAssertFalse(embeddings.isEmbedded(episodeUuid: "ep-old", source: .provided, model: model),
                       "eviction must take the vectors with it")
    }

    // MARK: - Candidate filters

    func testCandidateFiltersNarrowTheScan() {
        let podcast = createTestPodcast(uuid: "pod-1", title: "Show", dataManager: dataManager)
        var early = createTestEpisode(uuid: "ep-early", podcast: podcast, title: "Early", dataManager: dataManager)
        early.publishedDate = Date(timeIntervalSince1970: 1_000)
        early = dataManager.save(episode: early)
        var late = createTestEpisode(uuid: "ep-late", podcast: podcast, title: "Late", dataManager: dataManager)
        late.publishedDate = Date(timeIntervalSince1970: 2_000)
        late = dataManager.save(episode: late)

        for uuid in ["ep-early", "ep-late"] {
            indexCorpus(episodeUuid: uuid, podcastUuid: "pod-1", source: .generated)
            XCTAssertTrue(embeddings.replaceWindows(episodeUuid: uuid, podcastUuid: "pod-1", source: .generated,
                                                    model: model, windows: [window(0)]))
        }
        indexCorpus(episodeUuid: "ep-other", podcastUuid: "pod-2", source: .provided)
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-other", podcastUuid: "pod-2", source: .provided,
                                                model: model, windows: [window(0)]))

        func episodeUuids(_ filter: TranscriptEmbeddingCandidateFilter) -> Set<String> {
            var uuids = Set<String>()
            embeddings.candidates(model: model, filter: filter) { batch in
                uuids.formUnion(batch.map(\.episodeUuid))
            }
            return uuids
        }

        XCTAssertEqual(episodeUuids(.init()), ["ep-early", "ep-late", "ep-other"])
        XCTAssertEqual(episodeUuids(.init(source: .provided)), ["ep-other"])
        XCTAssertEqual(episodeUuids(.init(podcastUuid: "pod-1")), ["ep-early", "ep-late"])
        XCTAssertEqual(episodeUuids(.init(podcastUuid: "pod-1", excludeEpisodeUuid: "ep-late")), ["ep-early"])
        // The callback-detection shape: same podcast, published before this episode.
        XCTAssertEqual(episodeUuids(.init(podcastUuid: "pod-1", publishedBefore: Date(timeIntervalSince1970: 1_500))), ["ep-early"])
    }

    func testCandidatesStreamInBatchesCoveringEverything() {
        indexCorpus(episodeUuid: "ep-1")
        let windows = (0 ..< 7).map { window($0, vectorByte: UInt8($0)) }
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated,
                                                model: model, windows: windows))

        var batchSizes: [Int] = []
        var seen: [Int] = []
        embeddings.candidates(model: model, batchSize: 3) { batch in
            batchSizes.append(batch.count)
            seen.append(contentsOf: batch.map(\.windowIndex))
        }
        XCTAssertEqual(batchSizes, [3, 3, 1])
        XCTAssertEqual(seen, Array(0 ..< 7), "keyset pagination covers every window exactly once, in order")
    }

    // MARK: - Backfill work list

    func testPendingPairsListsUnembeddedNewestFirst() {
        indexCorpus(episodeUuid: "ep-a")
        indexCorpus(episodeUuid: "ep-b")
        XCTAssertTrue(embeddings.replaceWindows(episodeUuid: "ep-a", podcastUuid: "pod-1", source: .generated,
                                                model: model, windows: [window(0)]))

        let pending = embeddings.pendingPairs(model: model)
        XCTAssertEqual(pending.map(\.episodeUuid), ["ep-b"])
        XCTAssertEqual(pending.first?.source, .generated)
    }
}
