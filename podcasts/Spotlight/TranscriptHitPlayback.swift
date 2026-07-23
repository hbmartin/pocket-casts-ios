import Foundation
import PocketCastsDataModel

/// The canonical seek-time mapping for a transcript search hit, shared by the
/// New Search result row and the Siri intent.
///
/// Provided-corpus segments indexed from a server-generated transcript carry
/// reference-timeline times; when the hit's episode is the actively
/// fingerprinted now-playing episode the time is mapped onto the local audio.
/// For any other episode no mapping exists at seek time, so the indexed time is
/// the best available (an inherent limitation — dynamic-ad offsets can shift
/// the landing spot there).
@MainActor
enum TranscriptHitPlayback {
    static func seekTime(episodeUuid: String, startTime: TimeInterval, source: PocketCastsDataModel.TranscriptSource) -> TimeInterval {
        resolvedSeekTime(
            episodeUuid: episodeUuid,
            startTime: startTime,
            source: source,
            isNowPlaying: { PlaybackManager.shared.isNowPlayingEpisode(episodeUuid: $0) },
            isFingerprintActive: {
                if case .active = FingerprintTimingManager.shared.state {
                    return true
                }
                return false
            },
            playbackTime: {
                FingerprintTimingManager.shared.playbackTime(forReferenceTime: $0, episodeUuid: $1)
            }
        )
    }

    static func resolvedSeekTime(
        episodeUuid: String,
        startTime: TimeInterval,
        source: PocketCastsDataModel.TranscriptSource,
        isNowPlaying: (String) -> Bool,
        isFingerprintActive: () -> Bool,
        playbackTime: (TimeInterval, String) -> TimeInterval?
    ) -> TimeInterval {
        guard source == .provided,
              isNowPlaying(episodeUuid),
              isFingerprintActive(),
              let mapped = playbackTime(startTime, episodeUuid) else {
            return startTime
        }
        return mapped
    }

    /// Seeks-and-plays via the canonical deep-link path (loads the episode
    /// first when it isn't the one now playing). Returns the seconds played from.
    @discardableResult
    static func play(episodeUuid: String, podcastUuid: String?, startTime: TimeInterval, source: PocketCastsDataModel.TranscriptSource) -> TimeInterval {
        let seconds = seekTime(episodeUuid: episodeUuid, startTime: startTime, source: source)
        PlaybackManager.shared.play(episodeUuid: episodeUuid, podcastUuid: podcastUuid, at: seconds)
        return seconds
    }
}
