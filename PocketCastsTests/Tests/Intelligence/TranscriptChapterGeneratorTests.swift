import FoundationModels
import Synchronization
import XCTest

@testable import podcasts

nonisolated private final class CountingChapterIntelligence: IntelligenceProviding {
    private struct Counts: Sendable {
        var availability = 0
        var responses = 0
    }

    private let counts = Mutex(Counts())
    private let availabilityResult: IntelligenceAvailability
    private let response: @Sendable () throws -> GeneratedChapterList

    init(
        availability: IntelligenceAvailability = .available,
        response: @escaping @Sendable () throws -> GeneratedChapterList = {
            GeneratedChapterList(chapters: [])
        }
    ) {
        self.availabilityResult = availability
        self.response = response
    }

    func availability() -> IntelligenceAvailability {
        counts.withLock { $0.availability += 1 }
        return availabilityResult
    }

    func respond<T: Generable & Sendable>(
        instructions: String,
        prompt: String,
        generating type: T.Type
    ) async throws -> T {
        counts.withLock { $0.responses += 1 }
        guard let value = try response() as? T else {
            throw IntelligenceError.decodingFailed
        }
        return value
    }

    var callCounts: (availability: Int, responses: Int) {
        counts.withLock { ($0.availability, $0.responses) }
    }
}

/// Pure validation of on-device chapter generation and the per-episode cache.
@MainActor
final class TranscriptChapterGeneratorTests: XCTestCase {
    private let cueStarts: [TimeInterval] = Array(stride(from: 0.0, through: 3600, by: 30))
    private let productionCues = (0 ..< 12).map {
        TimedCueText(startTime: TimeInterval($0 * 60), text: "Transcript cue \($0)")
    }

    private func item(_ title: String, _ seconds: Int) -> GeneratedChapterListItem {
        GeneratedChapterListItem(title: title, startSeconds: seconds)
    }

    func testValidationSnapsSortsAndSpacesChapters() {
        let raw = [
            item("Closing thoughts", 3550),
            item("Intro", 12),
            item("Main topic", 900),
            item("Too close to main topic", 930),
            item("  ", 1800)
        ]

        let chapters = TranscriptChapterGenerator.validated(raw, cueStartTimes: cueStarts, duration: 3600)

        XCTAssertEqual(chapters.map(\.title), ["Intro", "Main topic", "Closing thoughts"])
        XCTAssertEqual(chapters.first?.startTime, 0, "An opening chapter near zero is pulled to the episode start")
        XCTAssertEqual(chapters.map(\.startTime), chapters.map(\.startTime).sorted())
        XCTAssertTrue(zip(chapters, chapters.dropFirst()).allSatisfy { $1.startTime - $0.startTime >= 60 },
                      "Chapters closer than the minimum gap are dropped")
    }

    func testValidationDropsUnsnappableTimestamps() {
        // Cues only cover the first 10 minutes; a chapter at 50 minutes has no
        // nearby cue and must be dropped rather than invented.
        let shortCues: [TimeInterval] = Array(stride(from: 0.0, through: 600, by: 30))
        let chapters = TranscriptChapterGenerator.validated([item("Ghost", 3000), item("Real", 300)],
                                                            cueStartTimes: shortCues,
                                                            duration: 3600)

        XCTAssertEqual(chapters.map(\.title), ["Real"])
    }

    func testValidationClampsToDuration() {
        let chapters = TranscriptChapterGenerator.validated([item("Beyond the end", 9000)],
                                                            cueStartTimes: cueStarts,
                                                            duration: 3600)

        XCTAssertEqual(chapters.map(\.startTime), [3600])
    }

    // MARK: - Chapter digest (review finding P2-19)

    func testChapterDigestSamplesTheWholeEpisodeWithinBudget() {
        // ~2 hours of cues, far beyond the budget: a prefix digest would only
        // ever describe the head of the episode.
        let cues = (0 ..< 400).map { TimedCueText(startTime: TimeInterval($0 * 18), text: "cue \($0) words words words") }

        let digest = TranscriptChapterGenerator.chapterDigest(from: cues, characterBudget: 1_200)

        XCTAssertLessThanOrEqual(digest.count, 1_200)

        let times = digest.split(separator: "\n").compactMap { line -> Int? in
            guard let end = line.firstIndex(of: "]") else { return nil }
            return Int(line[line.index(after: line.startIndex) ..< end])
        }
        XCTAssertFalse(times.isEmpty)
        XCTAssertEqual(times, times.sorted(), "Sampled lines stay in listening order")
        let lastCueTime = Int(cues.last!.startTime)
        XCTAssertGreaterThanOrEqual(times.max() ?? 0, lastCueTime - lastCueTime / 12,
                                    "The episode tail must be represented, not truncated away")
        XCTAssertLessThanOrEqual(times.min() ?? .max, lastCueTime / 12,
                                 "The episode head must still be represented")
    }

