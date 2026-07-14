import CoreSpotlight
import Foundation
import XCTest

@testable import podcasts

/// Recording fake for `SearchableIndexing`. File-scope and explicitly
/// nonisolated: the coordinator calls it off the main actor.
nonisolated private final class FakeIndex: SearchableIndexing, @unchecked Sendable {
    enum Call: Equatable {
        case index([String])
        case delete([String])
        case deleteAll([String])
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private var available = true
    private var failNext = false

    var calls: [Call] { lock.withLock { recordedCalls } }
    func setAvailable(_ value: Bool) { lock.withLock { available = value } }
    func setFailNext() { lock.withLock { failNext = true } }

    func isAvailable() -> Bool { lock.withLock { available } }

    nonisolated(nonsending) func index(_ items: [CSSearchableItem]) async throws {
        try recordOrThrow(.index(items.map(\.uniqueIdentifier).sorted()))
    }

    nonisolated(nonsending) func deleteItems(identifiers: [String]) async throws {
        try recordOrThrow(.delete(identifiers.sorted()))
    }

    nonisolated(nonsending) func deleteAll(domainIdentifiers: [String]) async throws {
        try recordOrThrow(.deleteAll(domainIdentifiers.sorted()))
    }

    private func recordOrThrow(_ call: Call) throws {
        let shouldThrow: Bool = lock.withLock {
            if failNext {
                failNext = false
                return true
            }
            recordedCalls.append(call)
            return false
        }
        if shouldThrow { throw NSError(domain: "fake", code: 1) }
    }
}

/// Mutable state shared with the coordinator's @Sendable lookup closures.
nonisolated private final class SharedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func update(_ transform: (inout Value) -> Void) { lock.withLock { transform(&value) } }
}

/// Coordinator behavior against a recording fake index: incremental
/// upsert/delete decisions, bulk-change full refresh, reconciliation diffing,
/// gating, and the persisted-state lifecycle (state only records confirmed
/// writes; flag-off clears once).
final class SpotlightIndexCoordinatorTests: XCTestCase {

