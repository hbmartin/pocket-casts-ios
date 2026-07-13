import Foundation
import Testing
@testable import PocketCastsTranscription

private func cue(_ speaker: String?, _ text: String, _ start: Double, _ end: Double) -> DiarizedCue {
    DiarizedCue(speaker: speaker, text: text, start: start, end: end)
}

struct VTTSerializerTests {
    // MARK: - Golden file

    @Test func goldenMultiSpeakerFile() {
        let cues = [
            cue("Speaker 1", "Welcome back to the show.", 0, 4.25),
            cue("Speaker 2", "Thanks for having me!", 4.5, 6),
            cue(nil, "[music]", 3690.25, 3691.5),
        ]

        let expected = """
        WEBVTT

        00:00:00.000 --> 00:00:04.250
        <v Speaker 1>Welcome back to the show.

        00:00:04.500 --> 00:00:06.000
        <v Speaker 2>Thanks for having me!

        01:01:30.250 --> 01:01:31.500
        [music]

        """

        #expect(VTTSerializer.serialize(cues: cues) == expected)
    }

    @Test func emptyCueListSerializesToBareHeader() {
        #expect(VTTSerializer.serialize(cues: []) == "WEBVTT\n")
    }

    @Test func transcriptConvenienceMatchesCueSerialization() {
        let cues = [cue("Speaker 1", "Hi", 0, 1), cue("Speaker 2", "Hey", 1, 2)]
        let transcript = DiarizedTranscript(
            cues: cues, language: "en", speakerCount: 2, engineDescription: "test")

        #expect(VTTSerializer.serialize(transcript) == VTTSerializer.serialize(cues: cues))
    }

    // MARK: - Voice tags

    @Test func nilSpeakerOmitsVoiceTag() {
        let output = VTTSerializer.serialize(cues: [cue(nil, "Monologue text", 0, 2)])

        #expect(output.contains("Monologue text\n"))
        #expect(!output.contains("<v"))
    }

    @Test func speakerEmitsVoiceTag() {
        let output = VTTSerializer.serialize(cues: [cue("Speaker 3", "Hello", 0, 2)])

        #expect(output.contains("<v Speaker 3>Hello\n"))
    }

    // MARK: - Escaping

    @Test func escapesReservedCharactersInCueText() {
        let output = VTTSerializer.serialize(cues: [
            cue("Speaker 1", "Tom & Jerry think 1 < 2 && 2 > 1 <v fake>", 0, 1)
        ])

        #expect(output.contains("<v Speaker 1>Tom &amp; Jerry think 1 &lt; 2 &amp;&amp; 2 &gt; 1 &lt;v fake&gt;\n"))
    }

    @Test func escapesAmpersandBeforeAngleBrackets() {
        // "&lt;" in source text must not double-escape into "&amp;lt;" wrongly ordered:
        // & first, then < and > — so "&<" becomes "&amp;&lt;".
        #expect(VTTSerializer.escape("&<>") == "&amp;&lt;&gt;")
        #expect(VTTSerializer.escape("&amp;") == "&amp;amp;")
    }

    @Test(arguments: [
        ("plain text", "plain text"),
        ("", ""),
        ("a & b", "a &amp; b"),
        ("<v Speaker 1>", "&lt;v Speaker 1&gt;"),
        ("5 > 3 < 7", "5 &gt; 3 &lt; 7"),
    ])
    func escapeTable(input: String, expected: String) {
        #expect(VTTSerializer.escape(input) == expected)
    }

    // MARK: - Zero-length clamp

    @Test func zeroLengthCueIsClampedByTenMilliseconds() {
        let output = VTTSerializer.serialize(cues: [cue(nil, "Blip", 5, 5)])

        #expect(output.contains("00:00:05.000 --> 00:00:05.010"))
    }

    @Test func invertedCueIsClampedByTenMilliseconds() {
        let output = VTTSerializer.serialize(cues: [cue(nil, "Blip", 5, 4)])

        #expect(output.contains("00:00:05.000 --> 00:00:05.010"))
    }

    @Test func negativeStartClampsToZero() {
        let output = VTTSerializer.serialize(cues: [cue(nil, "Early", -1, 2)])

        #expect(output.contains("00:00:00.000 --> 00:00:02.000"))
    }

    @Test func positiveLengthCueIsNotClamped() {
        let output = VTTSerializer.serialize(cues: [cue(nil, "Ok", 5, 5.5)])

        #expect(output.contains("00:00:05.000 --> 00:00:05.500"))
    }

    // MARK: - Timestamp formatting

    @Test(arguments: [
        (0.0, "00:00:00.000"),
        (0.001, "00:00:00.001"),
        (0.0625, "00:00:00.063"), // 62.5ms rounds half away from zero.
        (1.5, "00:00:01.500"),
        (59.999, "00:00:59.999"),
        (60.0, "00:01:00.000"),
        (61.25, "00:01:01.250"),
        (599.5, "00:09:59.500"),
        (3599.999, "00:59:59.999"),
        (3600.0, "01:00:00.000"), // > 1hr boundary.
        (3661.25, "01:01:01.250"),
        (7322.5, "02:02:02.500"),
        (36000.0, "10:00:00.000"),
        (360000.0, "100:00:00.000"), // Hours field grows beyond two digits.
    ])
    func timestampFormatting(seconds: Double, expected: String) {
        #expect(VTTSerializer.timestamp(seconds) == expected)
    }

    @Test func millisecondRoundingCannotProduceAThousand() {
        // 0.9995s rounds to exactly 1000ms, which must carry into the seconds
        // field rather than render as 00:00:00.1000.
        let formatted = VTTSerializer.timestamp(0.9995)

        #expect(formatted == "00:00:01.000" || formatted == "00:00:00.999")
        #expect(formatted.count == "00:00:00.000".count)
    }

    // MARK: - Payload safety

    @Test func newlinesInCueTextAreFlattenedToSpaces() {
        // A blank line inside a payload would terminate the cue early.
        let output = VTTSerializer.serialize(cues: [
            cue("Speaker 1", "line one\n\nline two\nline three", 0, 1)
        ])

        #expect(output.contains("<v Speaker 1>line one line two line three\n"))
    }

    @Test func multipleCuesAreSeparatedByBlankLines() {
        let output = VTTSerializer.serialize(cues: [
            cue("Speaker 1", "One", 0, 1),
            cue("Speaker 2", "Two", 1, 2),
        ])

        let expected = """
        WEBVTT

        00:00:00.000 --> 00:00:01.000
        <v Speaker 1>One

        00:00:01.000 --> 00:00:02.000
        <v Speaker 2>Two

        """
        #expect(output == expected)
    }

    // MARK: - Aligner integration

    @Test func alignerOutputSerializesDirectly() {
        let segments = [
            ASRSegment(text: "Hello there.", start: 0, end: 2),
            ASRSegment(text: "Hi!", start: 2.1, end: 3),
        ]
        let turns = [
            SpeakerTurn(speakerId: "X", start: 0, end: 2),
            SpeakerTurn(speakerId: "Y", start: 2, end: 3),
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        let expected = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        <v Speaker 1>Hello there.

        00:00:02.100 --> 00:00:03.000
        <v Speaker 2>Hi!

        """
        #expect(VTTSerializer.serialize(cues: cues) == expected)
    }
}
