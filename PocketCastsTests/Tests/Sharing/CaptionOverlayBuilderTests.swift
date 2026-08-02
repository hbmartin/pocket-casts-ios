import XCTest

@testable import podcasts

/// Pins the cue → caption math (Highlights S13).
final class CaptionOverlayBuilderTests: XCTestCase {
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

    func testCaptionsShiftToClipTimeAndClamp() {
        let transcript = makeTranscript([
            (95, 102, "Crosses the clip start. "),
            (105, 110, "Fully inside. "),
            (118, 130, "Crosses the clip end. "),
            (200, 210, "Far outside. ")
        ])

        let captions = CaptionOverlayBuilder.captions(
            cues: transcript.cues, plainText: transcript.plainText,
            clipStart: 100, clipDuration: 20
        )

        XCTAssertEqual(captions.count, 3)
        XCTAssertEqual(captions[0].start, 0, "a cue crossing the start clamps to 0")
        XCTAssertEqual(captions[0].text, "Crosses the clip start.")
        XCTAssertEqual(captions[1].start, 5)
        XCTAssertEqual(captions[2].start + captions[2].duration, 20,
                       "a cue crossing the end clamps to the clip duration")
    }

    func testShortCuesExtendToTheReadabilityFloor() {
        let transcript = makeTranscript([
            (10, 10.4, "Blip. "),
            (15, 18, "Later. ")
        ])

        let captions = CaptionOverlayBuilder.captions(
            cues: transcript.cues, plainText: transcript.plainText,
            clipStart: 10, clipDuration: 10
        )

        XCTAssertEqual(captions[0].duration, CaptionOverlayBuilder.minimumDisplay,
                       "sub-second cues stay readable")
    }

    func testExtensionNeverOverlapsTheNextCaption() {
        let transcript = makeTranscript([
            (10, 10.3, "First. "),
            (10.8, 13, "Second. ")
        ])

        let captions = CaptionOverlayBuilder.captions(
            cues: transcript.cues, plainText: transcript.plainText,
            clipStart: 10, clipDuration: 10
        )

        XCTAssertEqual(captions[0].start + captions[0].duration, captions[1].start,
                       accuracy: 0.001, "the floor yields to the next caption's start")
    }

    func testNoTranscriptOverlapMeansNoCaptions() {
        let transcript = makeTranscript([(0, 5, "Way before.")])

        XCTAssertTrue(CaptionOverlayBuilder.captions(
            cues: transcript.cues, plainText: transcript.plainText,
            clipStart: 100, clipDuration: 20
        ).isEmpty)
    }
}
