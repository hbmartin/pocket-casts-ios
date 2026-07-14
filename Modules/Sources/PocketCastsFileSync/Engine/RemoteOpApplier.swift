import Foundation
import PocketCastsDataModel

/// Writes the merged folder consensus into the local database, mirroring
/// the server sync engine's import semantics: `saveIfNotModified` guards
/// protect newer local edits, the actively-playing episode wins locally,
/// and folder-derived writes run under file-sync journal suppression.
struct RemoteOpApplier {
    let dataManager: DataManager
    let delegate: (any FileSyncDelegate)?

    struct ApplyResult {
        var podcastsApplied = 0
        var episodesApplied = 0
        var playlistsApplied = 0
        var foldersApplied = 0
        var bookmarksApplied = 0
        var queueChanged = false
    }

    func apply(_ state: MergeEngine.MergedState) async -> ApplyResult {
        var result = ApplyResult()

        for (uuid, merged) in state.folders {
            applyFolder(uuid: uuid, merged.record)
            result.foldersApplied += 1
        }
        for (uuid, merged) in state.podcasts {
            await applyPodcast(uuid: uuid, merged.record)
            result.podcastsApplied += 1
        }
        for (uuid, merged) in state.episodes {
            await applyEpisode(uuid: uuid, merged.record)
            result.episodesApplied += 1
        }
        for (uuid, merged) in state.playlists {
            applyPlaylist(uuid: uuid, merged.record)
            result.playlistsApplied += 1
        }
        for (uuid, merged) in state.bookmarks {
            await applyBookmark(uuid: uuid, merged.record)
            result.bookmarksApplied += 1
        }
        if !state.upNextOps.isEmpty {
            result.queueChanged = await applyUpNext(UpNextMerger.replay(ops: state.upNextOps))
        }
        applySettings(state.settings)
        applyStats(state.statsByDevice)

        return result
    }

    // MARK: Podcasts

    private func applyPodcast(uuid: String, _ item: Api_SyncUserPodcast) async {
        if let existing = dataManager.findPodcast(uuid: uuid, includeUnsubscribed: true) {
            DataManager.withFileSyncApplySuppression {
                let updated = RecordConverters.apply(item, to: existing)
                _ = dataManager.save(podcast: updated)
            }
            return
        }

        guard item.hasSubscribed, item.subscribed.value else { return }
        let backfilled = await delegate?.backfillPodcast(
            uuid: uuid,
            feedURL: item.feedURL.isEmpty ? nil : item.feedURL) ?? false
        DataManager.withFileSyncApplySuppression {
            if backfilled, let added = dataManager.findPodcast(uuid: uuid, includeUnsubscribed: true) {
                var updated = RecordConverters.apply(item, to: added)
                updated.subscribed = 1
                _ = dataManager.save(podcast: updated)
            } else {
                var stub = Podcast()
                stub.uuid = uuid
                stub.addedDate = item.hasDateAdded ? item.dateAdded.date : Date()
                stub.subscribed = 1
                stub.title = item.feedURL.isEmpty ? uuid : item.feedURL
                var updated = RecordConverters.apply(item, to: stub)
                updated.podcastUrl = item.feedURL.isEmpty ? nil : item.feedURL
                _ = dataManager.save(podcast: updated)
            }
        }
    }

    // MARK: Episodes

