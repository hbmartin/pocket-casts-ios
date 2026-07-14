import XCTest

@testable import podcasts

/// Timeline handling for Catch Me Up (review finding P2-17): `playedUpTo` is a
/// playback-timeline value, but non-local transcript cues live on the reference
/// timeline. The recap's cue filter must convert through the fingerprint
/// alignment when one is active — and only then.
final class CatchMeUpViewModelTests: XCTestCase {
    func testNonLocalTranscriptWithActiveTimingMapsToReferenceTime() {
        let result = CatchMeUpViewModel.effectivePlayedUpTo(
            1_000,
            isLocalTranscript: false,
            isTimingActive: true,
            referenceTime: { playbackTime in playbackTime - 90 } // 90s of dynamic ads played
        )

        XCTAssertEqual(result, 910, "Reference-timeline cues must be filtered against the mapped position")
    }

    func testLocalTranscriptUsesRawPlaybackTime() {
        var mapperCalled = false
        let result = CatchMeUpViewModel.effectivePlayedUpTo(
            1_000,
            isLocalTranscript: true,
            isTimingActive: true,
            referenceTime: { _ in
                mapperCalled = true
                return 0
            }
        )

        XCTAssertEqual(result, 1_000, "Local transcripts are cut from the played audio and align natively")
        XCTAssertFalse(mapperCalled)
    }

    func testInactiveTimingFallsBackToRawComparison() {
        let result = CatchMeUpViewModel.effectivePlayedUpTo(
            1_000,
            isLocalTranscript: false,
            isTimingActive: false,
            referenceTime: { _ in 0 }
        )

        XCTAssertEqual(result, 1_000)
    }

    func testUnavailableMappingFallsBackToRawComparison() {
        // Active state but no mapping for this episode (e.g. the alignment
        // belongs to a different episode): the episode-bound lookup returns nil.
        let result = CatchMeUpViewModel.effectivePlayedUpTo(
            1_000,
            isLocalTranscript: false,
            isTimingActive: true,
            referenceTime: { _ in nil }
        )

        XCTAssertEqual(result, 1_000)
    }
}
