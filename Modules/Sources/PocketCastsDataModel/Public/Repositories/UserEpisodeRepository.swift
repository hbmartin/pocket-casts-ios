import Foundation

/// Read and mutate user-uploaded episodes (Files).
///
/// `DataManager` is the production conformer; inject `any UserEpisodeRepository` (see
/// `Repositories+Dependency.swift`) so consumers can be tested with mocks and a
/// future persistence engine can ship as a second conformer.
public protocol UserEpisodeRepository: AnyObject {
    func findUserEpisode(uuid: String) -> UserEpisode?
    func allUserEpisodes(sortedBy: UploadedSort, limit: Int?) -> [UserEpisode]
    func allUserEpisodesDownloaded(sortedBy: UploadedSort, limit: Int?) -> [UserEpisode]
    func allUserEpisodesUploaded() -> [UserEpisode]
    func bulkSave(episodes: [UserEpisode])
    func delete(userEpisodeUuid: String)
    func deleteUserEpisodes(userEpisodeUuids: [String])
    func saveEpisode(uploadStatus: UploadStatus, episode: UserEpisode)
    func saveEpisode(uploadStatus: UploadStatus, uploadTaskId: String?, episode: UserEpisode)
    func saveEpisode(uploadStatus: UploadStatus, uploadError: String?, uploadTaskId: String?, episode: UserEpisode)
    func clearUploadTaskId(episode: UserEpisode)
    func findUserEpisode(uploadTaskId: String) -> UserEpisode?
    func findUserEpisodesWithUploadStatus(_ status: UploadStatus) -> [UserEpisode]
    func findUserEpisodesWhereNotNull(propertyName: String) -> [UserEpisode]
    func markImageUploaded(episode: UserEpisode)
    func removeOrphanedUserEpisodes()

    // MARK: Async variants

    // The returned models are mutable reference types: treat them as owned by
    // the awaiting task. The default implementations run the synchronous
    // requirement on a background queue; conformers can override with natively
    // async reads.
    func findUserEpisodeAsync(uuid: String) async -> UserEpisode?
}

public extension UserEpisodeRepository {
    // Conveniences mirroring DataManager's default arguments, which protocol
    // requirements cannot express.
    func allUserEpisodes(sortedBy: UploadedSort) -> [UserEpisode] {
        allUserEpisodes(sortedBy: sortedBy, limit: nil)
    }

    func allUserEpisodesDownloaded(sortedBy: UploadedSort) -> [UserEpisode] {
        allUserEpisodesDownloaded(sortedBy: sortedBy, limit: nil)
    }

    func findUserEpisodeAsync(uuid: String) async -> UserEpisode? {
        await runOffMainThread { self.findUserEpisode(uuid: uuid) }
    }
}

extension DataManager: UserEpisodeRepository {}
