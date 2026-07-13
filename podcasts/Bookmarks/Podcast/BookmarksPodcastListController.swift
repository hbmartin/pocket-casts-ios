import Combine
import Dependencies
import PocketCastsDataModel
import SwiftUI

class BookmarksPodcastListController: ThemedHostingController<BookmarksPodcastListView> {
    @Dependency(\.playbackManager) private var playbackManager: any PlaybackManaging
    private let bookmarkManager: BookmarkManager
    private let viewModel: BookmarkPodcastListViewModel

    init(podcast: Podcast) {
        @Dependency(\.playbackManager) var playbackManager
        let bookmarkManager = playbackManager.bookmarkManager
        self.bookmarkManager = bookmarkManager

        let sortOption = Settings.podcastBookmarksSort
        let viewModel = BookmarkPodcastListViewModel(podcast: podcast,
                                                      bookmarkManager: bookmarkManager,
                                                      sortOption: sortOption)
        viewModel.analyticsSource = .podcasts

        self.viewModel = viewModel
        super.init(rootView: .init(viewModel: viewModel))

        viewModel.router = self
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - BookmarkListRouter

extension BookmarksPodcastListController: BookmarkListRouter {
    func bookmarkPlay(_ bookmark: Bookmark) {
        playbackManager.playBookmark(bookmark, source: viewModel.analyticsSource)
    }

    func bookmarkEdit(_ bookmark: Bookmark) {
        let controller = BookmarkEditTitleViewController(manager: bookmarkManager, bookmark: bookmark, state: .updating)
        controller.source = viewModel.analyticsSource

        present(controller, animated: true)
    }

    func bookmarkShare(_ bookmark: Bookmark) {
        guard let episode = bookmark.episode as? Episode else {
            return
        }
        Analytics.track(.bookmarkShareTapped, source: viewModel.analyticsSource, properties: ["podcast_uuid": episode.podcastUuid, "episode_uuid": bookmark.episodeUuid])
        SharingModal.show(option: .option(for: bookmark, episode: episode), from: .podcastScreen, in: self)
    }

    func dismissBookmarksList() {
        dismiss(animated: true)
    }
}
