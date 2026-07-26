import Foundation
import PocketCastsDataModel
import UIKit

// Render fingerprints hash exactly the fields the list cells display. Item
// identity in the diffable snapshots is the uuid alone; when a uuid survives a
// refresh but its fingerprint changed, the row is reconfigured in place instead
// of deleted and reinserted (which would drop selection and swipe state).

extension ListEpisode {
    /// Mirrors handleIsEqual: the fields EpisodeCell renders.
    var renderFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(episode.title)
        hasher.combine(episode.episodeStatus)
        hasher.combine(episode.playingStatus)
        hasher.combine(episode.playedUpTo)
        hasher.combine(episode.duration)
        hasher.combine(episode.archived)
        hasher.combine(episode.playbackErrorDetails)
        hasher.combine(episode.keepEpisode)
        hasher.combine(episode.sizeInBytes)
        hasher.combine(tintColor)
        return hasher.finalize()
    }
}

extension UserEpisode {
    /// The UserEpisode fields EpisodeCell renders on the Files screen.
    var renderFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(episodeStatus)
        hasher.combine(playingStatus)
        hasher.combine(playedUpTo)
        hasher.combine(duration)
        hasher.combine(archived)
        hasher.combine(playbackErrorDetails)
        hasher.combine(keepEpisode)
        hasher.combine(sizeInBytes)
        hasher.combine(uploadStatus)
        hasher.combine(imageColor)
        return hasher.finalize()
    }
}

extension Podcast {
    /// The Podcast fields the folder grid/list cells render (artwork is keyed
    /// off the uuid, which is the item identity).
    var renderFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(cachedUnreadCount)
        return hasher.finalize()
    }
}
