import Foundation
import Testing
@testable import PocketCastsTranscription

// MARK: - Fixture helpers

private func seg(_ text: String, _ start: Double, _ end: Double, words: [TranscriptWord]? = nil) -> ASRSegment {
    ASRSegment(text: text, start: start, end: end, words: words)
}

private func word(_ text: String, _ start: Double, _ end: Double) -> TranscriptWord {
    TranscriptWord(text: text, start: start, end: end)
}

private func turn(_ id: String, _ start: Double, _ end: Double) -> SpeakerTurn {
    SpeakerTurn(speakerId: id, start: start, end: end)
}

/// Compact projection of a cue for table-driven expectations.
private struct ExpectedCue: Equatable, CustomStringConvertible {
    let speaker: String?
    let text: String

    init(_ speaker: String?, _ text: String) {
        self.speaker = speaker
        self.text = text
    }

    init(cue: DiarizedCue) {
        self.speaker = cue.speaker
        self.text = cue.text
    }

    var description: String { "\(speaker ?? "nil"): \(text)" }
}

private func project(_ cues: [DiarizedCue]) -> [ExpectedCue] {
    cues.map(ExpectedCue.init(cue:))
}

struct SpeakerAlignerTests {
    // MARK: - Step 1: unit selection (words when present, else segments)

