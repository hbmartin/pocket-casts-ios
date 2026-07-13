import Foundation
import PocketCastsTranscription
import XCTest

@testable import podcasts

/// The integration contract between the transcription module and the app's
/// existing transcript stack: whatever `SpeakerAligner` + `VTTSerializer` emit
/// must parse through `TranscriptModel.makeModel(from:format:.vtt)` with cue
/// count, cue times and speaker attribution preserved.
final class VTTRoundTripTests: XCTestCase {
    func testDiarizedOutputRoundTripsThroughTranscriptModel() throws {
        let segments = [
            ASRSegment(text: "Hello there everyone.", start: 0, end: 2.5,
                       words: [
                           TranscriptWord(text: "Hello", start: 0, end: 0.5),
                           TranscriptWord(text: "there", start: 0.6, end: 1.1),
                           TranscriptWord(text: "everyone.", start: 1.2, end: 2.5)
                       ]),
            ASRSegment(text: "Welcome back to the show.", start: 3.0, end: 5.0),
            ASRSegment(text: "Thanks for having me back.", start: 5.5, end: 7.25)
        ]
        let turns = [
            SpeakerTurn(speakerId: "SPEAKER_00", start: 0, end: 5.2),
            SpeakerTurn(speakerId: "SPEAKER_01", start: 5.4, end: 8.0)
        ]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues.map(\.speaker), ["Speaker 1", "Speaker 2"])

        let vtt = VTTSerializer.serialize(cues: cues)
        let model = try XCTUnwrap(TranscriptModel.makeModel(from: vtt, format: .vtt))

        XCTAssertEqual(model.cues.count, cues.count)
        for (parsed, original) in zip(model.cues, cues) {
            XCTAssertEqual(parsed.startTime, original.start, accuracy: 0.002)
            XCTAssertEqual(parsed.endTime, original.end, accuracy: 0.002)
        }

        XCTAssertEqual(speakerHeaders(in: model), ["Speaker 1", "Speaker 2"])
        XCTAssertTrue(model.plainText.contains("Hello there everyone."))
        XCTAssertTrue(model.plainText.contains("Thanks for having me back."))
        XCTAssertFalse(model.plainText.contains("<v"), "voice tags must be stripped from rendered text")
    }

    func testMonologueRoundTripsWithoutSpeakerTags() throws {
        let segments = [
            ASRSegment(text: "Just one voice talking here.", start: 0, end: 3),
            ASRSegment(text: "Still the same voice.", start: 4.5, end: 6)
        ]

        // Phase 1 runs with no diarizer: empty turns produce untagged cues.
        let cues = SpeakerAligner.align(segments: segments, turns: [])
        XCTAssertFalse(cues.isEmpty)
        XCTAssertTrue(cues.allSatisfy { $0.speaker == nil })

        let vtt = VTTSerializer.serialize(cues: cues)
        XCTAssertFalse(vtt.contains("<v"), "monologues must serialize without voice tags")

        let model = try XCTUnwrap(TranscriptModel.makeModel(from: vtt, format: .vtt))
        XCTAssertEqual(model.cues.count, cues.count)
        for (parsed, original) in zip(model.cues, cues) {
            XCTAssertEqual(parsed.startTime, original.start, accuracy: 0.002)
            XCTAssertEqual(parsed.endTime, original.end, accuracy: 0.002)
        }
        XCTAssertTrue(speakerHeaders(in: model).isEmpty)
    }

    /// The speaker-header runs `TranscriptModel` derives from `<v>` voice tags,
    /// in document order.
    private func speakerHeaders(in model: TranscriptModel) -> [String] {
        let text = model.nsAttributedText
        var headers: [String] = []
        text.enumerateAttribute(.transcriptSpeaker, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let name = value as? String {
                headers.append(name)
            }
        }
        return headers
    }
}
