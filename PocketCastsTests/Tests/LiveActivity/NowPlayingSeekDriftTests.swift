import XCTest

@testable import podcasts

/// The Live Activity has no seek notification: `NowPlayingLiveActivityManager`
/// detects seeks by comparing the actual position against the last pushed
/// content state's wall-clock projection (review finding P2-7). These pin the
/// pure projection math in `isSeekDrift` — ordinary playback ticks must stay
/// inside the threshold (no periodic activity updates) while a jump re-anchors.
final class NowPlayingSeekDriftTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_752_000_000)

    private func state(isPlaying: Bool = true, position: TimeInterval = 100, rate: Double? = 1) -> NowPlayingActivityAttributes.ContentState {
        NowPlayingActivityAttributes.ContentState(
            episodeTitle: "Episode",
            podcastName: "Podcast",
            chapterTitle: nil,
            isPlaying: isPlaying,
            position: position,
            duration: 3600,
            capturedAt: anchor,
            playbackRate: rate,
            artworkFileName: nil
        )
    }

    func testOrdinaryPlaybackTickIsNotDrift() {
        // 10 wall seconds after capture at 1x, playback should sit near 110.
        let drifted = NowPlayingLiveActivityManager.isSeekDrift(
            state: state(),
            currentTime: 111,
            now: anchor.addingTimeInterval(10)
        )
        XCTAssertFalse(drifted, "sub-threshold timer jitter must not trigger activity updates")
    }

    func testSeekBeyondThresholdIsDrift() {
        XCTAssertTrue(NowPlayingLiveActivityManager.isSeekDrift(
            state: state(),
            currentTime: 300, // user jumped ahead
            now: anchor.addingTimeInterval(10)
        ))
        XCTAssertTrue(NowPlayingLiveActivityManager.isSeekDrift(
            state: state(),
            currentTime: 40, // user jumped back
            now: anchor.addingTimeInterval(10)
        ))
    }

    func testProjectionScalesWithPlaybackRate() {
        // At 2x, 10 wall seconds advance playback ~20s: 120 is on-projection...
        XCTAssertFalse(NowPlayingLiveActivityManager.isSeekDrift(
            state: state(rate: 2),
            currentTime: 120,
            now: anchor.addingTimeInterval(10)
        ))
        // ...while the 1x projection (110) would be 10s off — the rate must
        // participate or every fast-playback tick reads as a seek.
        XCTAssertTrue(NowPlayingLiveActivityManager.isSeekDrift(
            state: state(rate: 1),
            currentTime: 120,
            now: anchor.addingTimeInterval(10)
        ))
    }

    func testNilRateProjectsAtOneTimes() {
        // States encoded before the field existed decode with nil = 1x.
        XCTAssertFalse(NowPlayingLiveActivityManager.isSeekDrift(
            state: state(rate: nil),
            currentTime: 110,
            now: anchor.addingTimeInterval(10)
        ))
    }

    func testPausedProjectionStaysFrozen() {
        // Paused: the projection holds at the captured position no matter how
        // much wall time passes...
        XCTAssertFalse(NowPlayingLiveActivityManager.isSeekDrift(
            state: state(isPlaying: false),
            currentTime: 100,
            now: anchor.addingTimeInterval(600)
        ))
        // ...so a scrub while paused still reads as drift.
        XCTAssertTrue(NowPlayingLiveActivityManager.isSeekDrift(
            state: state(isPlaying: false),
            currentTime: 200,
            now: anchor.addingTimeInterval(600)
        ))
    }
}
