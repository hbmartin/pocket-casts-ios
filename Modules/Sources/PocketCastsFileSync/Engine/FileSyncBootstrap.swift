import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Union-join seeding for the first time this device joins a sync folder:
/// writes existing local library state into the journal with historical
/// stamps so local and remote folders merge without either side winning
/// merely because it joined later.
struct FileSyncBootstrap {
    let dataManager: DataManager

    func seedLocalState() {
        let now = FileSyncClock.currentUTCTimeInMillis()
        let fallback = now - 1

        for podcast in dataManager.allPodcasts(includeUnsubscribed: false) {
            let stamp = podcast.addedDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? fallback
            dataManager.seedFileSyncJournal(
                entityType: .podcast, uuid: podcast.uuid, changedFields: [], wallClockMs: stamp)
        }

        for episode in dataManager.unsyncedEpisodes(limit: 10000) {
            var fields: [String] = []
            if episode.playedUpToModified > 0 { fields.append("playedUpTo") }
            if episode.playingStatusModified > 0 { fields.append("playingStatus") }
            if episode.archivedModified > 0 { fields.append("archived") }
            if episode.keepEpisodeModified > 0 { fields.append("starred") }
            if episode.durationModified > 0 { fields.append("duration") }
            guard !fields.isEmpty else { continue }
            let stamp = max(
                episode.playedUpToModified,
                episode.playingStatusModified,
                episode.archivedModified,
                episode.keepEpisodeModified,
                episode.durationModified)
            dataManager.seedFileSyncJournal(
                entityType: .episode, uuid: episode.uuid, changedFields: fields,
                wallClockMs: stamp > 0 ? stamp : fallback)
        }

        for playlist in dataManager.allPlaylists(includeDeleted: false) {
            dataManager.seedFileSyncJournal(
                entityType: .playlist, uuid: playlist.uuid, changedFields: [], wallClockMs: fallback)
        }

        for folder in dataManager.allFolders(includeDeleted: false) {
            dataManager.seedFileSyncJournal(
                entityType: .folder, uuid: folder.uuid, changedFields: [], wallClockMs: fallback)
        }

        for bookmark in dataManager.bookmarks.allBookmarks(includeDeleted: false) {
            dataManager.seedFileSyncJournal(
                entityType: .bookmark, uuid: bookmark.uuid, changedFields: [],
                wallClockMs: Int64(bookmark.created.timeIntervalSince1970 * 1000))
        }

        for episode in dataManager.allFolderBackedUserEpisodes() where episode.identity == .canonical {
            dataManager.seedFileSyncJournal(
                entityType: .userEpisode, uuid: episode.uuid,
                changedFields: ["uploadIdentity"], wallClockMs: fallback)
        }

        let queue = dataManager.allUpNextEpisodes().map(\.uuid)
        if !queue.isEmpty {
            dataManager.seedFileSyncUpNextReplace(episodeUuids: queue, wallClockMs: fallback)
        }

        FileLog.shared.addMessage("FileSync: union-join seed journaled")
    }
}
