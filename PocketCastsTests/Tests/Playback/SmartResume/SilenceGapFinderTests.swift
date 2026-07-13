import XCTest
@testable import podcasts

/// Exercises the pure snap algorithm with synthetic dB arrays (same style as
/// `TrimSilenceDetectorTests`). Speech sits at -20dB, silence at -60dB, and the
/// window starts 2.5s before the 100s target unless a test says otherwise.
final class SilenceGapFinderTests: XCTestCase {
    private let speech: Float = -20
    private let quiet: Float = -60
    private let windowStart: TimeInterval = 97.5
    private let target: TimeInterval = 100

    private func levels(count: Int, quietRuns: [ClosedRange<Int>]) -> [Float] {
        var levels = [Float](repeating: speech, count: count)
        for run in quietRuns {
            for index in run {
                levels[index] = quiet
            }
        }
        return levels
    }

    private func snap(_ levelsDB: [Float], hop: TimeInterval = 0.05) -> TimeInterval? {
        SilenceGapFinder.snapTime(levelsDB: levelsDB, windowStart: windowStart, hopDuration: hop, target: target)
    }

    // MARK: - Gap detection

    func testSnapsToGapBeforeTarget() throws {
        // a 0.4s gap at 99.0 with speech resuming at 99.4: snap lands at onset - 0.15
        let levelsDB = levels(count: 61, quietRuns: [30 ... 37])

        let snapped = try XCTUnwrap(snap(levelsDB))
        XCTAssertEqual(snapped, 99.25, accuracy: 0.0001)
    }

    func testGapShorterThanMinimumIsIgnored() {
        // isolated 2-hop dips establish the dynamic range but every run is under
        // the 3-hop (150ms) minimum, including the "gap" at index 40
        let levelsDB = levels(count: 61, quietRuns: [5 ... 6, 12 ... 13, 19 ... 20, 40 ... 41])

        XCTAssertNil(snap(levelsDB))
    }

    func testMinimumLengthGapIsAccepted() throws {
        // the same background, but the gap now spans exactly 3 hops (150ms)
        let levelsDB = levels(count: 61, quietRuns: [5 ... 6, 12 ... 13, 19 ... 20, 40 ... 42])

        let snapped = try XCTUnwrap(snap(levelsDB))
        XCTAssertEqual(snapped, 99.5, accuracy: 0.001)
    }

    // MARK: - Music guard

    func testLowDynamicRangeReturnsNil() {
        // trimmable-length dips of only 8dB below the base level: music, not speech
        var levelsDB = [Float](repeating: -30, count: 61)
        for index in Array(10 ... 14) + Array(30 ... 34) {
            levelsDB[index] = -38
        }

        XCTAssertNil(snap(levelsDB))
    }

    // MARK: - Candidate choice

    func testPicksCandidateNearestTarget() throws {
        // gaps snapping to 97.95 and 99.85: the one 0.15s from the target wins
        let levelsDB = levels(count: 61, quietRuns: [4 ... 11, 42 ... 49])

        let snapped = try XCTUnwrap(snap(levelsDB))
        XCTAssertEqual(snapped, 99.85, accuracy: 0.0001)
    }

    func testEqualDistanceTieBreaksEarlier() {
        // a 1/16s hop makes both snaps exact: 99.5 and 100.5 are each 0.5s from
        // the target, so the earlier one must win (and 100.5 shows the +0.5s
        // boundary is inclusive, or the tie couldn't happen)
        let levelsDB = levels(count: 70, quietRuns: [3 ... 3, 6 ... 6, 9 ... 9, 12 ... 12, 32 ... 33, 48 ... 49])

        XCTAssertEqual(snap(levelsDB, hop: 0.0625), 99.5)
    }

    // MARK: - Window boundary

    func testCandidateOnAfterBoundaryIsAccepted() {
        // gap start at exactly target + 0.5s: still a candidate
        let levelsDB = levels(count: 70, quietRuns: [3 ... 3, 6 ... 6, 9 ... 9, 12 ... 12, 15 ... 15, 18 ... 18, 48 ... 49])

        XCTAssertEqual(snap(levelsDB, hop: 0.0625), 100.5)
    }

    func testCandidateBeyondAfterBoundaryIsRejected() {
        // one hop later (100.5625) falls outside [target - 2.5, target + 0.5]
        let levelsDB = levels(count: 70, quietRuns: [3 ... 3, 6 ... 6, 9 ... 9, 12 ... 12, 15 ... 15, 18 ... 18, 49 ... 50])

        XCTAssertNil(snap(levelsDB, hop: 0.0625))
    }

    // MARK: - Degenerate input

    func testGapReachingWindowEndIsDiscarded() {
        // silence runs to the end of the window with no speech onset after it
        let levelsDB = levels(count: 61, quietRuns: [41 ... 60])

        XCTAssertNil(snap(levelsDB))
    }

    func testEmptyOrInvalidInputReturnsNil() {
        XCTAssertNil(snap([]))
        XCTAssertNil(snap(levels(count: 61, quietRuns: [30 ... 37]), hop: 0))
    }
}
