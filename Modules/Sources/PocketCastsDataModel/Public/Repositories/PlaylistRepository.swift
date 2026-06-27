import Foundation

/// Read and mutate playlists (filters) and their episode membership.
///
/// `DataManager` is the production conformer; inject `any PlaylistRepository` (see
/// `Repositories+Dependency.swift`) so consumers can be tested with mocks and a
/// future persistence engine can ship as a second conformer.
public protocol PlaylistRepository: AnyObject {
    func allPlaylists(includeDeleted: Bool) -> [EpisodeFilter]
    func allSmartPlaylists(includeDeleted: Bool) -> [EpisodeFilter]
    func allManualPlaylists(includeDeleted: Bool) -> [EpisodeFilter]
    func playlistsCount(includeDeleted: Bool) -> Int
    func playlistContainsEpisode(episodeUuid: String, includeDeleted: Bool) -> Bool
    func manualPlaylistUUIDs(for episodeUUID: String) -> [String]
    func playlistContainsPodcast(podcastUuid: String, includeDeleted: Bool) -> Bool
    func findPlaylist(uuid: String) -> EpisodeFilter?
    func episodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int
    func playlistEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int
    func playlistArchivedEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int
    func allPlaylistEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?, includingArchivedEpisodes: Bool) -> Int
    func playlistEpisodes(for playlist: EpisodeFilter, limit: Int?, sortType: PlaylistSort?) -> [Episode]
    func playlistFirstDistinctEpisodes(for playlist: EpisodeFilter, limit: Int, shouldShowArchived: Bool, search: String?, episodeUuidToAdd: String?) -> [Episode]
    func deleteDeletedPlaylists()
    func allUnsyncedPlaylists() -> [EpisodeFilter]
    @discardableResult
    func save(playlist: EpisodeFilter) -> EpisodeFilter
    func updatePlaylistUpdateDate(for playlist: EpisodeFilter, to date: Date)
    @discardableResult
    func add(episodes: [Episode], to playlist: EpisodeFilter) -> Bool
    func delete(playlist: EpisodeFilter)
    func markAllPlaylistsSynced()
    func markAllPlaylistsUnsynced()
    func nextSortPositionForPlaylist() -> Int
    func firstSortPositionForPlaylist() -> Int
    func bumpSortPositionForAllPlaylists(adding value: Int)
    func updatePosition(playlist: EpisodeFilter, newPosition: Int32)
    func moveEpisode(_ episodeUuid: String, in playlist: EpisodeFilter, to index: Int)
    func updateEpisodePosition(_ episodeUuid: String, in playlist: EpisodeFilter, to position: Int32)
    func deleteEpisodes(_ episodeUuids: [String], from playlist: EpisodeFilter)
    func rawDeleteEpisodes(_ episodeUuids: [String], from playlist: EpisodeFilter)
    func deleteAllEpisodes(in playlist: EpisodeFilter)

    // MARK: Async variants

    // The returned models are mutable reference types: treat them as owned by
    // the awaiting task. The default implementations run the synchronous
    // requirement on a background queue; conformers can override with natively
    // async reads.
    func playlistEpisodeCountAsync(for playlist: EpisodeFilter, episodeUuidToAdd: String?) async -> Int
    func playlistEpisodesAsync(for playlist: EpisodeFilter, limit: Int?, sortType: PlaylistSort?) async -> [Episode]
}

public extension PlaylistRepository {
    // Conveniences mirroring DataManager's default arguments, which protocol
    // requirements cannot express.
    func playlistContainsEpisode(episodeUuid: String) -> Bool {
        playlistContainsEpisode(episodeUuid: episodeUuid, includeDeleted: false)
    }

    func playlistContainsPodcast(podcastUuid: String) -> Bool {
        playlistContainsPodcast(podcastUuid: podcastUuid, includeDeleted: false)
    }

    func allPlaylistEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int {
        allPlaylistEpisodeCount(for: playlist, episodeUuidToAdd: episodeUuidToAdd, includingArchivedEpisodes: false)
    }

    func playlistEpisodes(for playlist: EpisodeFilter) -> [Episode] {
        playlistEpisodes(for: playlist, limit: nil, sortType: nil)
    }

    func playlistFirstDistinctEpisodes(for playlist: EpisodeFilter) -> [Episode] {
        playlistFirstDistinctEpisodes(for: playlist, limit: 4, shouldShowArchived: false, search: nil, episodeUuidToAdd: nil)
    }

    func updatePlaylistUpdateDate(for playlist: EpisodeFilter) {
        updatePlaylistUpdateDate(for: playlist, to: .now)
    }

    func bumpSortPositionForAllPlaylists() {
        bumpSortPositionForAllPlaylists(adding: 1)
    }

    func playlistEpisodeCountAsync(for playlist: EpisodeFilter, episodeUuidToAdd: String?) async -> Int {
        await runOffMainThread { self.playlistEpisodeCount(for: playlist, episodeUuidToAdd: episodeUuidToAdd) }
    }

    func playlistEpisodesAsync(for playlist: EpisodeFilter, limit: Int?, sortType: PlaylistSort?) async -> [Episode] {
        await runOffMainThread { self.playlistEpisodes(for: playlist, limit: limit, sortType: sortType) }
    }
}

extension DataManager: PlaylistRepository {}
