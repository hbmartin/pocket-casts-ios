import Foundation

/// Read and mutate the Up Next queue, its pending sync changes, and its history snapshots.
///
/// `DataManager` is the production conformer; inject `any UpNextRepository` (see
/// `Repositories+Dependency.swift`) so consumers can be tested with mocks and a
/// future persistence engine can ship as a second conformer.
public protocol UpNextRepository: AnyObject, Sendable {
    func allUpNextPlaylistEpisodes() -> [PlaylistEpisode]
    func upNextPlayListContains(episodeUuid: String) -> Bool
    func allUpNextEpisodes(from uuids: [String]) -> [Episode]
    func allUpNextEpisodes() -> [BaseEpisode]
    func allUpNextEpisodeUuids() -> [BaseEpisode]
    func findPlaylistEpisode(uuid: String) -> PlaylistEpisode?
    func positionForPlaylistEpisode(bottomOfList: Bool) -> Int32
    func deleteAllUpNextEpisodes()
    func deleteAllUpNextEpisodesExcept(episodeUuid: String)
    func deleteAllUpNextEpisodesNotIn(uuids: [String])
    func deleteAllUpNextEpisodesIn(uuids: [String])
    func save(playlistEpisode: PlaylistEpisode)
    func save(playlistEpisodes: [PlaylistEpisode])
    func delete(playlistEpisode: PlaylistEpisode)
    func movePlaylistEpisode(from: Int, to: Int)
    func playlistEpisodeCount() -> Int
    func playlistEpisodeAt(index: Int) -> PlaylistEpisode?
    func episodeInUpNextAt(index: Int) -> BaseEpisode?
    func findReplaceAction() -> UpNextChanges?
    func findUpdateActions() -> [UpNextChanges]
    func saveUpNextRemove(episodeUuid: String)
    func saveUpNextAddToTop(episodeUuid: String)
    func saveUpNextAddToBottom(episodeUuid: String)
    func saveUpNextAddNowPlaying(episodeUuid: String)
    func saveReplace(episodeList: [String])
    func deleteChangesOlderThan(utcTime: Int64)
    func snapshotUpNext()
    func upNextHistoryEntries() -> [UpNextHistoryManager.UpNextHistoryEntry]
    func upNextHistoryEpisodes(entry: Date) -> [String]

    // MARK: Async variants

    // The returned models are mutable reference types: treat them as owned by
    // the awaiting task. The default implementations run the synchronous
    // requirement on a background queue; conformers can override with natively
    // async reads.
    func allUpNextEpisodesAsync() async -> [BaseEpisode]
}

public extension UpNextRepository {
    func allUpNextEpisodesAsync() async -> [BaseEpisode] {
        await runOffMainThread { self.allUpNextEpisodes() }
    }
}

extension DataManager: UpNextRepository {}
