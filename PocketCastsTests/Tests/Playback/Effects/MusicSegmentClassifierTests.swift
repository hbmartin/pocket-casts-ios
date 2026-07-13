import XCTest

@testable import podcasts

/// The hysteresis state machine behind adaptive effects switching (Item 14):
/// enter/exit sustain windows, blip rejection, nil-coverage behavior and seeks.
final class MusicSegmentClassifierTests: XCTestCase {
    private func makeClassifier() -> MusicSegmentClassifier {
        MusicSegmentClassifier(parameters: .init(musicConfidenceThreshold: 0.7, enterSustain: 5, exitSustain: 3))
    }

    /// Feeds a music-dominant observation each second from `from` to `to`.
    private func feedMusic(_ classifier: inout MusicSegmentClassifier, from: TimeInterval, to: TimeInterval) -> Bool {
        var changed = false
        var time = from
        while time <= to {
            changed = classifier.analyze(speechConfidence: 0.1, musicConfidence: 0.9, at: time) || changed
            time += 1
        }
        return changed
    }

    private func feedSpeech(_ classifier: inout MusicSegmentClassifier, from: TimeInterval, to: TimeInterval) -> Bool {
        var changed = false
        var time = from
        while time <= to {
            changed = classifier.analyze(speechConfidence: 0.9, musicConfidence: 0.1, at: time) || changed
            time += 1
        }
        return changed
    }

    func testEntersAfterSustainedMusic() {
        var classifier = makeClassifier()

        XCTAssertFalse(feedMusic(&classifier, from: 0, to: 4), "4 seconds is under the 5s enter sustain")
        XCTAssertFalse(classifier.isMusicActive)

        XCTAssertTrue(feedMusic(&classifier, from: 5, to: 6))
        XCTAssertTrue(classifier.isMusicActive)
    }

    func testBriefMusicStingDoesNotEnter() {
        var classifier = makeClassifier()

        _ = feedMusic(&classifier, from: 0, to: 3)
        _ = feedSpeech(&classifier, from: 4, to: 5)
        _ = feedMusic(&classifier, from: 6, to: 9)

        XCTAssertFalse(classifier.isMusicActive, "Interrupted streaks must restart the sustain window")
    }

    func testExitsAfterSustainedSpeechAndReportsDuration() {
        var classifier = makeClassifier()
        _ = feedMusic(&classifier, from: 0, to: 6)
        XCTAssertTrue(classifier.isMusicActive)

        XCTAssertFalse(feedSpeech(&classifier, from: 7, to: 9), "2 seconds is under the 3s exit sustain")
        XCTAssertTrue(classifier.isMusicActive)

        XCTAssertTrue(feedSpeech(&classifier, from: 10, to: 11))
        XCTAssertFalse(classifier.isMusicActive)
        XCTAssertEqual(classifier.endedSegmentDuration ?? -1, 7, accuracy: 0.01,
                       "Segment ran from the enter streak start (0) to the exit streak start (7)")
    }

    func testNilCoverageHoldsStateAndResetsStreaks() {
        var classifier = makeClassifier()
        _ = feedMusic(&classifier, from: 0, to: 6)
        XCTAssertTrue(classifier.isMusicActive)

        // Stale/no-coverage observations never flip the state...
        for time in stride(from: 7.0, through: 30, by: 1) {
            XCTAssertFalse(classifier.analyze(speechConfidence: nil, musicConfidence: nil, at: time))
        }
        XCTAssertTrue(classifier.isMusicActive)

        // ...and they reset a pending exit streak.
        _ = feedSpeech(&classifier, from: 31, to: 32)
        _ = classifier.analyze(speechConfidence: nil, musicConfidence: nil, at: 33)
        XCTAssertFalse(feedSpeech(&classifier, from: 34, to: 36), "The exit streak restarted after the gap")
        XCTAssertTrue(classifier.isMusicActive)
    }

    func testLoudSpeechOverMusicDoesNotEnter() {
        var classifier = makeClassifier()
        var changed = false
        for time in stride(from: 0.0, through: 10, by: 1) {
            // Music above threshold but speech dominates: talking over a bed.
            changed = classifier.analyze(speechConfidence: 0.95, musicConfidence: 0.75, at: time) || changed
        }
        XCTAssertFalse(changed)
        XCTAssertFalse(classifier.isMusicActive)
    }

    func testSeekBackwardsRestartsStreak() {
        var classifier = makeClassifier()
        _ = feedMusic(&classifier, from: 100, to: 103)

        // A rewind mid-streak must not produce a negative span or instant flip.
        XCTAssertFalse(classifier.analyze(speechConfidence: 0.1, musicConfidence: 0.9, at: 50))
        XCTAssertFalse(feedMusic(&classifier, from: 51, to: 54))
        XCTAssertTrue(feedMusic(&classifier, from: 55, to: 56))
        XCTAssertTrue(classifier.isMusicActive)
    }

    func testResetClearsEverything() {
        var classifier = makeClassifier()
        _ = feedMusic(&classifier, from: 0, to: 6)
        XCTAssertTrue(classifier.isMusicActive)

        classifier.reset()

        XCTAssertFalse(classifier.isMusicActive)
        XCTAssertNil(classifier.endedSegmentDuration)
    }
}
