import PocketCastsDataModel
import XCTest

@testable import podcasts

private actor EntityChunkResponseProbe {
    nonisolated enum Mode: Sendable {
        case manuallyReleased
        case suspendUntilCancelled
    }

    struct Snapshot: Sendable {
        let startedChunks: [String]
        let activeCount: Int
        let maximumActiveCount: Int
    }

    private let mode: Mode
    private var startedChunks: [String] = []
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var releases: [Int: CheckedContinuation<Void, Never>] = [:]
    private var cancellationWaiters: [Int: CheckedContinuation<Void, Error>] = [:]
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func respond(to chunk: String) async throws -> [GeneratedEntityItem] {
        startedChunks.append(chunk)
        let invocation = startedChunks.count
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        resumeSatisfiedStartWaiters()
        defer { activeCount -= 1 }

        switch mode {
        case .manuallyReleased:
            await withCheckedContinuation { continuation in
                releases[invocation] = continuation
            }
        case .suspendUntilCancelled:
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { continuation in
                    cancellationWaiters[invocation] = continuation
                }
            } onCancel: {
                Task { await self.cancel(invocation) }
            }
        }

        return [GeneratedEntityItem(name: "Entity \(invocation)", kind: "person", startSeconds: invocation)]
    }

    func waitUntilStarted(_ expectedCount: Int) async {
        guard startedChunks.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((expectedCount, continuation))
        }
    }

    func release(_ invocation: Int) {
        releases.removeValue(forKey: invocation)?.resume()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            startedChunks: startedChunks,
            activeCount: activeCount,
            maximumActiveCount: maximumActiveCount
        )
    }

    private func resumeSatisfiedStartWaiters() {
        let satisfied = startWaiters.filter { $0.count <= startedChunks.count }
        startWaiters.removeAll { $0.count <= startedChunks.count }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
    }

    private func cancel(_ invocation: Int) {
        cancellationWaiters.removeValue(forKey: invocation)?.resume(throwing: CancellationError())
    }
}

final class EntityMentionGeneratorTests: XCTestCase {

    private func segment(_ index: Int, _ text: String, start: TimeInterval? = nil) -> TranscriptSearchSegment {
        TranscriptSearchSegment(index: index, text: text, startTime: start ?? TimeInterval(index * 30))
    }

    private func item(_ name: String, kind: String = "person", seconds: Int = 0) -> GeneratedEntityItem {
        GeneratedEntityItem(name: name, kind: kind, startSeconds: seconds)
    }

    nonisolated private static func startGeneratedItems(
        chunks: [String],
        probe: EntityChunkResponseProbe
    ) -> Task<[GeneratedEntityItem], Error> {
        Task.detached {
            try await EntityMentionGenerator.generatedItems(chunks: chunks) { chunk in
                try await probe.respond(to: chunk)
            }
        }
    }

    // MARK: - Chunking

