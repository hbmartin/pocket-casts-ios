import XCTest

@testable import podcasts

/// Deterministic transcript fixture built the same way `TranscriptModel.makeModel`
/// assembles its attributed text (speaker header runs + per-cue ranges), without
/// depending on the subtitle parser or compose filters.
enum TranscriptReaderFixture {

    static func makeModel() -> TranscriptModel {
        let result = NSMutableAttributedString()
        var cues = [TranscriptCue]()

        func addSpeaker(_ name: String) {
            result.append(NSAttributedString(string: "\n\(name)\n", attributes: [.transcriptSpeaker: name]))
        }

        func addCue(_ text: String, start: Double, end: Double) {
            let attributed = NSAttributedString(string: text)
            let range = NSRange(location: result.length, length: attributed.length)
            result.append(attributed)
            cues.append(TranscriptCue(startTime: start, endTime: end, characterRange: range))
        }

        addSpeaker("Alice")
        addCue("Hello and welcome to the show.\n", start: 10, end: 15)
        addCue("We are talking about pleasure today.\n", start: 16, end: 20)
        addSpeaker("Bob")
        addCue("It is a pleasure to be here.\n", start: 21, end: 25)

        guard let attributed = try? AttributedString(result, including: \.transcript) else {
            fatalError("Fixture conversion should never fail")
        }
        return TranscriptModel(attributedText: attributed, cues: cues, type: "text/vtt", hasJavascript: false)
    }
}

final class TranscriptReaderContentTests: XCTestCase {

    // MARK: - Block building

