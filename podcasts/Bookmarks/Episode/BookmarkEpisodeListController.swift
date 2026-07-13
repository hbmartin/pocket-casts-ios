import Combine
import Dependencies
import PocketCastsDataModel
import SwiftUI

class BookmarkEpisodeListController: ThemedHostingController<BookmarkEpisodeListView> {
    @Dependency(\.playbackManager) private var playbackManager: any PlaybackManaging
    private let bookmarkManager: BookmarkManager
    let viewModel: BookmarkEpisodeListViewModel

    private var cancellables = Set<AnyCancellable>()

    init(episode: BaseEpisode, displayMode: BookmarkEpisodeListView.DisplayMode = .list,
         themeOverride: Theme.ThemeType? = nil) {

        @Dependency(\.playbackManager) var playbackManager
        let bookmarkManager = playbackManager.bookmarkManager
        self.bookmarkManager = bookmarkManager

        let viewModel = BookmarkEpisodeListViewModel(episode: episode,
                                                      bookmarkManager: bookmarkManager,
                                                      sortOption: Settings.episodeBookmarksSort)
        viewModel.analyticsSource = (episode is Episode) ? .episodes : .files

        self.viewModel = viewModel

        if let themeOverride {
            super.init(rootView: BookmarkEpisodeListView(viewModel: viewModel, style: OverrideThemedBookmarksStyle(overrideTheme: themeOverride), displayMode: displayMode))
        } else {
            super.init(rootView: BookmarkEpisodeListView(viewModel: viewModel, displayMode: displayMode))
        }

        viewModel.router = self
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - BookmarkListRouter

extension BookmarkEpisodeListController: BookmarkListRouter {
    func bookmarkPlay(_ bookmark: Bookmark) {
        playbackManager.playBookmark(bookmark, source: viewModel.analyticsSource)
    }

    func bookmarkEdit(_ bookmark: Bookmark) {
        let controller = BookmarkEditTitleViewController(manager: bookmarkManager,
                                                         bookmark: bookmark,
                                                         state: .updating)

        controller.source = viewModel.analyticsSource

        present(controller, animated: true)
    }

    func bookmarkShare(_ bookmark: Bookmark) {
        guard let episode = viewModel.episode as? Episode else {
            return
        }
        Analytics.track(.bookmarkShareTapped, source: viewModel.analyticsSource, properties: ["podcast_uuid": episode.podcastUuid, "episode_uuid": bookmark.episodeUuid])

        SharingModal.show(option: .option(for: bookmark, episode: episode), from: .episodeDetail, in: self)
    }

    func dismissBookmarksList() {
        dismiss(animated: true)
    }
}
