@testable import PocketCastsDataModel
@testable import PocketCastsUtils
import XCTest

/// Coverage for the salient-segment store (migration 88, ADR-0018).
final class SalientSegmentDataManagerTests: DataManagerTestCase {
    private func segment(rank: Int32, start: Double = 10, end: Double = 40,
                         status: SalientSuggestionStatus = .candidate) -> SalientSegmentRecord {
        var record = SalientSegmentRecord()
        record.rank = rank
        record.startTime = start
        record.endTime = end
        record.title = "Segment \(rank)"
        record.score = 10 - rank
        record.excerpt = "Excerpt \(rank)"
        record.status = status
        return record
    }

    func testReplaceGenerationRoundTripsAndMarksPendingTop() throws {
        try runWithBothImplementations { dataManager, impl in
            let saved = dataManager.salientSegments.replaceGeneration(
                episodeUuid: "ep-1", podcastUuid: "pod-1", transcriptSource: "generated",
                generatedAt: Date(timeIntervalSince1970: 1000),
                segments: [segment(rank: 0), segment(rank: 1), segment(rank: 2), segment(rank: 3)],
                markPendingTop: 3
            )
            XCTAssertTrue(saved, "\(impl): replaceGeneration should succeed")

            let generation = dataManager.salientSegments.generation(episodeUuid: "ep-1")
            XCTAssertEqual(generation?.segments.count, 4, "\(impl): all segments round-trip")
            XCTAssertEqual(generation?.meta.transcriptSource, "generated", "\(impl)")
            XCTAssertEqual(generation?.meta.outcome, SalientSegmentOutcome.segments.rawValue, "\(impl)")

            let pending = dataManager.salientSegments.pendingSuggestions()
            XCTAssertEqual(pending.map(\.rank), [0, 1, 2], "\(impl): only the top ranks surface for review")
        }
    }

    func testEmptyGenerationWritesDurableNoSegmentsSentinel() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.salientSegments.replaceGeneration(
                episodeUuid: "ep-2", podcastUuid: nil, transcriptSource: "",
                generatedAt: Date(), segments: []
            )

            XCTAssertTrue(dataManager.salientSegments.hasGeneration(episodeUuid: "ep-2"),
                          "\(impl): a noSegments verdict counts as attempted (no regeneration loop)")
            XCTAssertEqual(
                dataManager.salientSegments.generation(episodeUuid: "ep-2")?.meta.outcome,
                SalientSegmentOutcome.noSegments.rawValue, "\(impl)"
            )
        }
    }

    func testStatusTransitionsSurviveRegenerationOnlyViaReplace() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.salientSegments.replaceGeneration(
                episodeUuid: "ep-3", podcastUuid: nil, transcriptSource: "generated",
                generatedAt: Date(), segments: [segment(rank: 0)], markPendingTop: 1
            )

            dataManager.salientSegments.setStatus(.accepted, episodeUuid: "ep-3", rank: 0, bookmarkUuid: "bm-1")

            let stored = dataManager.salientSegments.generation(episodeUuid: "ep-3")?.segments.first
            XCTAssertEqual(stored?.status, .accepted, "\(impl)")
            XCTAssertEqual(stored?.bookmarkUuid, "bm-1", "\(impl)")
            XCTAssertTrue(dataManager.salientSegments.pendingSuggestions().isEmpty, "\(impl)")
        }
    }

    func testMarkTopCandidatesPendingSkipsResolvedRows() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.salientSegments.replaceGeneration(
                episodeUuid: "ep-4", podcastUuid: nil, transcriptSource: "generated",
                generatedAt: Date(),
                segments: [segment(rank: 0, status: .dismissed), segment(rank: 1), segment(rank: 2)]
            )

            dataManager.salientSegments.markTopCandidatesPending(episodeUuid: "ep-4", count: 2)

            let pending = dataManager.salientSegments.pendingSuggestions()
            XCTAssertEqual(pending.map(\.rank), [1, 2],
                           "\(impl): dismissed rows never resurface as pending")
        }
    }

    func testReplaceGenerationMarksPendingByRankNotArrayPosition() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.salientSegments.replaceGeneration(
                episodeUuid: "ep-rank", podcastUuid: nil, transcriptSource: "generated",
                generatedAt: Date(),
                segments: [segment(rank: 3), segment(rank: 0), segment(rank: 2), segment(rank: 1)],
                markPendingTop: 2
            )

            XCTAssertEqual(dataManager.salientSegments.pendingSuggestions().map(\.rank), [0, 1],
                           "\(impl): rank, not input order, defines the top suggestions")
        }
    }
}
