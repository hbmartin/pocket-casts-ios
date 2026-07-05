import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

@MainActor
class UpNextHistoryModel: ObservableObject {
    @Published var historyEntries: [UpNextHistoryManager.UpNextHistoryEntry] = []
    @Published var episodes: [BaseEpisode] = []

    // Boxed so the nonisolated restore path can read it off the main actor
    private let dataManagerBox: PocketCastsUtils.UncheckedSendable<DataManager>

    private var dataManager: DataManager { dataManagerBox.value }

    init(dataManager: DataManager = DataManager.sharedManager) {
        self.dataManagerBox = PocketCastsUtils.UncheckedSendable(dataManager)
    }

    func loadEntries() {
        Task {
            historyEntries = dataManager.upNextHistoryEntries()
        }
    }

    func loadEpisodes(for entry: Date) {
        Task {
            let episodesUuid = dataManager.upNextHistoryEpisodes(entry: entry)
            episodes = episodesUuid.compactMap { dataManager.findBaseEpisode(uuid: $0) }
        }
    }

    nonisolated func reAddMissingItems(entry: Date) {
        let dataManagerBox = self.dataManagerBox
        Task {
            let dataManager = dataManagerBox.value
            let episodesUuid = dataManager.upNextHistoryEpisodes(entry: entry)
            FileLog.shared.addMessage("UpNextHistory: Restoring entries from \(entry) with episodes: [\(episodesUuid.joined(separator: ","))]")
            episodesUuid.forEach { episodeUuid in
                if let episode = dataManager.findBaseEpisode(uuid: episodeUuid) {
                    PlaybackManager.shared.addToUpNext(episode: episode, ignoringQueueLimit: true, userInitiated: false)
                }
            }
            PlaybackManager.shared.upNextBulkOperationDidComplete()
            PlaybackManager.shared.refreshUpNextList(checkForAutoDownload: false)

            let upNextQueueCount = PlaybackManager.shared.upNextQueueCount()
            FileLog.shared.addMessage("UpNextHistory: Restored Up Next Queue to \(upNextQueueCount) episodes")
        }
    }

    func createSnapshot() {
        dataManager.snapshotUpNext()
    }
}
