import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// Read-through mirrors for shared lists (Slice 7, ADR-0011): lists the
/// account collaborates on or subscribes to appear in the Playlists tab as
/// local manual playlists. Mirrors are server-derived caches — a refresh
/// REBUILDS them (delete + recreate) rather than merging, which keeps them
/// correct without conflict machinery. The owner's own published playlist is
/// deliberately NOT rebuilt: it stays a normal syncing manual playlist, and
/// the shared-list detail screen is where collaborator additions surface.
enum SocialListMirror {
    /// Deterministic local uuid for a list's mirror playlist.
    static func mirrorUuid(for listId: Int64) -> String {
        "social-list-\(listId)"
    }

    /// Refreshes all mirrors from the server. Fire on app refresh and after
    /// membership changes.
    static func refreshAll() async {
        guard FeatureFlag.socialProfiles.enabled, SocialIdentityStore.isJoined,
              let overview = await ApiServerHandler.shared.fetchSharedLists() else { return }

        let mirrorable = overview.lists.filter { $0.yourRole == .collaborator || $0.yourRole == .subscriber }
        let wantedUuids = Set(mirrorable.map { mirrorUuid(for: $0.id) })

        // Drop mirrors for lists we left / were kicked from / that died.
        for playlist in DataManager.sharedManager.allPlaylists(includeDeleted: false)
            where playlist.sharedListId != nil && playlist.sharedRole >= 2 && !wantedUuids.contains(playlist.uuid) {
            DataManager.sharedManager.delete(playlist: playlist)
        }

        for list in mirrorable {
            await rebuildMirror(for: list)
        }
    }

    /// Rebuilds one mirror playlist from the server's entry order.
    static func rebuildMirror(for list: SharedList) async {
        guard let page = await ApiServerHandler.shared.fetchSharedList(id: list.id, limit: 500) else { return }

        if let existing = DataManager.sharedManager.findPlaylist(uuid: mirrorUuid(for: list.id)) {
            DataManager.sharedManager.delete(playlist: existing)
        }

        var playlist = EpisodeFilter()
        playlist.uuid = mirrorUuid(for: list.id)
        playlist.playlistName = "\(list.title) · @\(list.ownerHandle)"
        playlist.manual = true
        playlist.sharedListId = list.id
        playlist.sharedRole = Int32(list.yourRole.rawValue)
        playlist.syncStatus = SyncStatus.synced.rawValue // never uploads: server-derived
        playlist.sortPosition = Int32(DataManager.sharedManager.nextSortPositionForPlaylist())
        playlist = DataManager.sharedManager.save(playlist: playlist)

        // Only locally-known episodes materialize; the shared-list screen
        // always shows the full server list regardless.
        let episodes = page.entries.compactMap { DataManager.sharedManager.findEpisode(uuid: $0.episodeUuid) }
        if !episodes.isEmpty {
            _ = DataManager.sharedManager.add(episodes: episodes, to: playlist)
        }
    }

    /// Removes the local mirror after unsubscribe/leave.
    static func removeMirror(for listId: Int64) {
        if let existing = DataManager.sharedManager.findPlaylist(uuid: mirrorUuid(for: listId)) {
            DataManager.sharedManager.delete(playlist: existing)
        }
    }
}