    private func applyEpisode(uuid: String, _ item: Api_SyncUserEpisode) async {
        var episode = dataManager.findEpisode(uuid: uuid)
        if episode == nil, !item.podcastUuid.isEmpty {
            let backfilled = await delegate?.backfillEpisode(uuid: uuid, podcastUuid: item.podcastUuid) ?? false
            if backfilled {
                episode = dataManager.findEpisode(uuid: uuid)
            }
        }
        guard let episode else { return }

        let activelyPlaying = delegate?.isEpisodeActivelyPlaying(uuid: uuid) ?? false

        DataManager.withFileSyncApplySuppression {
            if item.hasStarred {
                _ = dataManager.saveIfNotModified(starred: item.starred.value, episodeUuid: uuid)
            }
            if item.hasIsDeleted {
                if activelyPlaying, item.isDeleted.value {
                    dataManager.saveEpisode(archived: false, episode: episode, updateSyncFlag: true)
                } else {
                    _ = dataManager.saveIfNotModified(archived: item.isDeleted.value, episodeUuid: uuid)
                }
            }
            if item.hasPlayingStatus {
                if activelyPlaying {
                    dataManager.saveEpisode(playingStatus: .inProgress, episode: episode, updateSyncFlag: true)
                } else if let status = PlayingStatus(rawValue: item.playingStatus.value) {
                    _ = dataManager.saveIfNotModified(playingStatus: status, episodeUuid: uuid)
                }
            }
            if item.hasPlayedUpTo, !activelyPlaying,
               item.playedUpToModified.value > episode.playedUpToModified {
                let position = Double(item.playedUpTo.value)
                dataManager.saveEpisode(playedUpTo: position, episode: episode, updateSyncFlag: false)
                if delegate?.isEpisodeInPlayer(uuid: uuid) == true {
                    delegate?.seekToFromSync(episodeUuid: uuid, time: position)
                }
            }
            if item.hasDuration, !activelyPlaying, item.duration.value > 0 {
                dataManager.saveEpisode(duration: Double(item.duration.value), episode: episode, updateSyncFlag: false)
            }
        }
    }

    // MARK: Playlists / folders

    private func applyPlaylist(uuid: String, _ item: Api_SyncUserPlaylist) {
        DataManager.withFileSyncApplySuppression {
            let key = item.originalUuid.isEmpty ? uuid : item.originalUuid
            if item.hasIsDeleted, item.isDeleted.value {
                if let playlist = dataManager.findPlaylist(uuid: key) {
                    dataManager.delete(playlist: playlist)
                }
                return
            }
            var playlist = dataManager.findPlaylist(uuid: key) ?? {
                var new = EpisodeFilter()
                new.uuid = key
                return new
            }()
            playlist = RecordConverters.apply(item, to: playlist)
            _ = dataManager.save(playlist: playlist)
        }
    }

    private func applyFolder(uuid: String, _ item: Api_SyncUserFolder) {
        DataManager.withFileSyncApplySuppression {
            if item.isDeleted {
                dataManager.delete(folderUuid: uuid, markAsDeleted: false)
                return
            }
            var folder = dataManager.findFolder(uuid: uuid) ?? {
                var new = Folder()
                new.uuid = uuid
                return new
            }()
            folder = RecordConverters.apply(item, to: folder)
            _ = dataManager.save(folder: folder)
        }
    }

    // MARK: Bookmarks

    private func applyBookmark(uuid: String, _ item: Api_SyncUserBookmark) async {
        let existing = dataManager.bookmarks.bookmark(for: uuid, allowDeleted: true)

        if item.hasIsDeleted, item.isDeleted.value {
            if let existing, !existing.deleted {
                _ = await dataManager.bookmarks.remove(bookmarks: [existing], syncStatus: .synced)
            }
            return
        }

        guard let existing else {
            guard !item.episodeUuid.isEmpty else { return }
            _ = dataManager.bookmarks.add(
                uuid: uuid,
                episodeUuid: item.episodeUuid,
                podcastUuid: item.podcastUuid.isEmpty ? nil : item.podcastUuid,
                title: item.title.value,
                time: TimeInterval(item.time.value),
                dateCreated: item.hasCreatedAt ? item.createdAt.date : Date(),
                excerpt: item.hasExcerpt ? item.excerpt.value : nil,
                endTime: item.hasEndTime ? item.endTime.value : nil,
                syncStatus: .synced)
            return
        }

        if item.hasTitle, item.title.value != existing.title {
            let incomingModified = item.titleModified.value
            let localModified = existing.titleModified.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
            if incomingModified > localModified {
                _ = await dataManager.bookmarks.update(
                    bookmark: existing,
                    title: item.title.value,
                    modified: Date(timeIntervalSince1970: Double(incomingModified) / 1000),
                    syncStatus: .synced)
            }
        }

        // Highlight enrichment merges by stamped LWW (MergeEngine fields
        // 1000/1001), so the merged record is authoritative: adopt its excerpt
        // and end time whenever either differs from the local row. Each field
        // is honored independently — an absent field keeps the local value.
        let mergedExcerpt = item.hasExcerpt ? item.excerpt.value : existing.excerpt
        let mergedEndTime = item.hasEndTime ? item.endTime.value : existing.endTime
        if mergedExcerpt != existing.excerpt || mergedEndTime != existing.endTime {
            _ = await dataManager.bookmarks.updateEnrichment(
                uuid: uuid,
                excerpt: mergedExcerpt,
                endTime: mergedEndTime,
                syncStatus: .synced)
        }
    }