    func testMakeBlocksSplitsSpeakersAndCues() {
        let model = TranscriptReaderFixture.makeModel()
        let blocks = TranscriptReaderContent.makeBlocks(from: model)

        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0].kind, .speaker(name: "Alice"))
        XCTAssertEqual(blocks[1].kind, .paragraph(cueIndex: 0))
        XCTAssertEqual(blocks[2].kind, .paragraph(cueIndex: 1))
        XCTAssertEqual(blocks[3].kind, .speaker(name: "Bob"))
        XCTAssertEqual(blocks[4].kind, .paragraph(cueIndex: 2))

        XCTAssertEqual(blocks[0].text, "Alice")
        XCTAssertEqual(blocks[1].text, "Hello and welcome to the show.")
        XCTAssertEqual(blocks[2].text, "We are talking about pleasure today.")
        XCTAssertEqual(blocks[4].text, "It is a pleasure to be here.")

        // Ids are sequential array positions.
        XCTAssertEqual(blocks.map(\.id), Array(0 ..< blocks.count))
    }

    func testBlockRangesMatchFullTextAndAreTrimmed() {
        let model = TranscriptReaderFixture.makeModel()
        let blocks = TranscriptReaderContent.makeBlocks(from: model)
        let full = model.plainText as NSString

        for block in blocks {
            XCTAssertEqual(full.substring(with: block.rangeInFullText), block.text)
            XCTAssertEqual(block.text, block.text.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertFalse(block.text.isEmpty)
        }
    }

    func testMakeBlocksFromParsedVTT() throws {
        let vtt = """
        WEBVTT

        00:00:10.000 --> 00:00:15.000
        <v Speaker 1>Hello and welcome to the show.

        00:00:16.000 --> 00:00:20.000
        <v Speaker 2>Thanks, great to be here.
        """

        let model = try XCTUnwrap(TranscriptModel.makeModel(from: vtt, format: .vtt))
        let blocks = TranscriptReaderContent.makeBlocks(from: model)

        XCTAssertEqual(blocks.compactMap(\.speakerName), ["Speaker 1", "Speaker 2"])
        XCTAssertEqual(blocks.compactMap(\.cueIndex), Array(0 ..< model.cues.count))

        let full = model.plainText as NSString
        for block in blocks {
            XCTAssertEqual(full.substring(with: block.rangeInFullText), block.text)
            XCTAssertEqual(block.text, block.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func testMakeBlocksForCuelessTranscriptSplitsLines() {
        let text = "First paragraph of an HTML transcript.\n\nSecond paragraph."
        let model = TranscriptModel(attributedText: AttributedString(text), cues: [], type: "text/html", hasJavascript: false)

        let blocks = TranscriptReaderContent.makeBlocks(from: model)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .paragraph(cueIndex: nil))
        XCTAssertEqual(blocks[0].text, "First paragraph of an HTML transcript.")
        XCTAssertEqual(blocks[1].text, "Second paragraph.")
    }

    func testMakeBlocksForEmptyTranscript() {
        let model = TranscriptModel(attributedText: AttributedString(""), cues: [], type: "text/html", hasJavascript: false)
        XCTAssertTrue(TranscriptReaderContent.makeBlocks(from: model).isEmpty)
    }

    // MARK: - Quote assembly

    func testQuoteTextWithTitleLinkAndTime() {
        let quote = TranscriptQuoteBuilder.quoteText(
            cueText: "Hello world.",
            episodeTitle: "Episode One",
            shareURLString: "https://pca.st/episode/abc",
            startTime: 63.4
        )

        XCTAssertEqual(quote, "\u{201C}Hello world.\u{201D} — Episode One\nhttps://pca.st/episode/abc?t=63")
    }

    func testQuoteTextTrimsCueTextAndRoundsTime() {
        let quote = TranscriptQuoteBuilder.quoteText(
            cueText: "  Hello world.\n",
            episodeTitle: "Episode One",
            shareURLString: "https://pca.st/episode/abc",
            startTime: 63.6
        )

        XCTAssertEqual(quote, "\u{201C}Hello world.\u{201D} — Episode One\nhttps://pca.st/episode/abc?t=64")
    }

    func testQuoteTextWithoutTitle() {
        let quote = TranscriptQuoteBuilder.quoteText(
            cueText: "Hello world.",
            episodeTitle: nil,
            shareURLString: "https://pca.st/episode/abc",
            startTime: 10
        )

        XCTAssertEqual(quote, "\u{201C}Hello world.\u{201D}\nhttps://pca.st/episode/abc?t=10")
    }

    func testQuoteTextWithoutLink() {
        let quote = TranscriptQuoteBuilder.quoteText(
            cueText: "Hello world.",
            episodeTitle: "Episode One",
            shareURLString: nil,
            startTime: 10
        )

        XCTAssertEqual(quote, "\u{201C}Hello world.\u{201D} — Episode One")
    }

    func testQuoteTextWithoutStartTimeOmitsAnchor() {
        let quote = TranscriptQuoteBuilder.quoteText(
            cueText: "Hello world.",
            episodeTitle: nil,
            shareURLString: "https://pca.st/episode/abc",
            startTime: nil
        )

        XCTAssertEqual(quote, "\u{201C}Hello world.\u{201D}\nhttps://pca.st/episode/abc")
    }

    // MARK: - Cue tracker

    private let trackerCues = [
        TranscriptCue(startTime: 0, endTime: 5, characterRange: NSRange(location: 0, length: 5)),
        TranscriptCue(startTime: 5.5, endTime: 10, characterRange: NSRange(location: 5, length: 5)),
        TranscriptCue(startTime: 12, endTime: 20, characterRange: NSRange(location: 10, length: 5)),
        TranscriptCue(startTime: 20.5, endTime: 30, characterRange: NSRange(location: 15, length: 5))
    ]

    func testCueTrackerForwardPlayback() {
        var tracker = TranscriptCueTracker()

        XCTAssertEqual(tracker.cueIndex(at: 3, in: trackerCues), 0)
        XCTAssertEqual(tracker.cueIndex(at: 7, in: trackerCues), 1)
        XCTAssertEqual(tracker.cueIndex(at: 15, in: trackerCues), 2)
        XCTAssertEqual(tracker.cueIndex(at: 25, in: trackerCues), 3)
    }

    func testCueTrackerGapBetweenCues() {
        var tracker = TranscriptCueTracker()

        XCTAssertEqual(tracker.cueIndex(at: 7, in: trackerCues), 1)
        // 11 falls in the gap between cue 1 and cue 2.
        XCTAssertNil(tracker.cueIndex(at: 11, in: trackerCues))
        // The tracker still resolves the next cue after a gap.
        XCTAssertEqual(tracker.cueIndex(at: 13, in: trackerCues), 2)
    }

    func testCueTrackerBackwardSeek() {
        var tracker = TranscriptCueTracker()

        XCTAssertEqual(tracker.cueIndex(at: 25, in: trackerCues), 3)
        XCTAssertEqual(tracker.cueIndex(at: 7, in: trackerCues), 1)
        XCTAssertEqual(tracker.cueIndex(at: 3, in: trackerCues), 0)
    }

    func testCueTrackerBeforeFirstCue() {
        var tracker = TranscriptCueTracker()
        let cues = [TranscriptCue(startTime: 10, endTime: 20, characterRange: NSRange(location: 0, length: 5))]

        XCTAssertNil(tracker.cueIndex(at: 5, in: cues))
    }

    func testCueTrackerEmptyCues() {
        var tracker = TranscriptCueTracker()

        XCTAssertNil(tracker.cueIndex(at: 5, in: []))
    }

    func testCueTrackerOverlappingCuesResolveToEarliestMatch() {
        var tracker = TranscriptCueTracker()
        let cues = [
            TranscriptCue(startTime: 0, endTime: 10, characterRange: NSRange(location: 0, length: 5)),
            TranscriptCue(startTime: 5, endTime: 15, characterRange: NSRange(location: 5, length: 5))
        ]

        XCTAssertEqual(tracker.cueIndex(at: 7, in: cues), 0)

        // After a backward seek the full scan also resolves to the earliest match.
        XCTAssertEqual(tracker.cueIndex(at: 12, in: cues), 1)
        var rewound = TranscriptCueTracker()
        XCTAssertEqual(rewound.cueIndex(at: 12, in: cues), 1)
        XCTAssertEqual(rewound.cueIndex(at: 7, in: cues), 0)
    }

    func testCueTrackerResetRestoresFullScanFromStart() {
        var tracker = TranscriptCueTracker()

        XCTAssertEqual(tracker.cueIndex(at: 25, in: trackerCues), 3)
        tracker.reset()
        XCTAssertEqual(tracker.cueIndex(at: 3, in: trackerCues), 0)
    }
}
