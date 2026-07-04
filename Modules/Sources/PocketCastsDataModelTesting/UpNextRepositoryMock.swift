import Foundation
import PocketCastsDataModel

/// Generated protocol mock for `UpNextRepository`. Stub return values by selector:
/// `mock.stub("findPodcast(uuid:includeUnsubscribed:)", with: podcast)`.
// @unchecked Sendable: restates RepositoryMock's conformance, as Swift requires of subclasses; state stays lock-guarded in the base class.
public final class UpNextRepositoryMock: RepositoryMock, UpNextRepository, @unchecked Sendable {
    public func allUpNextPlaylistEpisodes() -> [PlaylistEpisode] {
        record("allUpNextPlaylistEpisodes()")
        return stubs["allUpNextPlaylistEpisodes()"] as? [PlaylistEpisode] ?? []
    }

    public func upNextPlayListContains(episodeUuid: String) -> Bool {
        record("upNextPlayListContains(episodeUuid:)")
        return stubs["upNextPlayListContains(episodeUuid:)"] as? Bool ?? false
    }

    public func allUpNextEpisodes(from uuids: [String]) -> [Episode] {
        record("allUpNextEpisodes(from:)")
        return stubs["allUpNextEpisodes(from:)"] as? [Episode] ?? []
    }

    public func allUpNextEpisodes() -> [BaseEpisode] {
        record("allUpNextEpisodes()")
        return stubs["allUpNextEpisodes()"] as? [BaseEpisode] ?? []
    }

    public func allUpNextEpisodeUuids() -> [BaseEpisode] {
        record("allUpNextEpisodeUuids()")
        return stubs["allUpNextEpisodeUuids()"] as? [BaseEpisode] ?? []
    }

    public func findPlaylistEpisode(uuid: String) -> PlaylistEpisode? {
        record("findPlaylistEpisode(uuid:)")
        return stubs["findPlaylistEpisode(uuid:)"] as? PlaylistEpisode
    }

    public func positionForPlaylistEpisode(bottomOfList: Bool) -> Int32 {
        record("positionForPlaylistEpisode(bottomOfList:)")
        return stubs["positionForPlaylistEpisode(bottomOfList:)"] as? Int32 ?? 0
    }

    public func deleteAllUpNextEpisodes() {
        record("deleteAllUpNextEpisodes()")
    }

    public func deleteAllUpNextEpisodesExcept(episodeUuid: String) {
        record("deleteAllUpNextEpisodesExcept(episodeUuid:)")
    }

    public func deleteAllUpNextEpisodesNotIn(uuids: [String]) {
        record("deleteAllUpNextEpisodesNotIn(uuids:)")
    }

    public func deleteAllUpNextEpisodesIn(uuids: [String]) {
        record("deleteAllUpNextEpisodesIn(uuids:)")
    }

    public func save(playlistEpisode: PlaylistEpisode) {
        record("save(playlistEpisode:)")
    }

    public func save(playlistEpisodes: [PlaylistEpisode]) {
        record("save(playlistEpisodes:)")
    }

    public func delete(playlistEpisode: PlaylistEpisode) {
        record("delete(playlistEpisode:)")
    }

    public func movePlaylistEpisode(from: Int, to: Int) {
        record("movePlaylistEpisode(from:to:)")
    }

    public func playlistEpisodeCount() -> Int {
        record("playlistEpisodeCount()")
        return stubs["playlistEpisodeCount()"] as? Int ?? 0
    }

    public func playlistEpisodeAt(index: Int) -> PlaylistEpisode? {
        record("playlistEpisodeAt(index:)")
        return stubs["playlistEpisodeAt(index:)"] as? PlaylistEpisode
    }

    public func episodeInUpNextAt(index: Int) -> BaseEpisode? {
        record("episodeInUpNextAt(index:)")
        return stubs["episodeInUpNextAt(index:)"] as? BaseEpisode
    }

    public func findReplaceAction() -> UpNextChanges? {
        record("findReplaceAction()")
        return stubs["findReplaceAction()"] as? UpNextChanges
    }

    public func findUpdateActions() -> [UpNextChanges] {
        record("findUpdateActions()")
        return stubs["findUpdateActions()"] as? [UpNextChanges] ?? []
    }

    public func saveUpNextRemove(episodeUuid: String) {
        record("saveUpNextRemove(episodeUuid:)")
    }

    public func saveUpNextAddToTop(episodeUuid: String) {
        record("saveUpNextAddToTop(episodeUuid:)")
    }

    public func saveUpNextAddToBottom(episodeUuid: String) {
        record("saveUpNextAddToBottom(episodeUuid:)")
    }

    public func saveUpNextAddNowPlaying(episodeUuid: String) {
        record("saveUpNextAddNowPlaying(episodeUuid:)")
    }

    public func saveReplace(episodeList: [String]) {
        record("saveReplace(episodeList:)")
    }

    public func deleteChangesOlderThan(utcTime: Int64) {
        record("deleteChangesOlderThan(utcTime:)")
    }

    public func snapshotUpNext() {
        record("snapshotUpNext()")
    }

    public func upNextHistoryEntries() -> [UpNextHistoryManager.UpNextHistoryEntry] {
        record("upNextHistoryEntries()")
        return stubs["upNextHistoryEntries()"] as? [UpNextHistoryManager.UpNextHistoryEntry] ?? []
    }

    public func upNextHistoryEpisodes(entry: Date) -> [String] {
        record("upNextHistoryEpisodes(entry:)")
        return stubs["upNextHistoryEpisodes(entry:)"] as? [String] ?? []
    }
}
