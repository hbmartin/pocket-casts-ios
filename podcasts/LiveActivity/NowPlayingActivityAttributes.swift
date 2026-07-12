import ActivityKit
import Foundation

/// Attributes for the Now Playing Live Activity (lock screen + Dynamic Island).
/// Shared between the app (which starts/updates the activity) and the widget
/// extension (which renders it). One activity spans a whole listening session,
/// so everything episode-specific lives in `ContentState` — a track change is
/// an update, not a new activity.
nonisolated struct NowPlayingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var episodeTitle: String
        var podcastName: String
        var chapterTitle: String?
        var isPlaying: Bool
        /// Playback position captured at `capturedAt`; while playing, views
        /// project forward from here with timer-interval text so the system
        /// animates progress without per-second updates.
        var position: TimeInterval
        var duration: TimeInterval
        var capturedAt: Date
        /// File name (inside the shared app-group container) of the current
        /// episode's downscaled artwork; nil when no artwork is cached yet.
        var artworkFileName: String?
    }
}

/// Shared location for the Live Activity artwork inside the app-group container.
nonisolated enum NowPlayingActivityArtwork {
    static func containerURL(groupId: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("live_activity", isDirectory: true)
    }
}
