import Foundation
import PocketCastsDataModel

/// Generated protocol mock for `PlaylistRepository`. Stub return values by selector:
/// `mock.stub("findPodcast(uuid:includeUnsubscribed:)", with: podcast)`.
public final class PlaylistRepositoryMock: RepositoryMock, PlaylistRepository {
    public func allPlaylists(includeDeleted: Bool) -> [EpisodeFilter] {
        record("allPlaylists(includeDeleted:)")
        return stubs["allPlaylists(includeDeleted:)"] as? [EpisodeFilter] ?? []
    }

    public func allSmartPlaylists(includeDeleted: Bool) -> [EpisodeFilter] {
        record("allSmartPlaylists(includeDeleted:)")
        return stubs["allSmartPlaylists(includeDeleted:)"] as? [EpisodeFilter] ?? []
    }

    public func allManualPlaylists(includeDeleted: Bool) -> [EpisodeFilter] {
        record("allManualPlaylists(includeDeleted:)")
        return stubs["allManualPlaylists(includeDeleted:)"] as? [EpisodeFilter] ?? []
    }

    public func playlistsCount(includeDeleted: Bool) -> Int {
        record("playlistsCount(includeDeleted:)")
        return stubs["playlistsCount(includeDeleted:)"] as? Int ?? 0
    }

    public func playlistContainsEpisode(episodeUuid: String, includeDeleted: Bool) -> Bool {
        record("playlistContainsEpisode(episodeUuid:includeDeleted:)")
        return stubs["playlistContainsEpisode(episodeUuid:includeDeleted:)"] as? Bool ?? false
    }

    public func manualPlaylistUUIDs(for episodeUUID: String) -> [String] {
        record("manualPlaylistUUIDs(for:)")
        return stubs["manualPlaylistUUIDs(for:)"] as? [String] ?? []
    }

    public func playlistContainsPodcast(podcastUuid: String, includeDeleted: Bool) -> Bool {
        record("playlistContainsPodcast(podcastUuid:includeDeleted:)")
        return stubs["playlistContainsPodcast(podcastUuid:includeDeleted:)"] as? Bool ?? false
    }

    public func findPlaylist(uuid: String) -> EpisodeFilter? {
        record("findPlaylist(uuid:)")
        return stubs["findPlaylist(uuid:)"] as? EpisodeFilter
    }

    public func episodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int {
        record("episodeCount(for:episodeUuidToAdd:)")
        return stubs["episodeCount(for:episodeUuidToAdd:)"] as? Int ?? 0
    }

    public func playlistEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int {
        record("playlistEpisodeCount(for:episodeUuidToAdd:)")
        return stubs["playlistEpisodeCount(for:episodeUuidToAdd:)"] as? Int ?? 0
    }

    public func playlistArchivedEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int {
        record("playlistArchivedEpisodeCount(for:episodeUuidToAdd:)")
        return stubs["playlistArchivedEpisodeCount(for:episodeUuidToAdd:)"] as? Int ?? 0
    }

    public func allPlaylistEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?, includingArchivedEpisodes: Bool) -> Int {
        record("allPlaylistEpisodeCount(for:episodeUuidToAdd:includingArchivedEpisodes:)")
        return stubs["allPlaylistEpisodeCount(for:episodeUuidToAdd:includingArchivedEpisodes:)"] as? Int ?? 0
    }

    public func playlistEpisodes(for playlist: EpisodeFilter, limit: Int?, sortType: PlaylistSort?) -> [Episode] {
        record("playlistEpisodes(for:limit:sortType:)")
        return stubs["playlistEpisodes(for:limit:sortType:)"] as? [Episode] ?? []
    }

    public func playlistFirstDistinctEpisodes(for playlist: EpisodeFilter, limit: Int, shouldShowArchived: Bool, search: String?, episodeUuidToAdd: String?) -> [Episode] {
        record("playlistFirstDistinctEpisodes(for:limit:shouldShowArchived:search:episodeUuidToAdd:)")
        return stubs["playlistFirstDistinctEpisodes(for:limit:shouldShowArchived:search:episodeUuidToAdd:)"] as? [Episode] ?? []
    }

    public func deleteDeletedPlaylists() {
        record("deleteDeletedPlaylists()")
    }

    public func allUnsyncedPlaylists() -> [EpisodeFilter] {
        record("allUnsyncedPlaylists()")
        return stubs["allUnsyncedPlaylists()"] as? [EpisodeFilter] ?? []
    }

    @discardableResult
    public func save(playlist: EpisodeFilter) -> EpisodeFilter {
        record("save(playlist:)")
        return playlist
    }

    public func updatePlaylistUpdateDate(for playlist: EpisodeFilter, to date: Date) {
        record("updatePlaylistUpdateDate(for:to:)")
    }

    @discardableResult
    public func add(episodes: [Episode], to playlist: EpisodeFilter) -> Bool {
        record("add(episodes:to:)")
        return stubs["add(episodes:to:)"] as? Bool ?? false
    }

    public func delete(playlist: EpisodeFilter) {
        record("delete(playlist:)")
    }

    public func markAllPlaylistsSynced() {
        record("markAllPlaylistsSynced()")
    }

    public func markAllPlaylistsUnsynced() {
        record("markAllPlaylistsUnsynced()")
    }

    public func nextSortPositionForPlaylist() -> Int {
        record("nextSortPositionForPlaylist()")
        return stubs["nextSortPositionForPlaylist()"] as? Int ?? 0
    }

    public func firstSortPositionForPlaylist() -> Int {
        record("firstSortPositionForPlaylist()")
        return stubs["firstSortPositionForPlaylist()"] as? Int ?? 0
    }

    public func bumpSortPositionForAllPlaylists(adding value: Int) {
        record("bumpSortPositionForAllPlaylists(adding:)")
    }

    public func updatePosition(playlist: EpisodeFilter, newPosition: Int32) {
        record("updatePosition(playlist:newPosition:)")
    }

    public func moveEpisode(_ episodeUuid: String, in playlist: EpisodeFilter, to index: Int) {
        record("moveEpisode(_:in:to:)")
    }

    public func updateEpisodePosition(_ episodeUuid: String, in playlist: EpisodeFilter, to position: Int32) {
        record("updateEpisodePosition(_:in:to:)")
    }

    public func deleteEpisodes(_ episodeUuids: [String], from playlist: EpisodeFilter) {
        record("deleteEpisodes(_:from:)")
    }

    public func rawDeleteEpisodes(_ episodeUuids: [String], from playlist: EpisodeFilter) {
        record("rawDeleteEpisodes(_:from:)")
    }

    public func deleteAllEpisodes(in playlist: EpisodeFilter) {
        record("deleteAllEpisodes(in:)")
    }
}
