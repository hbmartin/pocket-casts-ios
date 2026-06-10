import Foundation
import PocketCastsDataModel

/// Generated protocol mock for `UserEpisodeRepository`. Stub return values by selector:
/// `mock.stub("findPodcast(uuid:includeUnsubscribed:)", with: podcast)`.
public final class UserEpisodeRepositoryMock: RepositoryMock, UserEpisodeRepository {
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

    public func allUserEpisodesUploaded() -> [UserEpisode] {
        record("allUserEpisodesUploaded()")
        return stubs["allUserEpisodesUploaded()"] as? [UserEpisode] ?? []
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

    public func saveEpisode(uploadStatus: UploadStatus, episode: UserEpisode) {
        record("saveEpisode(uploadStatus:episode:)")
    }

    public func saveEpisode(uploadStatus: UploadStatus, uploadTaskId: String?, episode: UserEpisode) {
        record("saveEpisode(uploadStatus:uploadTaskId:episode:)")
    }

    public func saveEpisode(uploadStatus: UploadStatus, uploadError: String?, uploadTaskId: String?, episode: UserEpisode) {
        record("saveEpisode(uploadStatus:uploadError:uploadTaskId:episode:)")
    }

    public func clearUploadTaskId(episode: UserEpisode) {
        record("clearUploadTaskId(episode:)")
    }

    public func findUserEpisode(uploadTaskId: String) -> UserEpisode? {
        record("findUserEpisode(uploadTaskId:)")
        return stubs["findUserEpisode(uploadTaskId:)"] as? UserEpisode
    }

    public func findUserEpisodesWithUploadStatus(_ status: UploadStatus) -> [UserEpisode] {
        record("findUserEpisodesWithUploadStatus(_:)")
        return stubs["findUserEpisodesWithUploadStatus(_:)"] as? [UserEpisode] ?? []
    }

    public func findUserEpisodesWhereNotNull(propertyName: String) -> [UserEpisode] {
        record("findUserEpisodesWhereNotNull(propertyName:)")
        return stubs["findUserEpisodesWhereNotNull(propertyName:)"] as? [UserEpisode] ?? []
    }

    public func markImageUploaded(episode: UserEpisode) {
        record("markImageUploaded(episode:)")
    }

    public func removeOrphanedUserEpisodes() {
        record("removeOrphanedUserEpisodes()")
    }
}
