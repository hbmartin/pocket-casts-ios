import PocketCastsDataModel

extension PlaylistDetailViewModel {
    var shouldShowArchived: Bool {
        playlist.showArchivedEpisodes
    }

    var shouldShowArchivePlaceholder: Bool {
        archivedEpisodesCount > 0 && !shouldShowArchived
    }

    var shouldShowEmptyPlaceholder: Bool {
        episodes.isEmpty && !shouldShowArchivePlaceholder
    }

    func unarchivedEpisodesCount() -> Int {
        dataManager.playlistEpisodeCount(
            for: playlist,
            episodeUuidToAdd: playlist.episodeUuidToAddToQueries()
        )
    }

    func updateShowArchivedEpisodes(show: Bool) {
        var playlist = playlist
        playlist.showArchivedEpisodes = show
        let savedPlaylist = dataManager.save(playlist: playlist)
        update(playlist: savedPlaylist)
    }
}
