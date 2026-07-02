import Foundation
import PocketCastsDataModel

class PlaylistDetailFetchOperation: Operation, @unchecked Sendable {
    typealias CompletionHandler = ([ListEpisode], Int) -> Void

    private let episodesDataManager: EpisodesDataManager
    private let dataManager: DataManager
    private let playlist: EpisodeFilter
    private let completion: CompletionHandler
    private let shouldShowArchived: Bool
    private let searchTerm: String?

    init(
        dataManager: DataManager = .sharedManager,
        episodesDataManager: EpisodesDataManager = .init(),
        playlist: EpisodeFilter,
        shouldShowArchived: Bool = false,
        searchTerm: String? = nil,
        completion: @escaping CompletionHandler
    ) {
        self.dataManager = dataManager
        self.episodesDataManager = episodesDataManager
        self.playlist = playlist
        self.shouldShowArchived = shouldShowArchived
        self.searchTerm = searchTerm
        self.completion = completion

        super.init()
    }

    override func main() {
        autoreleasepool {
            if self.isCancelled { return }

            let newData: [ListEpisode]
            let archivedEpisodesCount: Int
            if let searchTerm {
                // Search fetch: show all matches regardless of archive state; archived count is
                // unused by the search path.
                newData = episodesDataManager.playlistEpisodes(for: playlist, limit: 0, shouldShowArchived: true, search: searchTerm)
                archivedEpisodesCount = 0
            } else {
                newData = episodesDataManager.playlistEpisodes(for: playlist, shouldShowArchived: shouldShowArchived)
                archivedEpisodesCount = dataManager.playlistArchivedEpisodeCount(
                    for: playlist,
                    episodeUuidToAdd: playlist.episodeUuidToAddToQueries()
                )
            }

            if self.isCancelled { return }

            DispatchQueue.main.sync { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.completion(newData, archivedEpisodesCount)
            }
        }
    }
}