    private var fakeIndex: FakeIndex!
    private var defaults: UserDefaults!
    private var stateURL: URL!
    private var episodesBox: SharedBox<[String: SpotlightItemBuilder.EpisodeMetadata]>!
    private var enabledBox: SharedBox<Bool>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fakeIndex = FakeIndex()
        defaults = UserDefaults(suiteName: "SpotlightIndexCoordinatorTests-\(UUID().uuidString)")
        stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotlight-state-\(UUID().uuidString).json")
        episodesBox = SharedBox([:])
        enabledBox = SharedBox(true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: stateURL)
        fakeIndex = nil
        defaults = nil
        episodesBox = nil
        enabledBox = nil
        try super.tearDownWithError()
    }

    private func makeCoordinator() -> SpotlightIndexCoordinator {
        let episodes = episodesBox!
        let enabled = enabledBox!
        return SpotlightIndexCoordinator(
            index: fakeIndex,
            defaults: defaults,
            stateFileURL: stateURL,
            debounceSeconds: 600, // tests call flushPending() directly
            isEnabled: { enabled.get() },
            resolveEpisode: { uuid in episodes.get()[uuid] },
            downloadedEpisodes: { episodes.get().values.sorted { $0.uuid < $1.uuid } }
        )
    }

    private func setEpisode(_ metadata: SpotlightItemBuilder.EpisodeMetadata) {
        episodesBox.update { $0[metadata.uuid] = metadata }
    }

    private func removeEpisode(uuid: String) {
        episodesBox.update { $0[uuid] = nil }
    }

    private func setEnabled(_ value: Bool) {
        enabledBox.update { $0 = value }
    }

    // MARK: - Incremental updates

    func testDownloadedEpisodeIsIndexedAndDeparturesAreDeleted() async {
        let c = makeCoordinator()
        setEpisode(.init(uuid: "ep-1", title: "One"))

        c.episodeChanged(uuid: "ep-1")
        c.episodeChanged(uuid: "ep-gone")
        await c.flushPending()

        XCTAssertEqual(fakeIndex.calls, [
            .delete(["episode:ep-gone"]),
            .index(["episode:ep-1"])
        ])
    }

    func testDuplicateEventsCoalesce() async {
        let c = makeCoordinator()
        setEpisode(.init(uuid: "ep-1", title: "One"))

        c.episodeChanged(uuid: "ep-1")
        c.episodeChanged(uuid: "ep-1")
        c.episodeChanged(uuid: "ep-1")
        await c.flushPending()

        XCTAssertEqual(fakeIndex.calls, [.index(["episode:ep-1"])])
    }

    func testBulkChangeTriggersFullRebuild() async {
        let c = makeCoordinator()
        setEpisode(.init(uuid: "ep-1", title: "One"))
        setEpisode(.init(uuid: "ep-2", title: "Two"))

        c.episodeChanged(uuid: nil)
        await c.flushPending()

        XCTAssertEqual(fakeIndex.calls, [.index(["episode:ep-1", "episode:ep-2"])])
    }

    func testDisabledCoordinatorDoesNothingIncrementally() async {
        let c = makeCoordinator()
        setEnabled(false)
        setEpisode(.init(uuid: "ep-1", title: "One"))

        c.episodeChanged(uuid: "ep-1")
        await c.flushPending()

        XCTAssertTrue(fakeIndex.calls.isEmpty)
    }

    func testFailedBatchIsNotRecordedAsWritten() async {
        let c = makeCoordinator()
        setEpisode(.init(uuid: "ep-1", title: "One"))

        fakeIndex.setFailNext()
        c.episodeChanged(uuid: "ep-1")
        await c.flushPending()
        XCTAssertTrue(fakeIndex.calls.isEmpty, "the failed write never landed")

        // The next full rebuild retries it.
        await c.rebuildAll()
        XCTAssertEqual(fakeIndex.calls.last, .index(["episode:ep-1"]))
    }

    // MARK: - Reconciliation

    func testRebuildDeletesStaleIdentifiersFromPreviousRuns() async {
        let c = makeCoordinator()
        setEpisode(.init(uuid: "ep-1", title: "One"))
        setEpisode(.init(uuid: "ep-2", title: "Two"))
        c.episodeChanged(uuid: "ep-1")
        c.episodeChanged(uuid: "ep-2")
        await c.flushPending()

        // ep-2's download departs; a stale identifier remains in state.
        removeEpisode(uuid: "ep-2")
        await c.rebuildAll()

        XCTAssertEqual(fakeIndex.calls.suffix(2), [
            .delete(["episode:ep-2"]),
            .index(["episode:ep-1"])
        ])
    }

    func testReconcileIfDueThrottlesToInterval() async {
        let c = makeCoordinator()
        setEpisode(.init(uuid: "ep-1", title: "One"))

        await c.reconcileIfDue()
        let first = fakeIndex.calls.count
        XCTAssertGreaterThan(first, 0, "first reconcile runs (schema version unset)")

        await c.reconcileIfDue()
        XCTAssertEqual(fakeIndex.calls.count, first, "second reconcile within the interval is skipped")
    }

    func testDisabledReconcileClearsPreviouslyWrittenItemsOnce() async {
        let c = makeCoordinator()
        setEpisode(.init(uuid: "ep-1", title: "One"))
        c.episodeChanged(uuid: "ep-1")
        await c.flushPending()
        XCTAssertEqual(fakeIndex.calls, [.index(["episode:ep-1"])])

        setEnabled(false)
        await c.reconcileIfDue()
        XCTAssertEqual(fakeIndex.calls.last, .deleteAll(["episode", "highlight"]))

        let before = fakeIndex.calls.count
        await c.reconcileIfDue()
        XCTAssertEqual(fakeIndex.calls.count, before, "state is empty now: nothing to clear again")
    }

    func testDisabledReconcileWithNoStateDoesNothing() async {
        let c = makeCoordinator()
        setEnabled(false)
        await c.reconcileIfDue()
        XCTAssertTrue(fakeIndex.calls.isEmpty)
    }
}
