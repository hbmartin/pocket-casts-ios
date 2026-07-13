import XCTest

@testable import podcasts

/// Pure logic of the Catch Me Up generator: tail-weighted digest selection,
/// output validation and the eligibility window.
final class CatchMeUpGeneratorTests: XCTestCase {
    // MARK: - Tail digest

    func testTailDigestKeepsTheMostRecentCuesWithinBudget() {
        let cues = (0 ..< 100).map { TimedCueText(startTime: TimeInterval($0 * 10), text: "cue number \($0) with some words") }

        let digest = CatchMeUpGenerator.tailDigest(from: cues, characterBudget: 200)

        XCTAssertTrue(digest.hasSuffix("cue number 99 with some words"), "The most recent cue must survive")
        XCTAssertFalse(digest.contains("cue number 0 "), "The oldest cues are dropped first")

        // Output stays in listening order despite tail-first selection.
        let times = digest.split(separator: "\n").compactMap { line -> Int? in
            guard let end = line.firstIndex(of: "]") else { return nil }
            return Int(line[line.index(after: line.startIndex) ..< end])
        }
        XCTAssertEqual(times, times.sorted())
    }

    func testTailDigestCapsRunawayCues() {
        let cues = [TimedCueText(startTime: 5, text: String(repeating: "a", count: 5000))]

        let digest = CatchMeUpGenerator.tailDigest(from: cues, characterBudget: 12_000, cueCharacterCap: 100)

        XCTAssertLessThan(digest.count, 120)
        XCTAssertTrue(digest.hasPrefix("[5] "))
    }

    // MARK: - Validation

    func testValidatedTrimsAndCaps() {
        let raw = GeneratedCatchUp(recap: "  A recap.  ", keyPoints: [" one ", "", "two", "three", "four"])

        let summary = CatchMeUpGenerator.validated(raw)

        XCTAssertEqual(summary?.recap, "A recap.")
        XCTAssertEqual(summary?.keyPoints, ["one", "two", "three"], "Empty points dropped, capped at 3")
    }

    func testValidatedRejectsEmptyRecap() {
        XCTAssertNil(CatchMeUpGenerator.validated(GeneratedCatchUp(recap: "   ", keyPoints: ["point"])))
    }

    // MARK: - Eligibility

    func testEligibilityWindow() {
        XCTAssertFalse(CatchMeUpGenerator.isEligible(playedUpTo: 60, duration: 3600), "Too early to need a recap")
        XCTAssertTrue(CatchMeUpGenerator.isEligible(playedUpTo: 600, duration: 3600))
        XCTAssertFalse(CatchMeUpGenerator.isEligible(playedUpTo: 3400, duration: 3600), "Nearly finished")
        XCTAssertFalse(CatchMeUpGenerator.isEligible(playedUpTo: 600, duration: 0), "Unknown duration fails closed")
    }
}
