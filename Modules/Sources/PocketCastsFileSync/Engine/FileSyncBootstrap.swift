import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Union-join seeding for the first time this device joins a sync folder:
/// writes existing local library state into the journal with historical
/// stamps so local and remote folders merge without either side winning
/// merely because it joined later.
struct FileSyncBootstrap {
    let dataManager: DataManager
    /// Injectable clock so simulations control time; production uses the wall clock.
    var now: @Sendable () -> Int64 = FileSyncClock.currentUTCTimeInMillis

    private enum BootstrapError: Error, CustomStringConvertible {
        case seedJournalWriteFailed

        var description: String {
            "file-sync bootstrap seed journal write failed"
        }
    }

    func seedLocalState() throws {
        let nowMs = now()
        let fallback = nowMs - 1
        var seedEntries: [DataManager.SeedEntry] = []

        for podcast in dataManager.allPodcasts(includeUnsubscribed: false) {
            let stamp = podcast.addedDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? fallback
            seedEntries.append(DataManager.SeedEntry(
                entityType: .podcast, uuid: podcast.uuid, changedFields: [], wallClockMs: stamp))
        }

        for episode in dataManager.unsyncedEpisodesIncludingLocalFeed(limit: 10000) {
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
            seedEntries.append(DataManager.SeedEntry(
                entityType: .episode, uuid: episode.uuid, changedFields: fields,
                wallClockMs: stamp > 0 ? stamp : fallback))
        }

        for playlist in dataManager.allPlaylists(includeDeleted: false) {
            seedEntries.append(DataManager.SeedEntry(
                entityType: .playlist, uuid: playlist.uuid, changedFields: [], wallClockMs: fallback))
        }

        for folder in dataManager.allFolders(includeDeleted: false) {
            seedEntries.append(DataManager.SeedEntry(
                entityType: .folder, uuid: folder.uuid, changedFields: [], wallClockMs: fallback))
        }

        for bookmark in dataManager.bookmarks.allBookmarks(includeDeleted: false) {
            seedEntries.append(DataManager.SeedEntry(
                entityType: .bookmark, uuid: bookmark.uuid, changedFields: [],
                wallClockMs: Int64(bookmark.created.timeIntervalSince1970 * 1000)))
        }

        for episode in dataManager.allFolderBackedUserEpisodes() where episode.identity == .canonical {
            seedEntries.append(DataManager.SeedEntry(
                entityType: .userEpisode, uuid: episode.uuid,
                changedFields: ["uploadIdentity"], wallClockMs: fallback))
        }

        let queue = dataManager.allUpNextEpisodes().map(\.uuid)
        let upNextUuids = queue.isEmpty ? nil : queue

        guard dataManager.seedFileSyncJournalBatch(
            entries: seedEntries,
            upNextEpisodeUuids: upNextUuids,
            upNextWallClockMs: upNextUuids != nil ? fallback : nil) else {
            throw BootstrapError.seedJournalWriteFailed
        }

        FileLog.shared.addMessage("FileSync: union-join seed journaled")
    }
}
