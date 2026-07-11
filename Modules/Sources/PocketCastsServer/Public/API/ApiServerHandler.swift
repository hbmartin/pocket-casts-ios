import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import SwiftProtobuf
import Synchronization

public final class ApiServerHandler: Sendable {
    public static let shared = ApiServerHandler()

    let apiQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    private let lastUpToSaved = Mutex<Date?>(nil)
    public class func saveUpTo(time: TimeInterval, duration: TimeInterval, episode: BaseEpisode) {
        // Fetched outside the lock so no delegate code runs while it is held.
        let minTimeBetweenProgressSaves = ServerConfig.shared.syncDelegate?.minTimeBetweenProgressSaves()
        let shouldSave = shared.lastUpToSaved.withLock { lastSaved in
            if let lastSaved, let minTimeBetweenProgressSaves, fabs(lastSaved.timeIntervalSinceNow) < minTimeBetweenProgressSaves {
                return false
            }
            lastSaved = Date()
            return true
        }
        guard shouldSave else { return }

        if let episode = episode as? Episode {
            let saveOperation = PositionSyncTask(upTo: time, duration: duration, episode: episode)
            shared.apiQueue.addOperation(saveOperation)
        }
    }

    public func saveCompleted(episode: BaseEpisode) {
        if let episode = episode as? Episode {
            let saveOperation = PositionSyncTask(upTo: episode.playedUpTo, duration: episode.duration, episode: episode)
            apiQueue.addOperation(saveOperation)
        }
    }

    public func saveStarred(episode: Episode) {
        let operation = StarredSyncTask(episode: episode)
        apiQueue.addOperation(operation)
    }

    public func retrieveStarred(completion: @escaping ([Episode]?) -> Void) {
        let retrieveTask = RetrieveStarredTask()
        retrieveTask.completion = completion
        apiQueue.addOperation(retrieveTask)
    }

    public func deleteAccount(completion: @escaping (Bool, String?) -> Void) {
        let deleteAccountTask = DeleteAccountTask()
        deleteAccountTask.completion = completion
        apiQueue.addOperation(deleteAccountTask)
    }

    public func loadStatsRequest(getFullData: Bool = false, completion: @escaping (RemoteStats?) -> Void) {
        let statsOperation = RetrieveStatsTask()
        statsOperation.getFullStatsData = getFullData
        statsOperation.completion = completion
        apiQueue.addOperation(statsOperation)
    }

    public func retrieveEpisodeTaskSynchronouusly(podcastUuid: String) -> ([EpisodeSyncInfo]?) {
        let retrieveTask = RetrieveEpisodesTask(podcastUuid: podcastUuid)
        var retrievedEpisodes: [EpisodeSyncInfo]?
        retrieveTask.completion = { episodes in
            retrievedEpisodes = episodes
        }
        retrieveTask.runTaskSynchronously()
        return retrievedEpisodes
    }

    public func syncSettings() {
        let syncSettingsTask = SyncSettingsTask()
        apiQueue.addOperation(syncSettingsTask)
    }

    public func reloadFoldersFromServer() {
        ServerSettings.setHomeGridNeedsRefresh(true)
        RefreshManager.shared.refreshPodcasts(forceEvenIfRefreshedRecently: true)
    }

    /// Swaps the current auth token with one scoped for use in Sonos connections
    /// - Returns: The auth token or nil if it failed for any reason
    public func exchangeSonosToken() async -> String? {
        let token = await withCheckedContinuation { continuation in
            let task = ExchangeSonosTask()

            task.completion = { token in
                continuation.resume(returning: token)
            }

            apiQueue.addOperation(task)
        }

        return token
    }
}
