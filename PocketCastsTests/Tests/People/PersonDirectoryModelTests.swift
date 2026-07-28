import Combine
import PocketCastsDataModel
import XCTest

@testable import podcasts

@MainActor
final class PersonDirectoryModelTests: XCTestCase {

    private func record(episode: String, podcast: String? = "pod-1", names: [String: String]?) -> EpisodeTranscriptionRecord {
        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = episode
        record.podcastUuid = podcast
        record.status = TranscriptionStatus.completed.rawValue
        if let names,
           let data = try? JSONEncoder().encode(names) {
            record.speakerNames = String(data: data, encoding: .utf8)
        }
        return record
    }

    func testAggregatesRenamesByExactDisplayName() {
        let records = [
            record(episode: "ep-1", names: ["Speaker 1": "Alice", "Speaker 2": "Bob"]),
            record(episode: "ep-2", names: ["Speaker 3": "Alice "]),
            record(episode: "ep-3", names: ["Speaker 1": "Carol"])
        ]

        let entries = PersonDirectoryBuilder.entries(
            from: records,
            existingEpisodeUuids: Set(records.map(\.episodeUuid))
        )

        XCTAssertEqual(entries.map(\.displayName), ["Alice", "Bob", "Carol"],
                       "most appearances first, then alphabetical; whitespace-trimmed names merge")
        let alice = entries[0]
        XCTAssertEqual(alice.appearances.count, 2)
        XCTAssertEqual(Set(alice.appearances.map(\.episodeUuid)), ["ep-1", "ep-2"])
        XCTAssertEqual(alice.appearances.first { $0.episodeUuid == "ep-2" }?.canonicalSpeaker, "Speaker 3",
                       "the canonical label rides along for segment scoping")
    }

    func testDropsAppearancesWhoseEpisodeIsGone() {
        let records = [
            record(episode: "ep-live", names: ["Speaker 1": "Alice"]),
            record(episode: "ep-gone", names: ["Speaker 1": "Alice", "Speaker 2": "Ghost"])
        ]

        let entries = PersonDirectoryBuilder.entries(from: records, existingEpisodeUuids: ["ep-live"])

        XCTAssertEqual(entries.map(\.displayName), ["Alice"])
        XCTAssertEqual(entries[0].appearances.map(\.episodeUuid), ["ep-live"])
    }

    func testIgnoresEmptyNamesAndRecordsWithoutRenames() {
        let records = [
            record(episode: "ep-1", names: ["Speaker 1": "  ", "Speaker 2": ""]),
            record(episode: "ep-2", names: nil)
        ]
        XCTAssertTrue(PersonDirectoryBuilder.entries(
            from: records,
            existingEpisodeUuids: Set(records.map(\.episodeUuid))
        ).isEmpty)
    }

    func testSameNameDifferentEpisodesShareOneEntry() {
        // The documented v1 trade-off: identity IS the display name.
        let records = [
            record(episode: "ep-1", podcast: "pod-a", names: ["Speaker 1": "John Smith"]),
            record(episode: "ep-2", podcast: "pod-b", names: ["Speaker 4": "John Smith"])
        ]
        let entries = PersonDirectoryBuilder.entries(
            from: records,
            existingEpisodeUuids: Set(records.map(\.episodeUuid))
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(entries[0].appearances.map(\.podcastUuid)), ["pod-a", "pod-b"])
    }

    func testDirectoryLoadBatchesEpisodeLookupAndIsIdempotentAcrossReappearance() async {
        let records = [
            record(episode: "ep-1", names: ["Speaker 1": "Alice"]),
            record(episode: "ep-2", names: ["Speaker 2": "Bob"]),
            record(episode: "ep-gone", names: ["Speaker 3": "Ghost"])
        ]
        let probe = EpisodeBatchProbe(existing: ["ep-1", "ep-2"])
        let tracked = expectation(description: "directory analytics tracked after loading")
        let analytics = PeopleAnalyticsRecorder { tracked.fulfill() }
        let model = PersonDirectoryModel(
            recordsProvider: { records },
            existingEpisodeUuidsProvider: { await probe.resolve($0) },
            directoryShownTracker: { analytics.trackDirectory(count: $0) }
        )

        model.load()
        model.load() // SwiftUI can reappear while the first load is still in flight.
        await fulfillment(of: [tracked], timeout: 1)
        model.load() // A later reappearance must remain idempotent as well.
        await Task.yield()

        let requests = await probe.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(Set(requests[0]), ["ep-1", "ep-2", "ep-gone"])
        XCTAssertEqual(model.entries.map(\.displayName), ["Alice", "Bob"])
        XCTAssertEqual(analytics.directoryCounts, [2])
    }

    func testDirectoryAnalyticsWaitsForActualLoadCompletion() async {
        let records = [record(episode: "ep-1", names: ["Speaker 1": "Alice"])]
        let gate = SingleValueGate(value: records)
        let tracked = expectation(description: "directory analytics tracked")
        let analytics = PeopleAnalyticsRecorder { tracked.fulfill() }
        let model = PersonDirectoryModel(
            recordsProvider: { await gate.value() },
            existingEpisodeUuidsProvider: { Set($0) },
            directoryShownTracker: { analytics.trackDirectory(count: $0) }
        )

        model.load()
        await gate.waitUntilStarted()
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(analytics.directoryCounts.isEmpty)

        await gate.resume()
        await fulfillment(of: [tracked], timeout: 1)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(analytics.directoryCounts, [1])
    }

