import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

extension PodcastManager {
    func deletePodcastIfUnused(_ podcast: Podcast) async {
        // we don't delete podcasts that haven't been synced or you're still subscribed to
        if podcast.syncStatus == SyncStatus.notSynced.rawValue || podcast.isSubscribed() { return }

        // we don't delete podcasts added to the phone in the last week. This is to prevent stuff you just leave open in discover from being removed
        if let addedDate = podcast.addedDate, abs(addedDate.timeIntervalSinceNow) < 1.week { return }

        // we don't delete podcasts which have any episodes in a playlist or Up Next
        if dataManager.playlistContainsPodcast(podcastUuid: podcast.uuid) { return }

        let interactedEpisodes = dataManager.allEpisodesForPodcast(id: podcast.id).filter { $0.userHasInteractedWithEpisode() }

        // we can safely delete podcasts where the user hasn't interacted with any of the episodes
        if interactedEpisodes.isEmpty {
            let episodes = dataManager.allEpisodesForPodcast(id: podcast.id)
            await downloadManager.cancelTasks(for: episodes)

            // Delete all the episodes for the podcast that we're deleting
            dataManager.deleteAllEpisodesInPodcast(podcastId: podcast.id)
            dataManager.delete(podcast: podcast)
            PodcastExistsHelper.shared.invalidate(uuid: podcast.uuid)
        }
    }

    func deleteGhostEpisodesIfNeeded() {
        let episodes = dataManager.findGhostEpisodes()
        guard !episodes.isEmpty else {
            return
        }

        FileLog.shared.addMessage("Found \(episodes.count) Ghost Episodes")

        var deleted_count = 0
        var uuids: [String] = []

        episodes.forEach { episode in
            guard
                !episode.uuid.isEmpty,
                episode.userHasInteractedWithEpisode() == false
            else {
                return
            }

            uuids.append("'\(episode.uuid)'")
            deleted_count += 1
        }

        DataManager.sharedManager.deleteGhostsEpisodes(uuids: uuids)
        FileLog.shared.addMessage("Deleted \(deleted_count) Ghost Episodes")
    }

    func checkForUnusedPodcasts() async {
        let podcasts = dataManager.allUnsubscribedPodcasts()
        for podcast in podcasts {
            await deletePodcastIfUnused(podcast)
        }
    }

    func checkForExpiredPodcastsAndCleanup() {
    }
}
