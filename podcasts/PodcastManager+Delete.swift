import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

extension PodcastManager {
    func unsubscribe(podcast: Podcast) {
        var podcast = podcast
        let savedFolderUuid = podcast.folderUuid

        if isLoggedIn() {
            let episodes = dataManager.allEpisodesForPodcast(id: podcast.id)
            for episode in episodes {
                EpisodeManager.deleteDownloadedFiles(episode: episode)
            }

            // if the user has signed in, there's a cleanup task (PodcastManager.deletePodcastIfUnused) that will run later to remove episodes they haven't interacted but we do some basic cleanup here
            // eg: remove downloaded/queued episodes and remove any that are in Up Next
            podcast.folderUuid = nil
            podcast.subscribed = 0
            podcast.autoArchiveEpisodeLimit = 0
            podcast.autoDownloadSetting = AutoDownloadSetting.off.rawValue
            podcast.isPushEnabled = false
            podcast.syncStatus = SyncStatus.notSynced.rawValue
            podcast.autoAddToUpNext = AutoAddToUpNextSetting.off.rawValue
            podcast.settings = PodcastSettings.defaults
            dataManager.save(podcast: podcast)
        } else {
            // if they aren't signed in, just blow it all away
            EpisodeManager.deleteAllEpisodesInPodcast(id: podcast.id)
            dataManager.delete(podcast: podcast)

            // only drop private-feed credentials with the row itself; the signed-in branch
            // keeps the row (subscribed = 0), so a resubscribe must still find them
            if podcast.feedRefreshSource == .localFeed {
                LocalFeedCredentials.delete(podcastUuid: podcast.uuid)
            }
        }
        PodcastExistsHelper.shared.invalidate(uuid: podcast.uuid)

        PlaylistManager.handlePodcastUnsubscribed(podcastUuid: podcast.uuid)

        // additionally if this podcast was in a folder, update the folder
        if let folderUuid = savedFolderUuid {
            dataManager.updateFolderSyncModified(folderUuid: folderUuid, syncModified: TimeFormatter.currentUTCTimeInMillis())
            NotificationCenter.postOnMainThread(FolderChanged(uuid: folderUuid))
        }

        NotificationCenter.postOnMainThread(PodcastDeleted(uuid: podcast.uuid))
    }
}
