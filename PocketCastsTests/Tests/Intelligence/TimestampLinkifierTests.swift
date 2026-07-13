import Foundation
import XCTest

@testable import podcasts

@MainActor
final class TimestampLinkifierTests: XCTestCase {

    // MARK: - seconds(from:)

    func testParsesMinutesSeconds() {
        XCTAssertEqual(TimestampLinkifier.seconds(from: "3:45"), 225)
        XCTAssertEqual(TimestampLinkifier.seconds(from: "0:05"), 5)
        XCTAssertEqual(TimestampLinkifier.seconds(from: "12:04"), 724)
    }

    func testParsesHoursMinutesSeconds() {
        XCTAssertEqual(TimestampLinkifier.seconds(from: "1:02:33"), 3753)
        XCTAssertEqual(TimestampLinkifier.seconds(from: "10:00:00"), 36000)
    }

    func testMinutesBeyond59AreValidInTwoComponentForm() {
        // "90:00" reads naturally as ninety minutes.
        XCTAssertEqual(TimestampLinkifier.seconds(from: "90:00"), 5400)
    }

    func testRejectsInvalidClockValues() {
        XCTAssertNil(TimestampLinkifier.seconds(from: "12:75"), "seconds must be under 60")
        XCTAssertNil(TimestampLinkifier.seconds(from: "1:75:10"), "minutes must be under 60 when hours are present")
        XCTAssertNil(TimestampLinkifier.seconds(from: "1:02:75"))
        XCTAssertNil(TimestampLinkifier.seconds(from: "345"))
        XCTAssertNil(TimestampLinkifier.seconds(from: ""))
        XCTAssertNil(TimestampLinkifier.seconds(from: "a:bc"))
    }

    // MARK: - matches(in:)

    func testFindsAllTimestampMentionsInOrder() {
        let text = "The intro starts at 2:30, the interview at 45:10, and the wrap-up at 1:02:33."
        let matches = TimestampLinkifier.matches(in: text)

        XCTAssertEqual(matches.map(\.text), ["2:30", "45:10", "1:02:33"])
        XCTAssertEqual(matches.map(\.seconds), [150, 2710, 3753])
    }

    func testMatchRangesSliceTheSourceText() {
        let text = "Jump to 12:04 for details."
        let matches = TimestampLinkifier.matches(in: text)

        XCTAssertEqual(matches.count, 1)
        let sliced = (text as NSString).substring(with: matches[0].nsRange)
        XCTAssertEqual(sliced, "12:04")
    }

    func testInvalidClockTimesAreNotLinked() {
        XCTAssertTrue(TimestampLinkifier.matches(in: "score was 12:75 overall").isEmpty)
    }

    func testDigitRunsWithoutWordBoundaryAreNotLinked() {
        XCTAssertTrue(TimestampLinkifier.matches(in: "code 12:345 here").isEmpty)
    }

    func testNoMatchesInPlainText() {
        XCTAssertTrue(TimestampLinkifier.matches(in: "No timestamps to see here.").isEmpty)
    }

    // MARK: - linkified(_:urlBuilder:)

    func testLinkifiedAttachesURLsToTimestampRuns() throws {
        let text = "Start 2:30 middle 45:10 end."
        let attributed = TimestampLinkifier.linkified(text) { seconds in
            URL(string: "test://seek?t=\(Int(seconds))")
        }

        // Round-trip content is unchanged.
        XCTAssertEqual(String(attributed.characters), text)

        let linkRuns = attributed.runs.compactMap { run -> (String, URL)? in
            guard let url = run.link else { return nil }
            return (String(attributed.characters[run.range]), url)
        }
        XCTAssertEqual(linkRuns.count, 2)
        XCTAssertEqual(linkRuns[0].0, "2:30")
        XCTAssertEqual(linkRuns[0].1.absoluteString, "test://seek?t=150")
        XCTAssertEqual(linkRuns[1].0, "45:10")
        XCTAssertEqual(linkRuns[1].1.absoluteString, "test://seek?t=2710")
    }

    func testLinkifiedWithNilURLLeavesTextPlain() {
        let attributed = TimestampLinkifier.linkified("At 2:30 sharp.") { _ in nil }
        XCTAssertEqual(String(attributed.characters), "At 2:30 sharp.")
        XCTAssertTrue(attributed.runs.allSatisfy { $0.link == nil })
    }

    func testLinkifiedPlainTextPassesThrough() {
        let attributed = TimestampLinkifier.linkified("Nothing here.") { _ in nil }
        XCTAssertEqual(String(attributed.characters), "Nothing here.")
    }

    // MARK: - Seek URL round-trip (view model contract)

    func testSeekURLRoundTrip() throws {
        let url = try XCTUnwrap(EpisodeSummaryViewModel.seekURL(for: 2710))
        XCTAssertEqual(EpisodeSummaryViewModel.seekSeconds(from: url), 2710)
    }

    func testSeekSecondsRejectsForeignURLs() throws {
        let foreign = try XCTUnwrap(URL(string: "https://example.com/?t=10"))
        XCTAssertNil(EpisodeSummaryViewModel.seekSeconds(from: foreign))
    }
}
