import XCTest
@testable import podcasts

/// Pure cue-window logic behind smart-highlight enrichment
/// (plans/AI UX Improvements.md Phase 3).
final class HighlightExcerptBuilderTests: XCTestCase {
    /// Builds a synthetic transcript: each piece becomes a cue whose
    /// `characterRange` indexes into the concatenated plain text.
    private func makeTranscript(_ pieces: [(start: TimeInterval, end: TimeInterval, text: String)]) -> (cues: [TranscriptCue], plainText: String) {
        var cues: [TranscriptCue] = []
        var plainText = ""
        for piece in pieces {
            let location = (plainText as NSString).length
            plainText += piece.text
            cues.append(TranscriptCue(
                startTime: piece.start,
                endTime: piece.end,
                characterRange: NSRange(location: location, length: (piece.text as NSString).length)
            ))
        }
        return (cues, plainText)
    }

    func testSelectsOnlyCuesIntersectingTheWindow() {
        let transcript = makeTranscript([
            (0, 4, "Way before the window. "),
            (48, 52, "Just inside on the left. "),
            (55, 58, "Right at the anchor. "),
            (62, 64, "Inside on the right. "),
            (70, 75, "Way after the window. ")
        ])

        // Anchor 58 → window [48, 63].
        let excerpt = HighlightExcerptBuilder.excerpt(around: 58, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.text, "Just inside on the left. Right at the anchor. Inside on the right.")
        XCTAssertEqual(excerpt?.startTime, 48)
        XCTAssertEqual(excerpt?.endTime, 64)
    }

    func testCueOverlappingWindowEdgeIsIncluded() {
        let transcript = makeTranscript([
            (0, 12, "Starts long before but overlaps the window start."),
            (30, 40, "Far beyond.")
        ])

        // Anchor 20 → window [10, 25]: the first cue's tail crosses into it.
        let excerpt = HighlightExcerptBuilder.excerpt(around: 20, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.text, "Starts long before but overlaps the window start.")
    }

    func testWindowClampsAtZeroForEarlyBookmarks() {
        let transcript = makeTranscript([
            (0, 3, "Opening line."),
            (100, 104, "Much later.")
        ])

        let excerpt = HighlightExcerptBuilder.excerpt(around: 2, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.text, "Opening line.")
        XCTAssertEqual(excerpt?.startTime, 0)
    }

    func testReturnsNilWhenNoCueIntersectsWindow() {
        let transcript = makeTranscript([
            (0, 4, "Beginning."),
            (500, 510, "End.")
        ])

        XCTAssertNil(HighlightExcerptBuilder.excerpt(around: 100, cues: transcript.cues, plainText: transcript.plainText))
    }

    func testReturnsNilForEmptyCues() {
        XCTAssertNil(HighlightExcerptBuilder.excerpt(around: 10, cues: [], plainText: "text"))
    }

    func testNormalizesWhitespaceAndNewlinesInsideCues() {
        let transcript = makeTranscript([
            (10, 12, "Line one\nwith  a break. "),
            (12, 14, "  Line two.  ")
        ])

        let excerpt = HighlightExcerptBuilder.excerpt(around: 12, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.text, "Line one with a break. Line two.")
    }

    func testCueWithOutOfBoundsRangeIsSkipped() {
        let cues = [
            TranscriptCue(startTime: 10, endTime: 12, characterRange: NSRange(location: 0, length: 5)),
            TranscriptCue(startTime: 12, endTime: 14, characterRange: NSRange(location: 100, length: 50))
        ]

        let excerpt = HighlightExcerptBuilder.excerpt(around: 12, cues: cues, plainText: "Hello world")

        XCTAssertEqual(excerpt?.text, "Hello")
    }

    func testWhitespaceOnlyWindowReturnsNil() {
        let transcript = makeTranscript([
            (10, 12, "   \n  ")
        ])

        XCTAssertNil(HighlightExcerptBuilder.excerpt(around: 11, cues: transcript.cues, plainText: transcript.plainText))
    }
}