    func testChunksRespectBudgetAndCarryTimestamps() {
        let segments = (0 ..< 30).map { segment($0, String(repeating: "w", count: 500)) }
        let chunks = EntityMentionGenerator.chunks(from: segments, characterBudget: 2000, maxChunks: 100)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 2000)
        }
        XCTAssertTrue(chunks[0].hasPrefix("[0] "), "lines carry bracketed second stamps")
        let totalLines = chunks.reduce(0) { $0 + $1.split(separator: "\n").count }
        XCTAssertEqual(totalLines, 30, "every segment lands in exactly one chunk")
    }

    func testChunksBeyondCapDropTheTail() {
        let segments = (0 ..< 30).map { segment($0, String(repeating: "w", count: 500)) }
        let chunks = EntityMentionGenerator.chunks(from: segments, characterBudget: 2000, maxChunks: 2)
        XCTAssertEqual(chunks.count, 2)
    }

    // MARK: - Model chunk admission / cancellation

    func testGeneratedItemsRunsChunksSeriallyInTranscriptOrder() async throws {
        let probe = EntityChunkResponseProbe(mode: .manuallyReleased)
        let task = Self.startGeneratedItems(chunks: ["first", "second"], probe: probe)

        await probe.waitUntilStarted(1)
        var snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.startedChunks, ["first"])
        XCTAssertEqual(snapshot.activeCount, 1)

        await probe.release(1)
        await probe.waitUntilStarted(2)
        snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.startedChunks, ["first", "second"])
        XCTAssertEqual(snapshot.activeCount, 1)
        XCTAssertEqual(snapshot.maximumActiveCount, 1)

        await probe.release(2)
        let items = try await task.value
        XCTAssertEqual(items.map(\.name), ["Entity 1", "Entity 2"])
    }

    func testGeneratedItemsCancellationStopsBeforeTheNextChunk() async {
        let probe = EntityChunkResponseProbe(mode: .suspendUntilCancelled)
        let task = Self.startGeneratedItems(chunks: ["first", "must-not-start"], probe: probe)
        await probe.waitUntilStarted(1)

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must terminate chunk generation")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
        }
        let snapshot = await probe.snapshot()

        XCTAssertEqual(snapshot.startedChunks, ["first"])
        XCTAssertEqual(snapshot.activeCount, 0)
        XCTAssertEqual(snapshot.maximumActiveCount, 1)
    }

    // MARK: - Merging / validation

    func testMergedValidatesKindsSnapsTimesAndDedupes() {
        let startTimes: [TimeInterval] = [0, 30, 60, 90]
        let merged = EntityMentionGenerator.merged([
            item("Alice", kind: "person", seconds: 33),           // snaps to 30
            item("alice", kind: "person", seconds: 92),           // fold-dupe, later -> dropped
            item("Dune", kind: "book", seconds: 61),              // snaps to 60
            item("Mystery", kind: "spaceship", seconds: 0),       // bad kind
            item("Nowhere", kind: "place", seconds: 500),         // no segment within 30s
            item("", kind: "person", seconds: 0),                 // empty name
            item("12345", kind: "product", seconds: 0)            // no letters
        ], segmentStartTimes: startTimes)

        XCTAssertEqual(merged.map(\.name), ["Alice", "Dune"], "earliest mention first")
        XCTAssertEqual(merged[0].startTime, 30)
        XCTAssertEqual(merged[0].kind, .person)
        XCTAssertEqual(merged[1].startTime, 60)
        XCTAssertEqual(merged[1].kind, .book)
    }

    func testMergedKeepsEarliestMentionOfDuplicates() {
        let merged = EntityMentionGenerator.merged([
            item("Alice", seconds: 90),
            item("Alice", seconds: 0)
        ], segmentStartTimes: [0, 30, 60, 90])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].startTime, 0)
    }

    func testMergedSortsSegmentTimesAndIgnoresCorruptAnchors() {
        let merged = EntityMentionGenerator.merged(
            [item("Midpoint", seconds: 45)],
            segmentStartTimes: [.nan, 60, .infinity, 0, -30, 30]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].startTime, 30, "an exact tie deterministically chooses the earlier seek point")
    }

    func testMergedRejectsAnIndexWithNoValidSeekAnchors() {
        let merged = EntityMentionGenerator.merged(
            [item("Alice", seconds: 0)],
            segmentStartTimes: [.nan, -.infinity, .infinity, -1]
        )

        XCTAssertTrue(merged.isEmpty)
    }

    func testMergedCapsAtMaxEntities() {
        let raw = (0 ..< 20).map { item("Entity Number \($0)", seconds: $0 * 30) }
        let merged = EntityMentionGenerator.merged(raw, segmentStartTimes: (0 ..< 20).map { TimeInterval($0 * 30) })
        XCTAssertEqual(merged.count, EntityMentionGenerator.maxEntities)
    }

    // MARK: - NLTagger fallback

    func testTaggerFallbackFindsPeopleAndPlaces() {
        let segments = [
            segment(0, "Tim Cook visited Paris last week to meet with Apple employees.", start: 12),
            segment(1, "It rained the whole time, which nobody enjoyed.", start: 42)
        ]
        let mentions = EntityMentionGenerator.taggerMentions(from: segments)

        XCTAssertTrue(mentions.contains { $0.name == "Tim Cook" && $0.kind == .person && $0.startTime == 12 })
        XCTAssertTrue(mentions.contains { $0.name == "Paris" && $0.kind == .place })
        XCTAssertTrue(mentions.allSatisfy { $0.kind == .person || $0.kind == .place || $0.kind == .organization },
                      "the fallback never claims kinds it can't detect")
    }

    // MARK: - Store

    func testStoreRoundTripsAndInvalidatesOnFingerprintMismatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("entity-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceEntityStore(directoryURL: directory)

        let mentions = [EntityMention(name: "Alice", kind: .person, startTime: 30)]
        store.save(mentions, episodeUuid: "ep-1", fingerprint: "generated-10-300")

        XCTAssertEqual(store.load(episodeUuid: "ep-1", fingerprint: "generated-10-300"), mentions)
        XCTAssertNil(store.load(episodeUuid: "ep-1", fingerprint: "generated-12-360"), "a re-indexed transcript reads as a miss")
        XCTAssertNil(store.load(episodeUuid: "ep-other", fingerprint: "generated-10-300"))
    }
}
