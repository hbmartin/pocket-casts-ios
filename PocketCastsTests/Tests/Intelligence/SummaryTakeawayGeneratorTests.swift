import Foundation
import FoundationModels
import XCTest

@testable import podcasts

// MARK: - Mock provider

/// Deterministic `IntelligenceProviding` stand-in: fixed availability and a
/// canned (or throwing) guided-generation result.
nonisolated private struct MockIntelligenceProvider: IntelligenceProviding {
    var availabilityResult: IntelligenceAvailability = .available
    var respondResult: @Sendable () throws -> GeneratedTakeawayList = { GeneratedTakeawayList(takeaways: []) }

    func availability() -> IntelligenceAvailability {
        availabilityResult
    }

    func respond<T: Generable & Sendable>(
        instructions: String,
        prompt: String,
        generating type: T.Type
    ) async throws -> T {
        guard let value = try respondResult() as? T else {
            throw IntelligenceError.decodingFailed
        }
        return value
    }
}

final class SummaryTakeawayGeneratorTests: XCTestCase {

    private let cues: [TimedCueText] = [
        TimedCueText(startTime: 0, text: "Welcome to the show."),
        TimedCueText(startTime: 60, text: "Our guest explains the rewrite."),
        TimedCueText(startTime: 120, text: "Why written culture beats meetings."),
        TimedCueText(startTime: 300, text: "Wrapping up with listener questions.")
    ]

    private let keyMoments: [Takeaway] = [
        Takeaway(text: "Introduction", startTime: 0),
        Takeaway(text: "Interview", startTime: 90)
    ]

    // MARK: - FoundationModels layer

    func testFoundationModelsPathProducesValidatedTakeaways() async {
        let provider = MockIntelligenceProvider(respondResult: {
            GeneratedTakeawayList(takeaways: [
                GeneratedTakeawayItem(text: "The rewrite worked because scope was frozen.", startSeconds: 65),
                GeneratedTakeawayItem(text: "Writing beats meetings for small teams.", startSeconds: 118)
            ])
        })
        let generator = SummaryTakeawayGenerator(intelligence: provider)

        let result = await generator.takeaways(cues: cues, keyMoments: keyMoments, duration: 400)

        XCTAssertEqual(result.layer, .foundationModels)
        XCTAssertNil(result.fallbackReason)
        XCTAssertEqual(result.takeaways, [
            Takeaway(text: "The rewrite worked because scope was frozen.", startTime: 60),
            Takeaway(text: "Writing beats meetings for small teams.", startTime: 120)
        ], "timestamps snap to the nearest cue start")
    }

    // MARK: - Fallback layering

    func testModelUnavailableFallsBackToKeyMoments() async {
        let provider = MockIntelligenceProvider(
            availabilityResult: .unavailable(reason: "model_not_ready"),
            respondResult: {
                XCTFail("respond must not be called when the model is unavailable")
                return GeneratedTakeawayList(takeaways: [])
            }
        )
        let generator = SummaryTakeawayGenerator(intelligence: provider)

        let result = await generator.takeaways(cues: cues, keyMoments: keyMoments, duration: 400)

        XCTAssertEqual(result.layer, .generatedChapters)
        XCTAssertEqual(result.takeaways, keyMoments)
        XCTAssertEqual(result.fallbackReason, "model_not_ready")
    }

    func testModelErrorFallsBackToKeyMoments() async {
        let provider = MockIntelligenceProvider(respondResult: {
            throw IntelligenceError.timedOut
        })
        let generator = SummaryTakeawayGenerator(intelligence: provider)

        let result = await generator.takeaways(cues: cues, keyMoments: keyMoments, duration: 400)

        XCTAssertEqual(result.layer, .generatedChapters)
        XCTAssertEqual(result.takeaways, keyMoments)
        XCTAssertEqual(result.fallbackReason, "timed_out")
    }

    func testNoTranscriptSkipsModelEntirely() async {
        let provider = MockIntelligenceProvider(respondResult: {
            XCTFail("respond must not be called without transcript cues")
            return GeneratedTakeawayList(takeaways: [])
        })
        let generator = SummaryTakeawayGenerator(intelligence: provider)

        let result = await generator.takeaways(cues: [], keyMoments: keyMoments, duration: 400)

        XCTAssertEqual(result.layer, .generatedChapters)
        XCTAssertEqual(result.takeaways, keyMoments)
        XCTAssertEqual(result.fallbackReason, "no_transcript")
    }

    func testNothingAvailableIsSummaryOnly() async {
        let provider = MockIntelligenceProvider(availabilityResult: .unavailable(reason: "device_not_eligible"))
        let generator = SummaryTakeawayGenerator(intelligence: provider)

        let result = await generator.takeaways(cues: [], keyMoments: [], duration: 400)

        XCTAssertEqual(result.layer, .summaryOnly)
        XCTAssertTrue(result.takeaways.isEmpty)
        XCTAssertEqual(result.fallbackReason, "no_transcript")
    }

    func testAllOutputDroppedInValidationFallsBack() async {
        let provider = MockIntelligenceProvider(respondResult: {
            GeneratedTakeawayList(takeaways: [
                // 1000s clamps to duration 400, nearest cue 300 is 100s away — dropped.
                GeneratedTakeawayItem(text: "Non-snappable", startSeconds: 1000)
            ])
        })
        let generator = SummaryTakeawayGenerator(intelligence: provider)

        let result = await generator.takeaways(cues: cues, keyMoments: keyMoments, duration: 400)

        XCTAssertEqual(result.layer, .generatedChapters)
        XCTAssertEqual(result.fallbackReason, "empty_after_validation")
    }

    // MARK: - Validation (clamp / snap / drop), table-driven

