import PocketCastsDataModel
import XCTest

@testable import podcasts

final class TranscriptSearchFusionTests: XCTestCase {

    private func ftsHit(_ episode: String, segment: Int, source: PocketCastsDataModel.TranscriptSource = .generated, snippet: String = "<b>match</b> text") -> TranscriptSearchHit {
        TranscriptSearchHit(
            location: .init(
                episodeUuid: episode,
                podcastUuid: "pod-1",
                segmentIndex: segment,
                startTime: Double(segment) * 10,
                endTime: nil,
                speaker: nil,
                source: source
            ),
            snippet: snippet
        )
    }

    private func semanticHit(_ episode: String, range: ClosedRange<Int>, source: PocketCastsDataModel.TranscriptSource = .generated, score: Float = 0.8) -> SemanticTranscriptHit {
        semanticHit(episode, start: range.lowerBound, end: range.upperBound, source: source, score: score)
    }

    private func semanticHit(_ episode: String, start: Int, end: Int, source: PocketCastsDataModel.TranscriptSource = .generated, score: Float = 0.8) -> SemanticTranscriptHit {
        SemanticTranscriptHit(episodeUuid: episode, podcastUuid: "pod-1", source: source,
                              startSegmentIndex: start, endSegmentIndex: end,
                              startTime: Double(start) * 10, endTime: nil,
                              textPreview: "window preview", score: score)
    }

    // MARK: - RRF

    func testTopExactAndSemanticRanksFollowRRF() {
        let fused = TranscriptSearchFusion.fused(
            ftsHits: [ftsHit("ep-a", segment: 0), ftsHit("ep-b", segment: 0)],
            semanticHits: [semanticHit("ep-c", range: 0 ... 3)]
        )

        XCTAssertEqual(fused.count, 3)
        // rank-1 exact (1/61) beats rank-1 semantic? They tie: 1/(60+1) each.
        // Order among equals is stable; the important invariant is rank-2 exact
        // (1/62) sorts below both rank-1 contributions.
        XCTAssertEqual(fused[0].score, 1.0 / 61, accuracy: 0.0001)
        XCTAssertTrue(fused.map(\.score).isSorted(descending: true))
    }

    func testOverlappingSemanticHitCollapsesIntoExactHit() {
        // The semantic window [0...3] covers the FTS hit's segment 2.
        let fused = TranscriptSearchFusion.fused(
            ftsHits: [ftsHit("ep-a", segment: 2, snippet: "<b>real</b> snippet")],
            semanticHits: [semanticHit("ep-a", range: 0 ... 3)]
        )

        XCTAssertEqual(fused.count, 1, "no duplicate row for the same moment")
        XCTAssertEqual(fused[0].matchType, .both)
        XCTAssertEqual(fused[0].snippet, "<b>real</b> snippet", "the FTS hit keeps its highlighted snippet")
        XCTAssertEqual(fused[0].score, 1.0 / 61 + 1.0 / 61, accuracy: 0.0001, "contributions sum")
    }

    func testNonOverlappingSourcesStaySeparate() {
        // Same episode + covering range, but different corpus source: no collapse.
        let fused = TranscriptSearchFusion.fused(
            ftsHits: [ftsHit("ep-a", segment: 2, source: .provided)],
            semanticHits: [semanticHit("ep-a", range: 0 ... 3, source: .generated)]
        )
        XCTAssertEqual(fused.count, 2)
    }

    func testPureSemanticHitCarriesPreviewAsSnippet() {
        let fused = TranscriptSearchFusion.fused(ftsHits: [], semanticHits: [semanticHit("ep-a", range: 4 ... 6)])
        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused[0].matchType, .semantic)
        XCTAssertEqual(fused[0].snippet, "window preview")
        XCTAssertEqual(fused[0].segmentIndex, 4, "seek lands on the window's first segment")
    }

    func testInvertedSemanticBoundsDoNotTrapOrOverlapExactHit() {
        let fused = TranscriptSearchFusion.fused(
            ftsHits: [ftsHit("ep-a", segment: 4)],
            semanticHits: [semanticHit("ep-a", start: 6, end: 2)]
        )

        XCTAssertEqual(fused.count, 2, "corrupt inverted bounds must not collapse into an exact hit")
        XCTAssertEqual(Set(fused.map(\.matchType)), [.exact, .semantic])
    }

    // MARK: - Recency boost

    func testRecencyBoostIsBoundedAndReorders() {
        var fused = TranscriptSearchFusion.fused(
            ftsHits: [ftsHit("ep-old", segment: 0), ftsHit("ep-fresh", segment: 0)],
            semanticHits: []
        )
        XCTAssertEqual(fused[0].episodeUuid, "ep-old", "rank order before boosting")

        fused = TranscriptSearchFusion.recencyBoosted(fused) { episodeUuid in
            episodeUuid == "ep-fresh" ? 0 : 400
        }

        XCTAssertEqual(fused[0].episodeUuid, "ep-fresh", "a just-played episode overtakes a barely-better stale hit")
        // Max boost is +25%: a fresh rank-2 (1/62 × 1.25) beats rank-1 (1/61)
        // only because they were nearly tied.
        let maxBoost = (1.0 / 62) * (1 + TranscriptSearchFusion.recencyBoostWeight)
        XCTAssertEqual(fused[0].score, maxBoost, accuracy: 0.0001)
    }

    func testMissingAgeMeansNoBoost() {
        let fused = TranscriptSearchFusion.fused(ftsHits: [ftsHit("ep-a", segment: 0)], semanticHits: [])
        let boosted = TranscriptSearchFusion.recencyBoosted(fused) { _ in nil }
        XCTAssertEqual(boosted[0].score, fused[0].score)
    }
}

private extension [Double] {
    func isSorted(descending: Bool) -> Bool {
        zip(self, dropFirst()).allSatisfy { descending ? $0 >= $1 : $0 <= $1 }
    }
}
