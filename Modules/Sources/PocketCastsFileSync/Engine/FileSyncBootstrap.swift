import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Union-join: when this device first joins a sync folder (or switches
/// folders), it seeds its full local library into the journal as ops with
/// historical timestamps, so LWW merging unions both sides — nothing on
/// either side is lost, and genuinely newer remote edits still win.
struct FileSyncBootstrap {
    let dataManager: DataManager

    func seedLocalState() {
        let now = DBUtils.currentUTCTimeInMillis()
        // Enable-time minus a small epsilon so a real remote edit at the
        // same wall-clock instant wins ties against seeded state.
        let fallback = now - 1

        for podcast in dataManager.allPodcasts(includeUnsubscribed: false) {
            let stamp = podcast.addedDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? fallback
            dataManager.seedFileSyncJournal(
                entityType: .podcast, uuid: podcast.uuid, changedFields: [], wallClockMs: stamp)
        }

        // Episodes still carrying *Modified stamps (the same predicate
        // server sync pushes from). Episodes whose stamps a past server
        // push zeroed re-seed naturally the next time they're touched.
        for episode in dataManager.unsyncedEpisodes(limit: 10000) {
            var fields: [String] = []
            if episode.playedUpToModified > 0 { fields.append("playedUpTo") }
            if episode.playingStatusModified > 0 { fields.append("playingStatus") }
            if episode.archivedModified > 0 { fields.append("archived") }
            if episode.keepEpisodeModified > 0 { fields.append("starred") }
            if episode.durationModified > 0 { fields.append("duration") }
            guard !fields.isEmpty else { continue }
            let stamp = max(episode.playedUpToModified, episode.playingStatusModified,
                            episode.archivedModified, episode.keepEpisodeModified)
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