    func testChapterDigestKeepsEverythingWhenItFits() {
        let cues = (0 ..< 5).map { TimedCueText(startTime: TimeInterval($0 * 60), text: "short cue \($0)") }

        let digest = TranscriptChapterGenerator.chapterDigest(from: cues)

        XCTAssertEqual(digest, SummaryTakeawayGenerator.digest(from: cues),
                       "Short transcripts need no sampling and match the plain digest")
        XCTAssertEqual(digest.split(separator: "\n").count, 5)
    }

    func testChapterDigestPreservesTimestampLineFormatAndCapsCues() {
        let cues = [
            TimedCueText(startTime: 5.4, text: String(repeating: "a", count: 5_000)),
            TimedCueText(startTime: 600, text: "  tail cue  ")
        ]

        let digest = TranscriptChapterGenerator.chapterDigest(from: cues, cueCharacterCap: 100)

        let lines = digest.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("[5] "), "Lines keep the bracketed-seconds shape validated() snaps against")
        XCTAssertLessThanOrEqual(lines[0].count, 104, "Runaway cues are individually capped")
        XCTAssertEqual(lines[1], "[600] tail cue")
    }

    func testTimestampStringFormats() {
        XCTAssertEqual(TranscriptChapterGenerator.timestampString(for: 65), "1:05")
        XCTAssertEqual(TranscriptChapterGenerator.timestampString(for: 3725), "1:02:05")
    }

    // MARK: - Production entry point

    func testChaptersReturnsCachedSuccessWithoutConsultingModel() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.save(.chapters([
            GeneratedChapter(title: "Cached", timestamp: "0:00", startTime: 0)
        ]), episodeUuid: "cached")
        let intelligence = CountingChapterIntelligence()

        let chapters = await TranscriptChapterGenerator(intelligence: intelligence, store: store)
            .chapters(episodeUuid: "cached", cues: productionCues, duration: 700)

        XCTAssertEqual(chapters.map(\.title), ["Cached"])
        XCTAssertEqual(intelligence.callCounts.availability, 0)
        XCTAssertEqual(intelligence.callCounts.responses, 0)
    }

    func testInsufficientCuesCachesNoChaptersAndSuppressesEligibleRetry() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let intelligence = CountingChapterIntelligence()
        let generator = TranscriptChapterGenerator(intelligence: intelligence, store: store)

        let first = await generator.chapters(
            episodeUuid: "thin",
            cues: Array(productionCues.prefix(9)),
            duration: 700
        )
        let second = await generator.chapters(
            episodeUuid: "thin",
            cues: productionCues,
            duration: 700
        )

        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(intelligence.callCounts.availability, 0)
        XCTAssertEqual(intelligence.callCounts.responses, 0)
        guard case .noChapters? = store.load(episodeUuid: "thin") else {
            XCTFail("The completed no-chapters outcome should be distinct from a cache miss")
            return
        }
    }

    func testUnavailableModelOutcomeIsCached() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let intelligence = CountingChapterIntelligence(
            availability: .unavailable(reason: "model_not_ready")
        )
        let generator = TranscriptChapterGenerator(intelligence: intelligence, store: store)

        let first = await generator.chapters(episodeUuid: "unavailable", cues: productionCues, duration: 700)
        let second = await generator.chapters(episodeUuid: "unavailable", cues: productionCues, duration: 700)

        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(intelligence.callCounts.availability, 1)
        XCTAssertEqual(intelligence.callCounts.responses, 0)
        guard case .noChapters? = store.load(episodeUuid: "unavailable") else {
            XCTFail("Model unavailability should persist the no-chapters outcome")
            return
        }
    }

    func testGenerationErrorOutcomeIsCached() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let intelligence = CountingChapterIntelligence(response: {
            throw IntelligenceError.timedOut
        })
        let generator = TranscriptChapterGenerator(intelligence: intelligence, store: store)

        let first = await generator.chapters(episodeUuid: "error", cues: productionCues, duration: 700)
        let second = await generator.chapters(episodeUuid: "error", cues: productionCues, duration: 700)

        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(intelligence.callCounts.availability, 1)
        XCTAssertEqual(intelligence.callCounts.responses, 1)
        guard case .noChapters? = store.load(episodeUuid: "error") else {
            XCTFail("A completed generation failure should suppress repeated model work")
            return
        }
    }

    func testEmptyValidatedOutcomeIsCached() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let intelligence = CountingChapterIntelligence(response: {
            GeneratedChapterList(chapters: [])
        })
        let generator = TranscriptChapterGenerator(intelligence: intelligence, store: store)

        let first = await generator.chapters(episodeUuid: "empty", cues: productionCues, duration: 700)
        let second = await generator.chapters(episodeUuid: "empty", cues: productionCues, duration: 700)

        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(intelligence.callCounts.responses, 1)
        guard case .noChapters? = store.load(episodeUuid: "empty") else {
            XCTFail("Empty validated output should suppress repeated model work")
            return
        }
    }

    func testCancellationDoesNotPoisonCache() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cancelled = CountingChapterIntelligence(response: {
            throw CancellationError()
        })

        let cancelledResult = await TranscriptChapterGenerator(intelligence: cancelled, store: store)
            .chapters(episodeUuid: "cancelled", cues: productionCues, duration: 700)
        XCTAssertTrue(cancelledResult.isEmpty)
        XCTAssertNil(store.load(episodeUuid: "cancelled"))

        let succeeding = CountingChapterIntelligence(response: {
            GeneratedChapterList(chapters: [
                GeneratedChapterListItem(title: "Intro", startSeconds: 0),
                GeneratedChapterListItem(title: "Middle", startSeconds: 180),
                GeneratedChapterListItem(title: "End", startSeconds: 420)
            ])
        })
        let chapters = await TranscriptChapterGenerator(intelligence: succeeding, store: store)
            .chapters(episodeUuid: "cancelled", cues: productionCues, duration: 700)

        XCTAssertEqual(chapters.map(\.title), ["Intro", "Middle", "End"])
        XCTAssertEqual(succeeding.callCounts.responses, 1)
    }

    func testStoreRoundTripsChapters() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceChapterStore(directoryURL: directory)

        XCTAssertNil(store.load(episodeUuid: "ep-1"))

        let chapters = [
            GeneratedChapter(title: "Intro", timestamp: "0:00", startTime: 0),
            GeneratedChapter(title: "Topic", timestamp: "15:00", startTime: 900)
        ]
        store.save(.chapters(chapters), episodeUuid: "ep-1")

        guard case .chapters(let loaded)? = store.load(episodeUuid: "ep-1") else {
            XCTFail("Expected a cached chapter list")
            return
        }
        XCTAssertEqual(loaded.map(\.title), ["Intro", "Topic"])
        XCTAssertEqual(loaded.map(\.startTime), [0, 900])
        XCTAssertEqual(loaded.map(\.timestamp), ["0:00", "15:00"], "Timestamps regenerate from start times")
        XCTAssertNil(store.load(episodeUuid: "ep-other"))
    }

    func testStoreIgnoresLegacySchemaEntries() throws {
        // v1 entries can carry reference-timeline, head-only chapter lists
        // (P2-18/P2-19); the schema bump must orphan them so they regenerate.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacyPayload = Data(#"[{"title":"Stale","startTime":5}]"#.utf8)
        try legacyPayload.write(to: directory.appendingPathComponent("ep-1.json"))
        try legacyPayload.write(to: directory.appendingPathComponent("ep-1.v2.json"))

        let store = OnDeviceChapterStore(directoryURL: directory)
        XCTAssertNil(store.load(episodeUuid: "ep-1"), "Legacy v1/v2 cache entries must not be served")

        store.save(.chapters([
            GeneratedChapter(title: "Fresh", timestamp: "0:05", startTime: 5)
        ]), episodeUuid: "ep-1")
        let versionedFile = directory.appendingPathComponent("ep-1.v\(OnDeviceChapterStore.schemaVersion).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: versionedFile.path))
        guard case .chapters(let loaded)? = store.load(episodeUuid: "ep-1") else {
            XCTFail("Expected the versioned chapter list")
            return
        }
        XCTAssertEqual(loaded.map(\.title), ["Fresh"])
    }

    func testStoreRoundTripsNoChaptersDistinctFromMiss() {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(store.load(episodeUuid: "ep-none"))
        store.save(.noChapters, episodeUuid: "ep-none")

        guard case .noChapters? = store.load(episodeUuid: "ep-none") else {
            XCTFail("Expected a persisted no-chapters sentinel")
            return
        }
        XCTAssertNil(store.load(episodeUuid: "ep-unattempted"))
    }

    private func temporaryStore() -> (OnDeviceChapterStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-store-\(UUID().uuidString)", isDirectory: true)
        return (OnDeviceChapterStore(directoryURL: directory), directory)
    }
}
