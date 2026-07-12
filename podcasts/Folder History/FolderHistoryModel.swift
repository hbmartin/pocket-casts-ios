import Dependencies
import PocketCastsDataModel
import PocketCastsServer

class FolderHistoryModel: ObservableObject {
    @Published var historyEntries: [FolderHistoryManager.PodcastFoldersHistoryEntry] = []
    @Published var podcastsAndFolders: [(Podcast, Folder)] = []

    @Dependency(\.folderRepository) private var folderRepository: any FolderRepository
    @Dependency(\.podcastRepository) private var podcastRepository: any PodcastRepository

    @MainActor
    func loadEntries() {
        Task {
            historyEntries = folderRepository.foldersHistoryEntries()
        }
    }

    @MainActor
    func loadFoldersHistory(for entry: Date) {
        Task {
            podcastsAndFolders = folderRepository.folderHistory(entry: entry).compactMap {
                if let podcast = podcastRepository.findPodcast(uuid: $0.key),
                   let folder = folderRepository.findFolder(uuid: $0.value) {
                    return (podcast, folder)
                }

                return nil
            }
        }
    }

    func restore() {
        podcastsAndFolders.forEach { podcast, folder in
            var podcast = podcast
            podcast.folderUuid = folder.uuid
            podcast.syncStatus = SyncStatus.notSynced.rawValue
            podcastRepository.save(podcast: podcast)
            NotificationCenter.postOnMainThread(FolderChanged(uuid: folder.uuid))
        }
        RefreshManager.shared.refreshPodcasts(forceEvenIfRefreshedRecently: true)
        Toast.show(L10n.restoreFoldersSuccess)
    }
}
