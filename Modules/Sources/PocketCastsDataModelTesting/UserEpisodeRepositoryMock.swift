import Foundation
import PocketCastsDataModel

/// Generated protocol mock for `UserEpisodeRepository`. Stub return values by selector.
// @unchecked Sendable: restates RepositoryMock's conformance; state stays lock-guarded in the base class.
public final class UserEpisodeRepositoryMock: RepositoryMock, UserEpisodeRepository, @unchecked Sendable {
    public func findUserEpisode(uuid: String) -> UserEpisode? {
        record("findUserEpisode(uuid:)")
        return stubs["findUserEpisode(uuid:)"] as? UserEpisode
    }

    public func allUserEpisodes(sortedBy: UploadedSort, limit: Int?) -> [UserEpisode] {
        record("allUserEpisodes(sortedBy:limit:)")
        return stubs["allUserEpisodes(sortedBy:limit:)"] as? [UserEpisode] ?? []
    }

    public func allUserEpisodesDownloaded(sortedBy: UploadedSort, limit: Int?) -> [UserEpisode] {
        record("allUserEpisodesDownloaded(sortedBy:limit:)")
        return stubs["allUserEpisodesDownloaded(sortedBy:limit:)"] as? [UserEpisode] ?? []
    }

    public func bulkSave(episodes: [UserEpisode]) {
        record("bulkSave(episodes:)")
    }

    public func delete(userEpisodeUuid: String) {
        record("delete(userEpisodeUuid:)")
    }

    public func deleteUserEpisodes(userEpisodeUuids: [String]) {
        record("deleteUserEpisodes(userEpisodeUuids:)")
    }

    public func findUserEpisodesWhereNotNull(propertyName: String) -> [UserEpisode] {
        record("findUserEpisodesWhereNotNull(propertyName:)")
        return stubs["findUserEpisodesWhereNotNull(propertyName:)"] as? [UserEpisode] ?? []
    }

    public func removeOrphanedUserEpisodes() {
        record("removeOrphanedUserEpisodes()")
    }
}
