import Dependencies
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

@MainActor
class UpNextHistoryModel: ObservableObject {
    @Published var historyEntries: [UpNextHistoryManager.UpNextHistoryEntry] = []
    @Published var episodes: [BaseEpisode] = []

    @Dependency(\.upNextRepository) private var upNextRepository
    @Dependency(\.episodeRepository) private var episodeRepository
    @Dependency(\.playbackManager) private var playbackManager

    func loadEntries() {
        Task {
            historyEntries = upNextRepository.upNextHistoryEntries()
        }
    }

    func loadEpisodes(for entry: Date) {
        Task {
            let episodesUuid = upNextRepository.upNextHistoryEpisodes(entry: entry)
            episodes = episodesUuid.compactMap { episodeRepository.findBaseEpisode(uuid: $0) }
        }
    }

    nonisolated func reAddMissingItems(entry: Date) {
        Task { @MainActor in
            let episodesUuid = upNextRepository.upNextHistoryEpisodes(entry: entry)
            FileLog.shared.addMessage("UpNextHistory: Restoring entries from \(entry) with episodes: [\(episodesUuid.joined(separator: ","))]")
            episodesUuid.forEach { episodeUuid in
                if let episode = episodeRepository.findBaseEpisode(uuid: episodeUuid) {
                    playbackManager.addToUpNext(episode: episode, ignoringQueueLimit: true, userInitiated: false)
                }
            }
            playbackManager.upNextBulkOperationDidComplete()
            playbackManager.refreshUpNextList(checkForAutoDownload: false)

            let upNextQueueCount = playbackManager.upNextQueueCount()
            FileLog.shared.addMessage("UpNextHistory: Restored Up Next Queue to \(upNextQueueCount) episodes")
        }
    }

    func createSnapshot() {
        upNextRepository.snapshotUpNext()
    }
}
