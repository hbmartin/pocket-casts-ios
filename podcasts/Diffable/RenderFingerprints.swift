import Foundation
import PocketCastsDataModel
import UIKit

// Render fingerprints hash exactly the fields the list cells display. Item
// identity in the diffable snapshots is the uuid alone; when a uuid survives a
// refresh but its fingerprint changed, the row is reconfigured in place instead
// of deleted and reinserted (which would drop selection and swipe state).

extension ListEpisode {
    /// Fields EpisodeCell renders for downloaded podcast episodes.
    nonisolated var renderFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(episode.title)
        hasher.combine(episode.episodeStatus)
        hasher.combine(episode.autoDownloadStatus)
        hasher.combine(episode.playingStatus)
        hasher.combine(episode.playedUpTo)
        hasher.combine(episode.duration)
        hasher.combine(episode.publishedDate)
        hasher.combine(episode.episodeNumber)
        hasher.combine(episode.seasonNumber)
        hasher.combine(episode.episodeType)
        hasher.combine(episode.fileType)
        hasher.combine(episode.archived)
        hasher.combine(episode.wasDeleted)
        hasher.combine(episode.playbackErrorDetails)
        hasher.combine(episode.downloadErrorDetails)
        hasher.combine(episode.keepEpisode)
        hasher.combine(episode.sizeInBytes)
        hasher.combine(episode.lastDownloadAttemptDate)
        hasher.combine(tintColor)
        return hasher.finalize()
    }
}

extension UserEpisode {
    /// The UserEpisode fields EpisodeCell renders on the Files screen.
    /// Bookmark state is supplied by the background refresh so checking the
    /// bookmark store does not add work to the MainActor snapshot apply.
    nonisolated func renderFingerprint(hasBookmarks: Bool) -> Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(episodeStatus)
        hasher.combine(autoDownloadStatus)
        hasher.combine(playingStatus)
        hasher.combine(playedUpTo)
        hasher.combine(duration)
        hasher.combine(publishedDate)
        hasher.combine(fileType)
        hasher.combine(archived)
        hasher.combine(wasDeleted)
        hasher.combine(playbackErrorDetails)
        hasher.combine(downloadErrorDetails)
        hasher.combine(keepEpisode)
        hasher.combine(sizeInBytes)
        hasher.combine(uploadStatus)
        hasher.combine(imageUrl)
        hasher.combine(imageModified)
        hasher.combine(imageColor)
        hasher.combine(hasCustomImage)
        hasher.combine(hasBookmarks)
        return hasher.finalize()
    }
}

extension Podcast {
    /// The Podcast fields the folder grid/list cells render (artwork is keyed
    /// off the uuid, which is the item identity).
    nonisolated var renderFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(author)
        hasher.combine(cachedUnreadCount)
        hasher.combine(isPaid)
        hasher.combine(backgroundColor)
        hasher.combine(detailColor)
        hasher.combine(primaryColor)
        hasher.combine(secondaryColor)
        hasher.combine(colorVersion)
        hasher.combine(imageURL)
        hasher.combine(thumbnailStatus)
        return hasher.finalize()
    }
}
