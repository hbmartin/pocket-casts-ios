import XCTest

@testable import podcasts

/// Pins `SalientSegmentGenerator.validated` (Highlights S8, ADR-0018): cue
/// snapping, length bounds, overlap merging, tail clearance, rank assignment.
final class SalientSegmentGeneratorTests: XCTestCase {
    /// Cues every 10s across a 600s episode.
    private var cues: [TimedCueText] {
        stride(from: 0.0, to: 600.0, by: 10.0).map { TimedCueText(startTime: $0, text: "cue at \(Int($0)) ") }
    }

    private func item(title: String = "Segment", start: Int, end: Int, importance: Int = 5) -> GeneratedSalientSegmentItem {
        GeneratedSalientSegmentItem(title: title, startSeconds: start, endSeconds: end, importance: importance)
    }

    func testSnapsToCueStartsAndKeepsChronologicalOrderWithRanks() {
        let segments = SalientSegmentGenerator.validated([
            item(title: "Second", start: 203, end: 262, importance: 4),
            item(title: "First", start: 48, end: 122, importance: 9)
        ], cues: cues, duration: 600)

        XCTAssertEqual(segments.map(\.title), ["First", "Second"], "output is chronological")
        XCTAssertEqual(segments.map(\.rank), [0, 1], "rank carries salience order")
        XCTAssertEqual(segments[0].startTime, 50, "start snaps to the nearest cue")
        XCTAssertEqual(segments[0].endTime, 120, "end snaps to a near cue start")
    }

    func testDropsUnsnappableAndTooShortSegments() {
        let farCues = [TimedCueText(startTime: 0, text: "a"), TimedCueText(startTime: 500, text: "b")]
            + (0..<10).map { TimedCueText(startTime: 100 + Double($0), text: "c") }

        let segments = SalientSegmentGenerator.validated([
            item(start: 300, end: 380),          // >30s from any cue start
            item(start: 100, end: 110)           // snapped length < 20s
        ], cues: farCues, duration: 600)

        XCTAssertTrue(segments.isEmpty)
    }

    func testMergesOverlappingCandidatesKeepingBestScore() {
        let segments = SalientSegmentGenerator.validated([
            item(title: "One", start: 100, end: 160, importance: 3),
            item(title: "Two", start: 150, end: 220, importance: 8)
        ], cues: cues, duration: 600)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].title, "One", "earlier title wins the merge")
        XCTAssertEqual(segments[0].score, 8, "best score survives the merge")
        XCTAssertEqual(segments[0].startTime, 100)
        XCTAssertEqual(segments[0].endTime, 220)
    }

    func testFinalSegmentClampsClearOfEpisodeEnd() {
        let segments = SalientSegmentGenerator.validated([
            item(start: 540, end: 600)
        ], cues: cues, duration: 600)

        XCTAssertEqual(segments.count, 1)
        XCTAssertLessThanOrEqual(segments[0].endTime, 600 - SalientSegmentGenerator.endClearance)
    }

    func testCapsSegmentCountByImportance() {
        let items = (0..<20).map { index in
            item(title: "S\(index)", start: index * 30, end: index * 30 + 25, importance: (index % 10) + 1)
        }

        let segments = SalientSegmentGenerator.validated(items, cues: cues, duration: 600)

        XCTAssertLessThanOrEqual(segments.count, SalientSegmentGenerator.maximumSegments)
        XCTAssertTrue(segments.contains { $0.rank == 0 }, "the top rank always survives the cap")
    }

    func testExcerptCollectsCueTextInsideTheWindow() {
        let segments = SalientSegmentGenerator.validated([
            item(start: 100, end: 130)
        ], cues: cues, duration: 600)

        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].excerpt.contains("cue at 100"))
        XCTAssertTrue(segments[0].excerpt.contains("cue at 120"))
        XCTAssertFalse(segments[0].excerpt.contains("cue at 130"), "the end boundary is exclusive")
    }
}
