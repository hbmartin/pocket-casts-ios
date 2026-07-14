import XCTest

@testable import podcasts

/// The result store/query behind the trim-silence VAD veto and adaptive
/// effects switching, driven with synthetic classifier results.
///
/// Regression focus (P2-1): completed SoundAnalysis windows are stored as
/// half-open frame ranges whose upperBound can never exceed the live read
/// head, so querying AT the head always returned nil and adaptive effects
/// never activated. Queries must lag the head by `queryLagFrames`.
final class TrimVoiceActivityAnalyzerTests: XCTestCase {
    private let sampleRate: Double = 44100

    private func makeAnalyzer() throws -> TrimVoiceActivityAnalyzer {
        do {
            return try TrimVoiceActivityAnalyzer(sampleRate: sampleRate)
        } catch {
            throw XCTSkip("System sound classifier unavailable in this environment: \(error)")
        }
    }

    private func frames(_ seconds: Double) -> Int64 {
        Int64(seconds * sampleRate)
    }

    func testLiveHeadIsNeverCoveredButLaggedQueryIs() throws {
        let analyzer = try makeAnalyzer()
        defer { analyzer.finish() }

        // Completed 0.5s windows at 0.25s hops, up to a 1.0s read head — the
        // best case the analyzer can ever offer: analysis fully caught up.
        analyzer.record(startSeconds: 0, endSeconds: 0.5, confidence: 0.2, musicConfidence: 0.9)
        analyzer.record(startSeconds: 0.25, endSeconds: 0.75, confidence: 0.2, musicConfidence: 0.9)
        analyzer.record(startSeconds: 0.5, endSeconds: 1.0, confidence: 0.2, musicConfidence: 0.9)

        let readHead = frames(1.0)

        // Old query semantics: the head equals the newest window's upperBound,
        // and a half-open range can never contain it — nil on every buffer.
        XCTAssertNil(analyzer.classification(atFramePosition: readHead),
                     "The live read head must not be covered by any completed window")
        XCTAssertNil(analyzer.speechConfidence(atFramePosition: readHead))

        // Lagged query lands inside completed coverage.
        let lagged = readHead - analyzer.queryLagFrames
        let classification = try XCTUnwrap(analyzer.classification(atFramePosition: lagged))
        XCTAssertEqual(classification.music, 0.9, accuracy: 0.0001)
        XCTAssertEqual(classification.speech, 0.2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(analyzer.speechConfidence(atFramePosition: lagged)), 0.2, accuracy: 0.0001)
    }

    func testQueryLagCoversOneWindowPlusOneHop() throws {
        let analyzer = try makeAnalyzer()
        defer { analyzer.finish() }

        // 0.5s window + 0.25s hop (overlapFactor 0.5) = 0.75s.
        XCTAssertEqual(analyzer.queryLagFrames, frames(0.75))
    }

    func testStoredRangesAlignWithTheAudioTheyDescribe() throws {
        let analyzer = try makeAnalyzer()
        defer { analyzer.finish() }

        analyzer.record(startSeconds: 1.0, endSeconds: 1.5, confidence: 0.8, musicConfidence: 0.1)

        XCTAssertNotNil(analyzer.classification(atFramePosition: frames(1.0)), "Window start is covered (inclusive)")
        XCTAssertNotNil(analyzer.classification(atFramePosition: frames(1.25)))
        XCTAssertNil(analyzer.classification(atFramePosition: frames(1.5)), "Window end is exclusive")
        XCTAssertNil(analyzer.classification(atFramePosition: frames(0.99)), "Audio before the window has no coverage")
    }

    func testFreshestOverlappingResultWins() throws {
        let analyzer = try makeAnalyzer()
        defer { analyzer.finish() }

        // Overlapping windows: the later (freshest) result covering the query wins.
        analyzer.record(startSeconds: 0, endSeconds: 0.5, confidence: 0.9, musicConfidence: 0.1)
        analyzer.record(startSeconds: 0.25, endSeconds: 0.75, confidence: 0.1, musicConfidence: 0.9)

        let classification = try XCTUnwrap(analyzer.classification(atFramePosition: frames(0.3)))
        XCTAssertEqual(classification.music, 0.9, accuracy: 0.0001)
    }

    func testSpeechDetectedInRangeUsesOverlapNotContainment() throws {
        let analyzer = try makeAnalyzer()
        defer { analyzer.finish() }

        analyzer.record(startSeconds: 0.5, endSeconds: 1.0, confidence: 0.85, musicConfidence: 0.05)

        // The retrospective trim veto queries whole gap ranges; a window merely
        // overlapping the gap must count.
        XCTAssertEqual(analyzer.speechDetected(inFrameRange: frames(0.9) ..< frames(2.0), aboveConfidence: 0.5), true)
        XCTAssertEqual(analyzer.speechDetected(inFrameRange: frames(0.9) ..< frames(2.0), aboveConfidence: 0.9), false)
        XCTAssertNil(analyzer.speechDetected(inFrameRange: frames(2.0) ..< frames(3.0), aboveConfidence: 0.5),
                     "No coverage at all must be nil so the caller does not veto")
    }
}