    @Test func wordTimingsSplitASegmentAcrossASpeakerChange() {
        let segments = [
            seg("Hello there. Hi!", 0, 7, words: [
                word("Hello", 0, 1),
                word("there.", 1, 2),
                word("Hi!", 6, 7),
            ])
        ]
        let turns = [turn("A", 0, 3), turn("B", 5.5, 10)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "Hello there."),
            ExpectedCue("Speaker 2", "Hi!"),
        ])
        #expect(cues[0].start == 0)
        #expect(cues[0].end == 2)
        #expect(cues[1].start == 6)
        #expect(cues[1].end == 7)
    }

    @Test func segmentWithoutWordsIsAssignedAsAWhole() {
        // Without word timings the same audio can't split mid-segment: each
        // segment takes the single max-overlap speaker.
        let segments = [seg("One", 0, 4), seg("Two", 4, 10)]
        let turns = [turn("A", 0, 4.5), turn("B", 4.5, 10)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "One"),
            ExpectedCue("Speaker 2", "Two"),
        ])
    }

    @Test func mixedSegmentsUseWordsWherePresentAndSegmentsElsewhere() {
        let segments = [
            seg("Alpha beta", 0, 4, words: [word("Alpha", 0, 1), word("beta", 3, 4)]),
            seg("Gamma", 4, 8),
        ]
        let turns = [turn("A", 0, 2), turn("B", 2, 8)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "Alpha"),
            ExpectedCue("Speaker 2", "beta Gamma"),
        ])
    }

    @Test func emptySegmentsProduceNoCues() {
        #expect(SpeakerAligner.align(segments: [], turns: [turn("A", 0, 5)]) == [])
    }

    @Test func whitespaceOnlyUnitsAreDropped() {
        let segments = [
            seg("  ", 0, 1),
            seg("Real text", 1, 2, words: [word("Real", 1, 1.5), word("  ", 1.5, 1.6), word("text", 1.6, 2)]),
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(project(cues) == [ExpectedCue(nil, "Real text")])
    }

    @Test func unitTextIsTrimmedBeforeJoining() {
        let segments = [
            seg("Hello world", 0, 2, words: [word(" Hello", 0, 1), word(" world ", 1, 2)])
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello world")
    }

    @Test func outOfOrderSegmentsAreSortedByStart() {
        let segments = [seg("Second", 5, 6), seg("First", 0, 1)]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 1)
        #expect(cues[0].text == "First Second")
        #expect(cues[0].start == 0)
        #expect(cues[0].end == 6)
    }

    // MARK: - Step 2: speaker assignment

    @Test func maximalOverlapWins() {
        let segments = [
            seg("gamma alpha", 0, 10, words: [
                word("gamma", 0, 1), // Only overlaps A.
                word("alpha", 1, 10), // A overlap 3s, B overlap 6s -> B.
            ])
        ]
        let turns = [turn("A", 0, 4), turn("B", 4, 10)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "gamma"),
            ExpectedCue("Speaker 2", "alpha"),
        ])
    }

    @Test func overlapTieGoesToTheEarlierTurn() {
        let segments = [
            seg("tied later", 4, 9, words: [
                word("tied", 4, 6), // 1s overlap with each turn -> earlier turn A.
                word("later", 8, 9), // Only overlaps B.
            ])
        ]
        let turns = [turn("A", 0, 5), turn("B", 5, 10)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "tied"),
            ExpectedCue("Speaker 2", "later"),
        ])
    }

    @Test func zeroOverlapAssignsNearestTurnMidpointWithinTolerance() {
        let segments = [
            seg("one two three", 0, 6, words: [
                word("one", 0, 1), // Inside A.
                word("two", 1.1, 1.5), // No overlap; midpoint 1.3 is 0.8 from A's midpoint (0.5).
                word("three", 5, 6), // Inside B.
            ])
        ]
        let turns = [turn("A", 0, 1), turn("B", 5, 6)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "one two"),
            ExpectedCue("Speaker 2", "three"),
        ])
    }

    @Test func gapToleranceIsInclusiveAtTheBoundary() {
        // Word midpoint 1.5 is exactly 1.0 from turn A's midpoint 0.5 (all values
        // binary-exact) -> still assigned to A.
        let segments = [
            seg("one edge three", 0, 6, words: [
                word("one", 0, 1),
                word("edge", 1.25, 1.75),
                word("three", 5, 6),
            ])
        ]
        let turns = [turn("A", 0, 1), turn("B", 5, 6)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "one edge"),
            ExpectedCue("Speaker 2", "three"),
        ])
    }

    @Test func beyondGapToleranceInheritsThePreviousSpeaker() {
        // Word midpoint 1.75 is 1.25 from A's midpoint and far from B's -> falls
        // back to inheriting the previous unit's speaker (A).
        let segments = [
            seg("one drift three", 0, 8, words: [
                word("one", 0, 1),
                word("drift", 1.5, 2),
                word("three", 7, 8),
            ])
        ]
        let turns = [turn("A", 0, 1), turn("B", 7, 8)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "one drift"),
            ExpectedCue("Speaker 2", "three"),
        ])
    }

    @Test func gapToleranceIsInjectable() {
        // "drift" (midpoint 2.75) sits 1.75s from turn A's midpoint: unreachable
        // at the default 1.0s tolerance (nil — nothing to inherit), reachable at 2.0s.
        let segments = [
            seg("drift a b", 2.5, 11, words: [
                word("drift", 2.5, 3),
                word("a", 4, 5),
                word("b", 10, 11),
            ])
        ]
        let turns = [turn("A", 4, 5), turn("B", 10, 11)]

        let defaultCues = SpeakerAligner.align(segments: segments, turns: turns)
        let wideCues = SpeakerAligner.align(
            segments: segments, turns: turns,
            options: SpeakerAligner.Options(gapTolerance: 2.0))

        #expect(project(defaultCues) == [
            ExpectedCue(nil, "drift"),
            ExpectedCue("Speaker 1", "a"),
            ExpectedCue("Speaker 2", "b"),
        ])
        #expect(project(wideCues) == [
            ExpectedCue("Speaker 1", "drift a"),
            ExpectedCue("Speaker 2", "b"),
        ])
    }

    @Test func unassignableFirstUnitWithNoPreviousSpeakerIsNil() {
        let segments = [
            seg("intro one two", 0, 21, words: [
                word("intro", 0, 1), // Far from every turn, nothing to inherit -> nil.
                word("one", 10, 11),
                word("two", 20, 21),
            ])
        ]
        let turns = [turn("A", 10, 11), turn("B", 20, 21)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue(nil, "intro"),
            ExpectedCue("Speaker 1", "one"),
            ExpectedCue("Speaker 2", "two"),
        ])
    }

    // MARK: - Steps 4 & 5: normalization

    @Test func speakersAreNormalizedByFirstAppearance() {
        // The diarizer's raw IDs are reversed alphabetically; first appearance wins.
        let segments = [seg("First", 0, 2), seg("Second", 2, 4)]
        let turns = [turn("SPEAKER_07", 0, 2), turn("SPEAKER_00", 2, 4)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "First"),
            ExpectedCue("Speaker 2", "Second"),
        ])
    }

    @Test func recurringSpeakerKeepsItsNumber() {
        let segments = [
            seg("a", 0, 1), seg("b", 1, 2), seg("c", 2, 3),
        ]
        let turns = [turn("X", 0, 1), turn("Y", 1, 2), turn("X", 2, 3)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "a"),
            ExpectedCue("Speaker 2", "b"),
            ExpectedCue("Speaker 1", "c"),
        ])
    }

    @Test func singleDistinctSpeakerEmitsNilSpeakers() {
        let segments = [seg("Hello.", 0, 5), seg("Still me talking.", 6, 10)]
        let turns = [turn("A", 0, 10)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(!cues.isEmpty)
        #expect(cues.allSatisfy { $0.speaker == nil })
    }

    @Test func emptyTurnsEmitNilSpeakers() {
        let segments = [seg("Hello.", 0, 5), seg("World.", 6, 10)]

        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(!cues.isEmpty)
        #expect(cues.allSatisfy { $0.speaker == nil })
    }

    @Test func twoDistinctSpeakersKeepLabelsEvenWithNilGaps() {
        let segments = [seg("intro", 0, 1), seg("a", 10, 11), seg("b", 20, 21)]
        let turns = [turn("A", 10, 11), turn("B", 20, 21)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(cues.map(\.speaker) == [nil, "Speaker 1", "Speaker 2"])
    }

    // MARK: - Step 3: cue grouping

    @Test func speakerChangeBreaksCues() {
        let segments = (0..<4).map { seg("s\($0)", Double($0), Double($0 + 1)) }
        let turns = [turn("A", 0, 1), turn("B", 1, 2), turn("A", 2, 3), turn("B", 3, 4)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(cues.map(\.speaker) == ["Speaker 1", "Speaker 2", "Speaker 1", "Speaker 2"])
    }

    @Test func sentencePunctuationPlusPauseBreaksACue() {
        let segments = [
            seg("Hello. World", 0, 3, words: [
                word("Hello.", 0, 1),
                word("World", 2, 3), // 1.0s pause after sentence-final "." -> break.
            ])
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(project(cues) == [ExpectedCue(nil, "Hello."), ExpectedCue(nil, "World")])
    }

    @Test func punctuationWithoutEnoughPauseDoesNotBreak() {
        let segments = [
            seg("Hello. World", 0, 2, words: [
                word("Hello.", 0, 1),
                word("World", 1.5, 2), // 0.5s pause: below threshold.
            ])
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(project(cues) == [ExpectedCue(nil, "Hello. World")])
    }

    @Test func pauseExactlyAtThresholdDoesNotBreak() {
        // The break requires a pause strictly greater than 0.75s.
        let segments = [
            seg("Hello. World", 0, 2, words: [
                word("Hello.", 0, 1),
                word("World", 1.75, 2),
            ])
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 1)
    }

    @Test func pauseWithoutSentencePunctuationDoesNotBreak() {
        let segments = [
            seg("Hello World", 0, 5, words: [
                word("Hello", 0, 1),
                word("World", 4, 5), // Long pause but no sentence-final punctuation.
            ])
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 1)
    }

    @Test(arguments: [
        ("Done.", true),
        ("Done!", true),
        ("Done?", true),
        ("Done\u{2026}", true), // Ellipsis character.
        ("Really?\"", true), // Terminator inside a trailing quote.
        ("(Done.)", true),
        ("Done", false),
        ("Done,", false),
        ("Done;", false),
        ("\"\"", false), // Wrappers only, nothing underneath.
        ("", false),
    ])
    func sentenceFinalPunctuationDetection(text: String, expected: Bool) {
        #expect(SpeakerAligner.endsSentence(text) == expected)
    }

    @Test func characterCapBreaksCues() {
        let ninetyNine = String(repeating: "a", count: 99)
        let segments = [
            seg(ninetyNine, 0, 1),
            seg(ninetyNine, 1, 2), // Joined: 199 chars, still within 200.
            seg(ninetyNine, 2, 3), // Would make 299 -> breaks.
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 2)
        #expect(cues[0].text.count == 199)
        #expect(cues[1].text.count == 99)
    }

    @Test func characterCapIsInclusiveAtExactlyTwoHundred() {
        let segments = [
            seg(String(repeating: "a", count: 100), 0, 1),
            seg(String(repeating: "b", count: 99), 1, 2), // 100 + space + 99 = 200 exactly.
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 1)
        #expect(cues[0].text.count == 200)
    }

    @Test func oversizedSingleUnitStillFormsItsOwnCue() {
        let segments = [seg(String(repeating: "x", count: 300), 0, 1)]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 1)
        #expect(cues[0].text.count == 300)
    }

    @Test func durationCapBreaksCues() {
        let segments = [
            seg("one", 0, 8),
            seg("two", 8, 14), // Cue now spans 14s, within 15.
            seg("three", 14, 20), // Would span 20s -> breaks.
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(project(cues) == [ExpectedCue(nil, "one two"), ExpectedCue(nil, "three")])
        #expect(cues[0].start == 0)
        #expect(cues[0].end == 14)
        #expect(cues[1].start == 14)
        #expect(cues[1].end == 20)
    }

    @Test func durationCapIsInclusiveAtExactlyFifteenSeconds() {
        let segments = [seg("one", 0, 10), seg("two", 10, 15)]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 1)
        #expect(cues[0].end == 15)
    }

    @Test func groupingCapsAreInjectable() {
        let segments = [seg("aaaa", 0, 1), seg("bbbb", 1, 2)]
        let cues = SpeakerAligner.align(
            segments: segments, turns: [],
            options: SpeakerAligner.Options(maxCueCharacters: 5))

        #expect(cues.count == 2)
    }

    @Test func cueSpansFirstUnitStartToLastUnitEnd() {
        let segments = [
            seg("Hello world again", 0.5, 3.5, words: [
                word("Hello", 0.5, 1),
                word("world", 1.5, 2),
                word("again", 3, 3.5),
            ])
        ]
        let cues = SpeakerAligner.align(segments: segments, turns: [])

        #expect(cues.count == 1)
        #expect(cues[0].start == 0.5)
        #expect(cues[0].end == 3.5)
        #expect(cues[0].text == "Hello world again")
    }

    // MARK: - End-to-end shape

    @Test func typicalTwoSpeakerConversation() {
        let segments = [
            seg("Welcome back to the show.", 0, 3, words: [
                word("Welcome", 0, 0.6),
                word("back", 0.6, 1),
                word("to", 1, 1.2),
                word("the", 1.2, 1.4),
                word("show.", 1.4, 3),
            ]),
            seg("Thanks for having me!", 3.4, 5.5, words: [
                word("Thanks", 3.4, 3.9),
                word("for", 3.9, 4.2),
                word("having", 4.2, 4.8),
                word("me!", 4.8, 5.5),
            ]),
            seg("So tell us your story.", 6.5, 9, words: [
                word("So", 6.5, 6.8),
                word("tell", 6.8, 7.2),
                word("us", 7.2, 7.5),
                word("your", 7.5, 7.9),
                word("story.", 7.9, 9),
            ]),
        ]
        let turns = [turn("host", 0, 3.2), turn("guest", 3.3, 5.7), turn("host", 6.4, 9.2)]

        let cues = SpeakerAligner.align(segments: segments, turns: turns)

        #expect(project(cues) == [
            ExpectedCue("Speaker 1", "Welcome back to the show."),
            ExpectedCue("Speaker 2", "Thanks for having me!"),
            ExpectedCue("Speaker 1", "So tell us your story."),
        ])
    }
}
