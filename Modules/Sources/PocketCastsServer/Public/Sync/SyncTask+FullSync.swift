import Foundation
import PocketCastsDataModel
import PocketCastsUtils

extension SyncTask {
    func processServerPlaylists(_ playlists: [(EpisodeFilter, [Episode])]) {
        // before looking at the server playlists, mark any we have here locally as needing to be syncing so they get pushed up with the next sync
        DataManager.sharedManager.markAllPlaylistsUnsynced()

        playlists.forEach { playlist, serverEpisodes in
            var playlist = playlist
            // if we have this playlist locally, assume the server version is more up to date, so blow ours away
            if let localPlaylist = DataManager.sharedManager.findPlaylist(uuid: playlist.uuid) {
                // ...unless it's a custom playlist: those are device-local (the server
                // never saw their customQuery), so a full sync must not delete-rewrite
                // them on a uuid collision.
                if localPlaylist.isCustom {
                    FileLog.shared.addMessage("SyncTask: preserving local custom playlist \(localPlaylist.uuid) during full sync")
                    return
                }
                DataManager.sharedManager.delete(playlist: localPlaylist)
            }

            // save the server version of the filter, as long as it's not deleted
            guard !playlist.wasDeleted else {
                return
            }

            var addedEpisodes: [Episode] = []

            // Add missing episodes
            let matchedEpisodeUuids = Set(DataManager.sharedManager.playlistEpisodes(for: playlist).map { $0.uuid })
            addedEpisodes = serverEpisodes.filter { !matchedEpisodeUuids.contains($0.uuid) }

            playlist.syncStatus = SyncStatus.synced.rawValue
            DataManager.sharedManager.save(playlist: playlist)
            let didAdd = DataManager.sharedManager.add(episodes: addedEpisodes, to: playlist)
            if !didAdd {
                let playlistCount = DataManager.sharedManager.allPlaylistEpisodeCount(for: playlist, episodeUuidToAdd: nil, includingArchivedEpisodes: true)
                FileLog.shared.addMessage("SyncTask: Tried to add too many episodes from server playlist \(playlist.playlistName) episodeCount: \(addedEpisodes) playlistCount: \(playlistCount)")
            }
        }
    }

    func processServerHomeGrid(podcasts: [PodcastSyncInfo]?, folders: [FolderSyncInfo]?, lastSyncAt: String) {
        // before looking at the server podcasts, mark any we have here locally as needing to be syncing so they get pushed up with the next sync
        DataManager.sharedManager.markAllPodcastsUnsyncedWhereLastSyncAtNot(lastSyncAt)

        // for folders we take the opposite approach, anything you currently have on device is old and should be replaced with the server copy
        DataManager.sharedManager.clearAllFolderInformation()

        // import any folders first, since that's fast and needs no extra calls
        if let folders {
            for folder in folders {
                processFolder(folder)
            }
        }

        guard let podcasts else { return }

        resetPodcastImportProgress(total: podcasts.count, upTo: 0)
        for podcast in podcasts {
            importQueue.addOperation {
                self.incrementAndPostPodcastImportProgress()

                self.processPodcast(podcast, lastSyncAt: lastSyncAt)
            }
        }
        importQueue.waitUntilAllOperationsAreFinished()

        NotificationCenter.postOnMainThread(SyncProgressPodcastsImported())
    }

    private func processFolder(_ folder: FolderSyncInfo) {
        FolderHelper.addFolderToDatabase(folder)
    }

    func processPodcast(_ podcast: PodcastSyncInfo, lastSyncAt: String) {
        guard let uuid = podcast.uuid else { return }

        if let localPodcast = DataManager.sharedManager.findPodcast(uuid: uuid), lastSyncAt == localPodcast.fullSyncLastSyncAt {
            FileLog.shared.addMessage("Skipping processing of podcast \(uuid) in full sync, already done previously")
            return
        }

        FileLog.shared.addMessage("Processing podcast \(uuid)")
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        ServerPodcastManager.shared.addFromUuid(podcastUuid: uuid, subscribe: true) { success in
            if !success {
                dispatchGroup.leave()

                return
            }

            defer { dispatchGroup.leave() }
            guard var localPodcast = DataManager.sharedManager.findPodcast(uuid: uuid) else { return }

            // we have added the podcast locally so add the synced info for it
            if let startFrom = podcast.autoStartFrom {
                localPodcast.startFrom = Int32(startFrom)
            }
            if let skipLast = podcast.autoSkipLast {
                localPodcast.skipLast = Int32(skipLast)
            }
            localPodcast.syncStatus = SyncStatus.synced.rawValue
            localPodcast.fullSyncLastSyncAt = lastSyncAt

            if let addedDate = podcast.dateAdded {
                localPodcast.addedDate = addedDate
            }

            localPodcast.folderUuid = podcast.folderUuid

            if let sortOrder = podcast.sortPosition {
                localPodcast.sortOrder = sortOrder
            }

            if let settings = podcast.settings {
                localPodcast = self.processSettings(settings, to: localPodcast)
            }

            // now grab the sync info for the episodes
            let retrieveEpisodesTask = RetrieveEpisodesTask(podcastUuid: uuid)
            retrieveEpisodesTask.completion = { episodes in
                DataManager.sharedManager.save(podcast: localPodcast)

                guard let episodes else { return }

                DataManager.sharedManager.saveBulkEpisodeSyncInfo(episodes: DataConverter.convert(syncInfoEpisodes: episodes))
            }
            retrieveEpisodesTask.runTaskSynchronously()
        }

        _ = dispatchGroup.wait(timeout: .now() + 30.seconds)
    }
}

