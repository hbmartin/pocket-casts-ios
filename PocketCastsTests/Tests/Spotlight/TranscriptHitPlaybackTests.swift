import Foundation
import PocketCastsDataModel
import XCTest

@testable import podcasts

@MainActor
final class TranscriptHitPlaybackTests: XCTestCase {
    func testProvidedHitMapsThroughItsEpisode() {
        var mappedEpisodeUuid: String?
        let result = TranscriptHitPlayback.resolvedSeekTime(
            episodeUuid: "episode-a",
            startTime: 42,
            source: .provided,
            isNowPlaying: { $0 == "episode-a" },
            isFingerprintActive: { true },
            playbackTime: { time, episodeUuid in
                mappedEpisodeUuid = episodeUuid
                return time + 8
            }
        )

        XCTAssertEqual(result, 50)
        XCTAssertEqual(mappedEpisodeUuid, "episode-a")
    }

    func testTrackSwitchBeforeLookupCannotUseAnotherEpisodesMapping() {
        var nowPlayingEpisodeUuid = "episode-a"
        var mappedEpisodeUuid: String?
        let result = TranscriptHitPlayback.resolvedSeekTime(
            episodeUuid: "episode-a",
            startTime: 42,
            source: .provided,
            isNowPlaying: { episodeUuid in
                guard episodeUuid == nowPlayingEpisodeUuid else { return false }
                nowPlayingEpisodeUuid = "episode-b"
                return true
            },
            isFingerprintActive: { true },
            playbackTime: { time, episodeUuid in
                mappedEpisodeUuid = episodeUuid
                return episodeUuid == nowPlayingEpisodeUuid ? time + 100 : nil
            }
        )

        XCTAssertEqual(mappedEpisodeUuid, "episode-a")
        XCTAssertEqual(result, 42, "the stale hit must retain its reference time rather than use episode-b's mapping")
    }

    func testGeneratedHitNeverUsesFingerprintMapping() {
        var requestedMapping = false
        let result = TranscriptHitPlayback.resolvedSeekTime(
            episodeUuid: "episode-a",
            startTime: 42,
            source: .generated,
            isNowPlaying: { _ in true },
            isFingerprintActive: { true },
            playbackTime: { _, _ in
                requestedMapping = true
                return 100
            }
        )

        XCTAssertEqual(result, 42)
        XCTAssertFalse(requestedMapping)
    }
}