    func testValidatedClampSnapDropTable() {
        let cueStartTimes: [TimeInterval] = [0, 60, 120, 300]

        struct Case {
            let name: String
            let item: GeneratedTakeawayItem
            let duration: TimeInterval
            let expected: Takeaway?
        }

        let longText = String(repeating: "x", count: 250)

        let cases: [Case] = [
            Case(name: "exact cue time passes through",
                 item: GeneratedTakeawayItem(text: "a", startSeconds: 60),
                 duration: 400,
                 expected: Takeaway(text: "a", startTime: 60)),
            Case(name: "near time snaps to nearest cue",
                 item: GeneratedTakeawayItem(text: "b", startSeconds: 65),
                 duration: 400,
                 expected: Takeaway(text: "b", startTime: 60)),
            Case(name: "negative time clamps to zero then snaps",
                 item: GeneratedTakeawayItem(text: "c", startSeconds: -10),
                 duration: 400,
                 expected: Takeaway(text: "c", startTime: 0)),
            Case(name: "overshoot clamps to duration then snaps when in tolerance",
                 item: GeneratedTakeawayItem(text: "d", startSeconds: 1000),
                 duration: 320,
                 expected: Takeaway(text: "d", startTime: 300)),
            Case(name: "non-snappable after clamping is dropped",
                 item: GeneratedTakeawayItem(text: "e", startSeconds: 1000),
                 duration: 400,
                 expected: nil),
            Case(name: "unknown duration skips the upper clamp",
                 item: GeneratedTakeawayItem(text: "f", startSeconds: 290),
                 duration: 0,
                 expected: Takeaway(text: "f", startTime: 300)),
            Case(name: "whitespace-only text is dropped",
                 item: GeneratedTakeawayItem(text: "   \n", startSeconds: 60),
                 duration: 400,
                 expected: nil),
            Case(name: "overlong text is capped at 200 characters",
                 item: GeneratedTakeawayItem(text: longText, startSeconds: 60),
                 duration: 400,
                 expected: Takeaway(text: String(longText.prefix(200)), startTime: 60))
        ]

        for testCase in cases {
            let validated = SummaryTakeawayGenerator.validated(
                [testCase.item],
                cueStartTimes: cueStartTimes,
                duration: testCase.duration
            )
            if let expected = testCase.expected {
                XCTAssertEqual(validated, [expected], testCase.name)
            } else {
                XCTAssertTrue(validated.isEmpty, testCase.name)
            }
        }
    }

    func testValidatedDeduplicatesSortsAndLimits() {
        let cueStartTimes: [TimeInterval] = [0, 60, 120, 180, 240, 300, 360]
        let items = [
            GeneratedTakeawayItem(text: "late", startSeconds: 300),
            GeneratedTakeawayItem(text: "dupe of late", startSeconds: 302),
            GeneratedTakeawayItem(text: "early", startSeconds: 0),
            GeneratedTakeawayItem(text: "mid", startSeconds: 121),
            GeneratedTakeawayItem(text: "one", startSeconds: 60),
            GeneratedTakeawayItem(text: "two", startSeconds: 180),
            GeneratedTakeawayItem(text: "over the limit", startSeconds: 240)
        ]

        let validated = SummaryTakeawayGenerator.validated(items, cueStartTimes: cueStartTimes, duration: 400)

        XCTAssertEqual(validated.count, 5, "capped at the default limit")
        XCTAssertEqual(validated.map(\.startTime), validated.map(\.startTime).sorted(), "sorted ascending")
        XCTAssertEqual(Set(validated.map(\.startTime)).count, validated.count, "no duplicate snapped times")
        XCTAssertFalse(validated.contains { $0.text == "dupe of late" }, "second item snapping to a used time is dropped")
    }

    func testValidatedWithNoCuesReturnsNothing() {
        let validated = SummaryTakeawayGenerator.validated(
            [GeneratedTakeawayItem(text: "a", startSeconds: 10)],
            cueStartTimes: [],
            duration: 100
        )
        XCTAssertTrue(validated.isEmpty)
    }

    // MARK: - Digest

    func testDigestFormatsLinesWithBracketedSeconds() {
        let digest = SummaryTakeawayGenerator.digest(from: [
            TimedCueText(startTime: 0, text: "Hello"),
            TimedCueText(startTime: 65.4, text: "World")
        ])
        XCTAssertEqual(digest, "[0] Hello\n[65] World")
    }

    func testDigestSkipsEmptyCuesAndRespectsBudget() {
        let cues = [
            TimedCueText(startTime: 0, text: "   "),
            TimedCueText(startTime: 1, text: "Kept"),
            TimedCueText(startTime: 2, text: String(repeating: "y", count: 100))
        ]
        let digest = SummaryTakeawayGenerator.digest(from: cues, characterBudget: 20)
        XCTAssertEqual(digest, "[1] Kept", "empty cue skipped, over-budget cue dropped")
    }

    func testDigestCapsIndividualCueText() {
        let digest = SummaryTakeawayGenerator.digest(
            from: [TimedCueText(startTime: 3, text: String(repeating: "z", count: 500))],
            cueCharacterCap: 10
        )
        XCTAssertEqual(digest, "[3] \(String(repeating: "z", count: 10))")
    }

    // MARK: - Cue extraction

    func testTimedCuesExtractionFromTranscriptModel() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:03.000
        Hello world

        00:00:04.000 --> 00:00:06.000
        Second cue
        """
        let model = try XCTUnwrap(TranscriptModel.makeModel(from: vtt, format: .vtt))

        let cues = SummaryTakeawayGenerator.timedCues(from: model)

        XCTAssertEqual(cues, [
            TimedCueText(startTime: 1, text: "Hello world"),
            TimedCueText(startTime: 4, text: "Second cue")
        ])
    }
}