// MARK: - Bookmarks

extension SyncTask {
    /// Fully imports the server bookmarks and replaces the existing data if there is any available
    func processServerBookmarks(_ bookmarks: [Api_BookmarkResponse]) {
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            let bookmarkManager = dataManager.bookmarks

            // Set all the bookmarks as synced
            bookmarkManager.markAllBookmarksAsSynced()

            for apiBookmark in bookmarks {
                let localBookmark = bookmarkManager.bookmark(for: apiBookmark.bookmarkUuid, allowDeleted: true)
                await bookmarkManager.remove(apiBookmark: apiBookmark).when(false) {
                    FileLog.shared.addMessage("SyncTask: Process Server Bookmarks - Could not delete existing bookmark: \(apiBookmark.bookmarkUuid)")
                }

                // Add the incoming bookmark to the database
                let addedUuid = bookmarkManager.add(from: apiBookmark)
                if addedUuid == nil {
                    FileLog.shared.addMessage("SyncTask: Process Server Bookmarks - Could not add bookmark: \(String(describing: try? apiBookmark.jsonString()))")
                } else if let addedUuid {
                    if FeatureFlag.highlightAccountSync.enabled {
                        await bookmarkManager.mergeHighlightFields(from: apiBookmark, local: localBookmark, uuid: addedUuid)
                    } else if let localBookmark {
                        await bookmarkManager.restoreLocalHighlightFields(from: localBookmark, uuid: addedUuid)
                    }
                }
            }

            semaphore.signal()
        }

        semaphore.wait()
        // A full sync is download-only: nothing local was uploaded, so it can
        // never complete the highlight-upload transition. Re-arm the one-shot
        // requeue instead — the next incremental sync re-uploads highlight
        // fields the server may lack (fresh login, account switch, fields
        // captured while the flag was dark). Re-upload is stamp-LWW idempotent.
        UserDefaults.standard.set(false, forKey: ServerConstants.UserDefaults.highlightAccountSyncCompleted)
    }
}

private extension BookmarkDataManager {
    func add(from apiBookmark: Api_BookmarkResponse) -> String? {
        add(uuid: apiBookmark.bookmarkUuid,
            episodeUuid: apiBookmark.episodeUuid,
            podcastUuid: apiBookmark.podcastUuid,
            title: apiBookmark.title,
            time: .init(apiBookmark.time),
            dateCreated: apiBookmark.createdAt.date,
            syncStatus: .synced)
    }

