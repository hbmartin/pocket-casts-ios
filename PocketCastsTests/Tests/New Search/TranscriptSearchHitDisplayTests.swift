import Foundation
@testable import PocketCastsDataModel
@testable import podcasts
import XCTest

/// Coverage for the snippet highlight-marker parser behind the library
/// transcript search result rows (plans/AI UX Improvements.md Phase 4).
final class TranscriptSearchHitDisplayTests: XCTestCase {
    private typealias Run = TranscriptSearchHitDisplay.Run

    func testRunsSplitHighlightMarkersIntoStyledRuns() {
        let snippet = "…what <b>search</b> looks like when <b>transcripts</b> join in…"

        let runs = TranscriptSearchHitDisplay.runs(from: snippet)

        XCTAssertEqual(runs, [
            Run(text: "…what ", isHighlighted: false),
            Run(text: "search", isHighlighted: true),
            Run(text: " looks like when ", isHighlighted: false),
            Run(text: "transcripts", isHighlighted: true),
            Run(text: " join in…", isHighlighted: false)
        ])
    }

    func testRunsWithoutMarkersAreASinglePlainRun() {
        XCTAssertEqual(TranscriptSearchHitDisplay.runs(from: "no matches here"),
                       [Run(text: "no matches here", isHighlighted: false)])
    }

    func testRunsHandleUnterminatedStartMarker() {
        let runs = TranscriptSearchHitDisplay.runs(from: "broken <b>tail without end")

        XCTAssertEqual(runs, [Run(text: "broken tail without end", isHighlighted: false)],
                       "An unterminated marker should degrade to plain text with markers stripped")
    }

    func testRunsHandleEmptyAndMarkerOnlyInput() {
        XCTAssertTrue(TranscriptSearchHitDisplay.runs(from: "").isEmpty)
        XCTAssertEqual(TranscriptSearchHitDisplay.runs(from: "<b></b>"), [])
    }

    func testRunsConcatenateBackToSnippetText() {
        let snippet = "a <b>b</b> c <b>d</b>"
        let runs = TranscriptSearchHitDisplay.runs(from: snippet)

        XCTAssertEqual(runs.map(\.text).joined(), "a b c d")
    }
}
