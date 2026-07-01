import PocketCastsDataModel
import PocketCastsUtils

extension PlaylistDetailViewModel {
    func playAllEpisodes() {
        PlaybackManager.shared.play(playlist: playlist)
    }

    func saveUpNextAndPlay() {
        Task { [weak self] in
            guard let self else { return }
            let batches = await self.batchedUpNextEpisodes()
            await MainActor.run {
                self.playAllEpisodes()
            }
            let success = await self.createPlaylists(from: batches)
            if success {
                await MainActor.run {
                    Toast.show(
                        batches.count > 1 ? L10n.playlistPlayAllUpNextSavedPlural : L10n.playlistPlayAllUpNextSaved,
                        actions: [
                            .init(title: L10n.bookmarkAddedButtonTitle) {
                                NavigationManager.sharedManager.navigateTo(
                                    NavigationManager.filterPageKey
                                )
                            }
                        ]
                    )
                }
            }
        }
    }

    // nonisolated so the synchronous Up Next DB reads run off the main actor (the class is @MainActor);
    // uses the global DataManager rather than capturing the non-Sendable instance. Returns Sendable [[Episode]].
    nonisolated private func batchedUpNextEpisodes(batchSize: Int = Constants.Limits.maxFilterItems) async -> [[Episode]] {
        let uuids = DataManager.sharedManager.allUpNextEpisodeUuids().compactMap(\.uuid)
        let allEpisodes = DataManager.sharedManager.allUpNextEpisodes(from: uuids)

        guard !allEpisodes.isEmpty else { return [] }
        guard allEpisodes.count > batchSize else { return [allEpisodes] }

        var result: [[Episode]] = []
        var startIndex = 0

        while startIndex < allEpisodes.count {
            let endIndex = min(startIndex + batchSize, allEpisodes.count)
            result.append(Array(allEpisodes[startIndex..<endIndex]))
            startIndex += batchSize
        }

        return result
    }

    nonisolated private func createPlaylists(from batches: [[Episode]]) async -> Bool {
        let firstSortPosition = max(0, DataManager.sharedManager.firstSortPositionForPlaylist())
        DataManager.sharedManager.bumpSortPositionForAllPlaylists(adding: batches.count)
        for (index, batch) in batches.enumerated() {
            let playlist = DataManager.sharedManager.save(
                playlist: newManualPlaylist(index: index + 1, sortPosition: firstSortPosition + index)
            )
            DataManager.sharedManager.add(episodes: batch, to: playlist)
        }
        return true
    }

    nonisolated private func newManualPlaylist(index: Int, sortPosition: Int) -> EpisodeFilter {
        var playlistName = "\(L10n.upNext) - \(Date().monthDayString())"
        if index > 1 {
            playlistName += " (\(index))"
        }
        var playlist = PlaylistManager.createNewPlaylist()
        playlist.setTitle(playlistName, defaultTitle: L10n.playlistsDefaultNewPlaylist.localizedCapitalized)
        playlist.manual = true
        playlist.syncStatus = SyncStatus.notSynced.rawValue
        playlist.isNew = false
        playlist.sortType = PlaylistSort.dragAndDrop.rawValue
        playlist.sortPosition = Int32(sortPosition)
        return playlist
    }
}