    /// Full-sync merge of the highlight fields (ADR-0016). The base row was
    /// just replaced from the server, but the server copy is not authoritative
    /// for these fields: fields captured while the flag was dark (or offline)
    /// were never uploaded, and a plain apply would destroy them. Standard
    /// stamp LWW instead — a local-newer trim or tag set is restored and marked
    /// `.notSynced` so the next incremental sync uploads it; otherwise the
    /// server copy applies as `.synced`.
    func mergeHighlightFields(from apiBookmark: Api_BookmarkResponse, local: Bookmark?, uuid: String) async {
        let serverTrimMs = apiBookmark.trimModified
        let localTrimMs = local?.trimModified.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0

        if localTrimMs > serverTrimMs,
           let local, let excerpt = local.excerpt, let trimModified = local.trimModified {
            await updateTrim(uuid: uuid,
                             excerpt: excerpt,
                             endTime: local.endTime ?? local.time,
                             trimModified: trimModified,
                             syncStatus: .notSynced)
        } else if !apiBookmark.excerpt.isEmpty {
            // end_time is a bare proto3 double, so absent decodes as 0 — fall
            // back to the bookmark's own timestamp (the incremental path's
            // rule) rather than storing a nonsense [time, 0] window.
            let endTime = apiBookmark.endTime > 0 ? apiBookmark.endTime : TimeInterval(apiBookmark.time)
            if serverTrimMs > 0 {
                await updateTrim(uuid: uuid,
                                 excerpt: apiBookmark.excerpt,
                                 endTime: endTime,
                                 trimModified: Date(timeIntervalSince1970: TimeInterval(serverTrimMs) / 1000),
                                 syncStatus: .synced)
            } else {
                await updateEnrichment(uuid: uuid,
                                       excerpt: apiBookmark.excerpt,
                                       endTime: endTime,
                                       syncStatus: .synced)
            }
        } else if let local, let excerpt = local.excerpt, local.trimModified == nil {
            // Machine enrichment the server has no copy of: keep it and let the
            // next incremental sync upload it rather than re-deriving on device.
            await updateEnrichment(uuid: uuid,
                                   excerpt: excerpt,
                                   endTime: local.endTime,
                                   syncStatus: .notSynced)
        }

        let serverTagsMs = apiBookmark.tagsModified
        let localTagsMs = local?.tagsModified.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        if localTagsMs > serverTagsMs, let local, let tagsModified = local.tagsModified {
            await setTags(uuid: uuid,
                          tags: local.tags,
                          modified: tagsModified,
                          syncStatus: .notSynced)
        } else if serverTagsMs > 0 {
            await setTags(uuid: uuid,
                          tags: apiBookmark.tags,
                          modified: Date(timeIntervalSince1970: TimeInterval(serverTagsMs) / 1000),
                          syncStatus: .synced)
        }
    }

    /// While account sync is dark, the server cannot round-trip highlight
    /// fields. A full sync still replaces the base bookmark row, so restore the
    /// device-local fields after the replacement.
    func restoreLocalHighlightFields(from bookmark: Bookmark, uuid: String) async {
        if let excerpt = bookmark.excerpt, !excerpt.isEmpty {
            if let trimModified = bookmark.trimModified {
                await updateTrim(uuid: uuid,
                                 excerpt: excerpt,
                                 endTime: bookmark.endTime ?? bookmark.time,
                                 trimModified: trimModified,
                                 syncStatus: .synced)
            } else {
                await updateEnrichment(uuid: uuid,
                                       excerpt: excerpt,
                                       endTime: bookmark.endTime ?? bookmark.time,
                                       syncStatus: .synced)
            }
        }
        if let tagsModified = bookmark.tagsModified {
            await setTags(uuid: uuid,
                          tags: bookmark.tags,
                          modified: tagsModified,
                          syncStatus: .synced)
        }
    }

    func remove(apiBookmark: Api_BookmarkResponse) async -> Bool? {
        guard let bookmark = bookmark(for: apiBookmark.bookmarkUuid, allowDeleted: true) else {
            return nil
        }

        return await permanentlyDelete(bookmarks: [bookmark])
    }
}

// MARK: - Settings

private extension SyncTask {
    func processSettings(_ settings: PodcastSettings, to podcast: Podcast) -> Podcast {
        var podcast = podcast
        let oldSettings = podcast.settings
        podcast.settings.$customEffects = settings.$customEffects
        podcast.settings.$autoStartFrom = settings.$autoStartFrom
        podcast.settings.$autoSkipLast = settings.$autoSkipLast
        podcast.settings.$trimSilence = settings.$trimSilence
        podcast.settings.$playbackSpeed = settings.$playbackSpeed
        podcast.settings.$boostVolume = settings.$boostVolume
        podcast.settings.$notification = settings.$notification
        podcast.settings.$autoArchive = settings.$autoArchive
        podcast.settings.$autoArchivePlayed = settings.$autoArchivePlayed
        podcast.settings.$autoArchiveInactive = settings.$autoArchiveInactive
        podcast.settings.$autoArchiveEpisodeLimit = settings.$autoArchiveEpisodeLimit
        podcast.settings.$addToUpNext = settings.$addToUpNext
        podcast.settings.$addToUpNextPosition = settings.$addToUpNextPosition
        podcast.settings.$episodesSortOrder = settings.$episodesSortOrder
        podcast.settings.$episodeGrouping = settings.$episodeGrouping
        podcast.settings.$showArchived = settings.$showArchived
        oldSettings.printDiff(from: podcast.settings, withIdentifier: podcast.uuid)
        return podcast
    }
}
