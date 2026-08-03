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

    // MARK: - Smart window (sentence-snapped reach-back, Highlights program S1)

    func testSmartExcerptReachesBackToSentenceStart() {
        // One long thought split over cues; the sentence before it ends with ".".
        let transcript = makeTranscript([
            (0, 8, "An earlier point that is finished. "),
            (8.2, 20, "Here begins the thought "),
            (20.3, 35, "that keeps going and going "),
            (35.2, 50, "until the listener finally taps. ")
        ])

        // Anchor 48: base window is [38, 53], but the sentence started at 8.2.
        let excerpt = HighlightExcerptBuilder.smartExcerpt(around: 48, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.startTime, 8.2, "should reach back to the cue after the terminal punctuation")
        XCTAssertEqual(excerpt?.text, "Here begins the thought that keeps going and going until the listener finally taps.")
    }

    func testSmartExcerptStopsAtSilenceBoundary() {
        // No punctuation anywhere (auto-STT style); a 3s gap marks the turn.
        let transcript = makeTranscript([
            (0, 10, "speaker one wrapping up "),
            (13, 25, "speaker two starts here "),
            (25.2, 40, "and continues to the tap ")
        ])

        let excerpt = HighlightExcerptBuilder.smartExcerpt(around: 38, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.startTime, 13, "the 3s gap should stop the reach-back")
    }

    func testSmartExcerptRespectsLeadingCap() {
        // Continuous unpunctuated speech: the 45s cap is the only brake.
        var pieces: [(start: TimeInterval, end: TimeInterval, text: String)] = []
        for i in 0..<12 {
            let start = TimeInterval(i) * 10
            pieces.append((start: start, end: start + 10, text: "chunk \(i) "))
        }
        let transcript = makeTranscript(pieces)

        // Anchor 115 → cues starting at ≥ 70 qualify (115 - 45); cue [70,80] is the earliest.
        let excerpt = HighlightExcerptBuilder.smartExcerpt(around: 115, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.startTime, 70, "reach-back should stop at maxLeadingReach")
    }

    func testSmartExcerptFinishesTheSentenceInFlight() {
        let transcript = makeTranscript([
            (0, 4, "Before. "),
            (48, 55, "The thought crosses "),
            (55.2, 62, "the anchor and ends here. "),
            (62.3, 70, "A new sentence after it. ")
        ])

        // Anchor 50: base window ends at 55, but the sentence runs to 62.
        let excerpt = HighlightExcerptBuilder.smartExcerpt(around: 50, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.endTime, 62, "should extend to the end of the sentence in flight")
        XCTAssertEqual(excerpt?.text, "The thought crosses the anchor and ends here.")
    }

    func testSmartExcerptReturnsNilWithoutIntersectingCues() {
        let transcript = makeTranscript([(100, 110, "Far away.")])

        XCTAssertNil(HighlightExcerptBuilder.smartExcerpt(around: 10, cues: transcript.cues, plainText: transcript.plainText))
    }

    // MARK: - Stored-window recovery (trim editor open path)

    func testRecoveredWindowMatchesMultiCueExcerpt() {
        let transcript = makeTranscript([
            (0, 5, "Before the window. "),
            (10, 15, "First stored piece. "),
            (15.2, 20, "Second stored piece. "),
            (25, 30, "After the window. ")
        ])

        let window = HighlightExcerptBuilder.recoveredWindow(
            excerpt: "First stored piece. Second stored piece.",
            endTime: 20,
            cues: transcript.cues,
            plainText: transcript.plainText
        )

        XCTAssertEqual(window, 10...20)
    }

    func testRecoveredWindowToleratesEndTimeDrift() {
        // Sync round-trips endTime through ms; sub-second drift must not break recovery.
        let transcript = makeTranscript([(10, 15, "Only piece.")])

        let window = HighlightExcerptBuilder.recoveredWindow(
            excerpt: "Only piece.",
            endTime: 15.4,
            cues: transcript.cues,
            plainText: transcript.plainText
        )

        XCTAssertEqual(window, 10...15)
    }

    func testRecoveredWindowSurvivesDenseWordLevelCues() {
        // Auto-STT cues can end within fractions of a second of each other:
        // several ends fall inside the drift tolerance, and only the excerpt's
        // suffix identifies the true last cue. Recovery must try candidates
        // nearest the stored endTime, not blindly take the last in tolerance.
        let transcript = makeTranscript([
            (10, 10.6, "One "),
            (10.6, 11.2, "two "),
            (11.2, 11.8, "three "),
            (11.8, 12.4, "four "),
            (12.4, 13.0, "five ")
        ])

        let window = HighlightExcerptBuilder.recoveredWindow(
            excerpt: "One two three",
            endTime: 11.8,
            cues: transcript.cues,
            plainText: transcript.plainText
        )

        XCTAssertEqual(window, 10...11.8)
    }

    func testRecoveredWindowFailsWhenTranscriptChanged() {
        let transcript = makeTranscript([(10, 15, "Completely different words now.")])

        XCTAssertNil(HighlightExcerptBuilder.recoveredWindow(
            excerpt: "The excerpt that once existed.",
            endTime: 15,
            cues: transcript.cues,
            plainText: transcript.plainText
        ), "an unreproducible window must fall back rather than guess")
    }

    // MARK: - Explicit range (trim editor save path)

    func testRangeExcerptSelectsIntersectingCues() {
        let transcript = makeTranscript([
            (0, 5, "One. "),
            (5.2, 10, "Two. "),
            (10.2, 15, "Three. ")
        ])

        let excerpt = HighlightExcerptBuilder.excerpt(in: 6...11, cues: transcript.cues, plainText: transcript.plainText)

        XCTAssertEqual(excerpt?.text, "Two. Three.")
        XCTAssertEqual(excerpt?.startTime, 5.2)
        XCTAssertEqual(excerpt?.endTime, 15)
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
