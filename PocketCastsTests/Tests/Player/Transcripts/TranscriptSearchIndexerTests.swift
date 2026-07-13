import Foundation
@testable import PocketCastsDataModel
@testable import podcasts
import XCTest

/// Pure-logic coverage for the library transcript search indexer's cue
/// extraction and merging (plans/AI UX Improvements.md Phase 4). Nothing here
/// touches the database or the network.
final class TranscriptSearchIndexerTests: XCTestCase {

    // MARK: - Merging

    func testShortCuesMergeUntilMinimumLength() throws {
        let model = makeModel(cueTexts: ["Hello there.", "How are you?", "This is more text to cross forty chars."],
                              timing: [(0, 2), (2, 5), (5, 9)])

        let segments = TranscriptSearchIndexer.indexableCues(from: model)

        XCTAssertEqual(segments.count, 1, "Short cues should merge into a single segment")
        let segment = try XCTUnwrap(segments.first)
        XCTAssertEqual(segment.index, 0)
        XCTAssertEqual(segment.text, "Hello there. How are you? This is more text to cross forty chars.")
        XCTAssertEqual(segment.startTime, 0, "Segment start should come from the first merged cue")
        XCTAssertEqual(segment.endTime, 9, "Segment end should come from the last merged cue")
    }

    func testLongCueBecomesItsOwnSegment() throws {
        let text = "A single cue that is comfortably longer than forty characters on its own."
        let model = makeModel(cueTexts: [text], timing: [(1.5, 7)])

        let segments = TranscriptSearchIndexer.indexableCues(from: model)

        XCTAssertEqual(segments.count, 1)
        let segment = try XCTUnwrap(segments.first)
        XCTAssertEqual(segment.text, text)
        XCTAssertEqual(segment.startTime, 1.5)
        XCTAssertEqual(segment.endTime, 7)
    }

    func testTrailingShortCueFlushesAsFinalSegment() {
        let long = "This opening cue easily exceeds the forty character segment minimum."
        let model = makeModel(cueTexts: [long, "Bye!"], timing: [(0, 5), (5, 6)])

        let segments = TranscriptSearchIndexer.indexableCues(from: model)

        XCTAssertEqual(segments.count, 2, "A leftover short tail should still be flushed as its own segment")
        XCTAssertEqual(segments.map(\.index), [0, 1], "Segment indexes should be ordinal")
        XCTAssertEqual(segments.last?.text, "Bye!")
        XCTAssertEqual(segments.last?.startTime, 5)
        XCTAssertEqual(segments.last?.endTime, 6)
    }

    func testCueTextIsTrimmedWhenMerged() {
        let model = makeModel(cueTexts: ["  Hello  ", "\nworld and some more text over the minimum length\n"])

        let segments = TranscriptSearchIndexer.indexableCues(from: model)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "Hello world and some more text over the minimum length")
    }

    // MARK: - Skipping

    func testWhitespaceOnlyCuesAreSkipped() {
        let model = makeModel(cueTexts: ["   ", "\n\n", "Actual spoken words that stretch beyond the minimum."])

        let segments = TranscriptSearchIndexer.indexableCues(from: model)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "Actual spoken words that stretch beyond the minimum.")
    }

    func testCuesWithInvalidRangesAreSkipped() {
        let text = "Short text"
        let cues = [
            // Range entirely out of the text's UTF-16 bounds
            TranscriptCue(startTime: 0, endTime: 1, characterRange: NSRange(location: 100, length: 5)),
            // Range straddling the end of the text
            TranscriptCue(startTime: 1, endTime: 2, characterRange: NSRange(location: 5, length: 50)),
            // Empty range
            TranscriptCue(startTime: 2, endTime: 3, characterRange: NSRange(location: 0, length: 0))
        ]
        let model = TranscriptModel(attributedText: AttributedString(text), cues: cues, type: "vtt", hasJavascript: false)

        XCTAssertTrue(TranscriptSearchIndexer.indexableCues(from: model).isEmpty)
    }

    func testModelWithoutCuesYieldsNoSegments() {
        // text/html transcripts parse with no cue timing at all
        let model = TranscriptModel(attributedText: AttributedString("A cue-less transcript body"), cues: [], type: "text/html", hasJavascript: false)

        XCTAssertTrue(TranscriptSearchIndexer.indexableCues(from: model).isEmpty)
    }

    // MARK: - End to end through the VTT parser

    func testIndexableCuesFromParsedVTT() throws {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        Welcome back to the show everyone.

        00:00:02.000 --> 00:00:04.500
        Today we are talking about search.

        00:00:04.500 --> 00:00:06.000
        Enjoy!
        """
        let model = try XCTUnwrap(TranscriptModel.makeModel(from: vtt, format: .vtt))

        let segments = TranscriptSearchIndexer.indexableCues(from: model)

        XCTAssertFalse(segments.isEmpty)
        XCTAssertEqual(segments.map(\.index), Array(0 ..< segments.count), "Segment indexes should be ordinal")
        for segment in segments {
            XCTAssertFalse(segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertLessThanOrEqual(segment.startTime, try XCTUnwrap(segment.endTime))
        }
        XCTAssertEqual(segments.first?.startTime, 0)
        XCTAssertEqual(segments.last?.endTime, 6)
        // The searchable text round-trips from the parsed transcript
        XCTAssertTrue(segments.contains { $0.text.contains("talking about search") })
    }

    // MARK: - Helpers

    /// Builds a TranscriptModel whose text is the concatenation of `cueTexts`,
    /// with each cue's characterRange pointing at its own slice (UTF-16 offsets,
    /// exactly like the production parser produces).
    private func makeModel(cueTexts: [String], timing: [(Double, Double)]? = nil) -> TranscriptModel {
        var fullText = ""
        var cues = [TranscriptCue]()
        for (index, text) in cueTexts.enumerated() {
            let location = (fullText as NSString).length
            fullText += text
            let times = timing?[index] ?? (Double(index), Double(index) + 1)
            cues.append(TranscriptCue(startTime: times.0,
                                      endTime: times.1,
                                      characterRange: NSRange(location: location, length: (text as NSString).length)))
        }
        return TranscriptModel(attributedText: AttributedString(fullText), cues: cues, type: "vtt", hasJavascript: false)
    }
}
