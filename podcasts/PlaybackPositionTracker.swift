import Foundation
import PocketCastsDataModel

/// Owns the transient (between-DB-saves) playback position of the current episode
/// (Phase 5, docs/Phase5-PlaybackModernization.md D4).
///
/// Before this existed, `PlaybackManager.progressTimerFired` mutated
/// `episode.playedUpTo` in place every second, making the shared `Episode` instance
/// the liveness channel for the playing position. The tracker is that channel now:
/// per-tick position lands here, the database still gets the periodic
/// `recordPlaybackPosition` save, and readers combine both via `playedUpTo(for:)`.
/// This removes the last in-place shared-mutation dependency standing between
/// `Episode`/`UserEpisode` and value semantics.
@MainActor
final class PlaybackPositionTracker {
    private var episodeUuid: String?
    private var transientPosition: TimeInterval?

    /// Records the per-second position tick for the episode currently playing.
    func tick(upTo: TimeInterval, episodeUuid: String) {
        switchEpisodeIfNeeded(to: episodeUuid)
        transientPosition = upTo
    }

    /// Forces the tracked position (e.g. restarting a played episode from zero).
    func overridePosition(_ position: TimeInterval, episodeUuid: String) {
        switchEpisodeIfNeeded(to: episodeUuid)
        transientPosition = position
    }

    /// The freshest known position for `episode`: the transient tick value when the
    /// tracker is following that episode, otherwise the episode's stored value.
    func playedUpTo(for episode: BaseEpisode) -> TimeInterval {
        guard episode.uuid == episodeUuid, let transientPosition else {
            return episode.playedUpTo
        }
        return transientPosition
    }

    private func switchEpisodeIfNeeded(to uuid: String) {
        if uuid != episodeUuid {
            episodeUuid = uuid
            transientPosition = nil
        }
    }
}