    func testPersonDetailLoadIsIdempotentWhenViewReappears() async {
        let probe = InvocationProbe()
        let loaded = expectation(description: "episode rows loaded")
        var cancellables = Set<AnyCancellable>()
        let model = PersonDetailModel(
            entry: Self.personEntry,
            episodesProvider: { _ in
                await probe.record()
                return [Self.episodeRow]
            }
        )
        model.$episodes
            .dropFirst()
            .sink { rows in
                if rows == [Self.episodeRow] { loaded.fulfill() }
            }
            .store(in: &cancellables)

        model.load()
        model.load()
        await fulfillment(of: [loaded], timeout: 1)
        model.load()
        await Task.yield()

        let invocationCount = await probe.count
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(model.episodes, [Self.episodeRow])
        withExtendedLifetime(cancellables) {}
    }

    func testRapidSearchNeverPublishesSupersededIdenticalTermResult() async {
        let gate = SearchResultGate()
        let publishedNewest = expectation(description: "newest repeated search published")
        let stalePublished = expectation(description: "superseded search must not publish")
        stalePublished.isInverted = true
        let analytics = PeopleAnalyticsRecorder()
        var cancellables = Set<AnyCancellable>()
        let newest = Self.display(episodeUuid: "newest")
        let stale = Self.display(episodeUuid: "stale")
        let model = PersonDetailModel(
            entry: Self.personEntry,
            searchProvider: { term, _ in await gate.value(for: term) },
            searchTracker: { analytics.trackSearch(count: $0) }
        )
        model.$searchHits
            .dropFirst()
            .sink { hits in
                if hits == [newest] { publishedNewest.fulfill() }
                if hits == [stale] { stalePublished.fulfill() }
            }
            .store(in: &cancellables)

        model.searchTerm = "same"
        await gate.waitForInvocation(term: "same", count: 1)
        model.searchTerm = "other"
        await gate.waitForInvocation(term: "other", count: 1)
        model.searchTerm = "same"
        await gate.waitForInvocation(term: "same", count: 2)

        await gate.resumeLast(term: "same", returning: [newest])
        await fulfillment(of: [publishedNewest], timeout: 1)
        await gate.resumeFirst(term: "same", returning: [stale])
        await gate.resumeFirst(term: "other", returning: [])
        await fulfillment(of: [stalePublished], timeout: 0.1)

        XCTAssertEqual(model.searchHits, [newest])
        XCTAssertEqual(analytics.searchCounts, [1])
        withExtendedLifetime(cancellables) {}
    }

    private static let personEntry = PersonDirectoryEntry(
        displayName: "Alice",
        appearances: [PersonAppearance(episodeUuid: "ep-1", podcastUuid: "pod-1", canonicalSpeaker: "Speaker 1")]
    )

    // nonisolated: read from the nonisolated episodesProvider closure.
    nonisolated private static let episodeRow = PersonDetailModel.EpisodeRow(
        uuid: "ep-1",
        podcastUuid: "pod-1",
        title: "Episode",
        podcastTitle: "Podcast"
    )

    private static func display(episodeUuid: String) -> TranscriptSearchHitDisplay {
        TranscriptSearchHitDisplay(
            episodeUuid: episodeUuid,
            podcastUuid: "pod-1",
            segmentIndex: 0,
            episodeTitle: episodeUuid,
            runs: [.init(text: episodeUuid, isHighlighted: false)],
            startTime: 0,
            speaker: "Speaker 1",
            source: .generated
        )
    }
}

private actor EpisodeBatchProbe {
    let existing: Set<String>
    private(set) var requests: [[String]] = []

    init(existing: Set<String>) {
        self.existing = existing
    }

    func resolve(_ uuids: [String]) -> Set<String> {
        requests.append(uuids)
        return existing
    }
}

private actor InvocationProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private actor SingleValueGate<Value: Sendable> {
    private let result: Value
    private var resultContinuation: CheckedContinuation<Value, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var started = false

    init(value: Value) {
        result = value
    }

    func value() async -> Value {
        await withCheckedContinuation { continuation in
            resultContinuation = continuation
            started = true
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resume() {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

private actor SearchResultGate {
    private var continuations: [String: [CheckedContinuation<[TranscriptSearchHitDisplay], Never>]] = [:]
    private var invocationCounts: [String: Int] = [:]
    private var waiters: [(term: String, count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func value(for term: String) async -> [TranscriptSearchHitDisplay] {
        await withCheckedContinuation { continuation in
            continuations[term, default: []].append(continuation)
            invocationCounts[term, default: 0] += 1
            resumeSatisfiedWaiters()
        }
    }

    func waitForInvocation(term: String, count: Int) async {
        guard invocationCounts[term, default: 0] < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((term, count, continuation))
        }
    }

    func resumeFirst(term: String, returning result: [TranscriptSearchHitDisplay]) {
        guard var pending = continuations[term], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        continuations[term] = pending
        continuation.resume(returning: result)
    }

    func resumeLast(term: String, returning result: [TranscriptSearchHitDisplay]) {
        guard var pending = continuations[term], !pending.isEmpty else { return }
        let continuation = pending.removeLast()
        continuations[term] = pending
        continuation.resume(returning: result)
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(term: String, count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if invocationCounts[waiter.term, default: 0] >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}

@MainActor
private final class PeopleAnalyticsRecorder {
    private let onDirectoryTrack: @MainActor () -> Void
    private(set) var directoryCounts: [Int] = []
    private(set) var searchCounts: [Int] = []

    init(onDirectoryTrack: @escaping @MainActor () -> Void = {}) {
        self.onDirectoryTrack = onDirectoryTrack
    }

    func trackDirectory(count: Int) {
        directoryCounts.append(count)
        onDirectoryTrack()
    }

    func trackSearch(count: Int) {
        searchCounts.append(count)
    }
}
