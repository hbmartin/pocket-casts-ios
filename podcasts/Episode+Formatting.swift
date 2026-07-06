import Foundation
import PocketCastsDataModel

nonisolated extension Episode {
    func shortLastPlaybackInteractionDate() -> String {
        shortDateFor(date: lastPlaybackInteractionDate)
    }

    func shouldArchiveOnCompletion() -> Bool {
        #if !APPCLIP
        if let podcast = parentPodcast(), podcast.isAutoArchiveOverridden {
            return podcast.autoArchivePlayedAfterTime == 0 && (Settings.archiveStarredEpisodes() || !keepEpisode)
        }

        return Settings.autoArchivePlayedAfter() == 0 && (Settings.archiveStarredEpisodes() || !keepEpisode)
        #else
        return false
        #endif
    }

    func userHasInteractedWithEpisode() -> Bool {
        keepEpisode || archived || downloaded(pathFinder: DownloadManager.shared) || !unplayed() || PlaybackManager.episodeIsInUpNext(uuid: uuid) || lastPlaybackInteractionDate != nil
    }

    func episodeCanBeCleanedUp() -> Bool {
        !keepEpisode &&
        !downloaded(pathFinder: DownloadManager.shared) &&
        !inProgress() &&
        !PlaybackManager.episodeIsInUpNext(uuid: uuid) &&
        !DataManager.sharedManager.playlistContainsEpisode(episodeUuid: uuid)
    }

    public func subTitle() -> String {
        parentPodcast()?.title ?? ""
    }
}