    // MARK: Up Next

    private func applyUpNext(_ replayed: [UpNextMerger.QueueEntry]) async -> Bool {
        var target = replayed

        let localQueue = delegate?.currentQueueEpisodeUuids() ?? []
        if let playing = localQueue.first {
            if let index = target.firstIndex(where: { $0.episodeUuid == playing }) {
                let entry = target.remove(at: index)
                target.insert(entry, at: 0)
            } else {
                target.insert(UpNextMerger.QueueEntry(episodeUuid: playing, podcastUuid: ""), at: 0)
            }
        }

        if localQueue == target.map(\.episodeUuid) {
            return false
        }

        dataManager.snapshotUpNext()

        var keptUuids: [String] = []
        for (index, entry) in target.enumerated() {
            if let existing = dataManager.findPlaylistEpisode(uuid: entry.episodeUuid) {
                var moved = existing
                moved.episodePosition = Int32(index)
                DataManager.withFileSyncApplySuppression {
                    dataManager.save(playlistEpisode: moved)
                }
                keptUuids.append(entry.episodeUuid)
                continue
            }

            var episode = dataManager.findBaseEpisode(uuid: entry.episodeUuid)
            if episode == nil, !entry.podcastUuid.isEmpty,
               entry.podcastUuid != DataConstants.userEpisodeFakePodcastId {
                if await delegate?.backfillEpisode(uuid: entry.episodeUuid, podcastUuid: entry.podcastUuid) == true {
                    episode = dataManager.findBaseEpisode(uuid: entry.episodeUuid)
                }
            }
            guard episode != nil || entry.podcastUuid == DataConstants.userEpisodeFakePodcastId else {
                continue
            }

            var playlistEpisode = PlaylistEpisode()
            playlistEpisode.episodeUuid = entry.episodeUuid
            playlistEpisode.podcastUuid = entry.podcastUuid.isEmpty
                ? (episode?.parentIdentifier() ?? "")
                : entry.podcastUuid
            playlistEpisode.title = episode?.displayableTitle() ?? ""
            playlistEpisode.episodePosition = Int32(index)
            DataManager.withFileSyncApplySuppression {
                dataManager.save(playlistEpisode: playlistEpisode)
            }
            keptUuids.append(entry.episodeUuid)
        }

        DataManager.withFileSyncApplySuppression {
            dataManager.deleteAllUpNextEpisodesNotIn(uuids: keptUuids)
        }
        delegate?.refreshQueueFromDatabase()
        return true
    }

    // MARK: Settings / stats

    private func applySettings(_ settings: [String: MergeEngine.SettingValue]) {
        guard let delegate else { return }
        for (name, value) in settings {
            delegate.applySetting(FileSyncSettingChange(
                name: name,
                jsonValue: value.jsonValue,
                modifiedAtMs: value.stamp.wallClockMs))
        }
    }

    private func applyStats(_ statsByDevice: [String: MergeEngine.StatsEntry]) {
        guard let delegate, !statsByDevice.isEmpty else { return }
        var totals = Filesync_StatsCumulative()
        for entry in statsByDevice.values {
            totals.timesStartedAt = min(
                totals.timesStartedAt == 0 ? Int64.max : totals.timesStartedAt,
                entry.stats.timesStartedAt == 0 ? Int64.max : entry.stats.timesStartedAt)
            totals.timeSilenceRemoval += entry.stats.timeSilenceRemoval
            totals.timeVariableSpeed += entry.stats.timeVariableSpeed
            totals.timeIntroSkipping += entry.stats.timeIntroSkipping
            totals.timeSkipping += entry.stats.timeSkipping
            totals.timeListened += entry.stats.timeListened
        }
        if totals.timesStartedAt == Int64.max { totals.timesStartedAt = 0 }
        delegate.applyPeerStats(totals)
    }
}
