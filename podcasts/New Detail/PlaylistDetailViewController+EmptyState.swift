import PocketCastsUtils
import UIKit

extension PlaylistDetailViewController {
    private var emptyStateTitle: String {
        if viewModel.isManualPlaylist {
            return viewModel.hasSubscribedPodcasts ? L10n.playlistManualEmptyStateTitle : L10n.playlistManualEmptyStateTitleNoPodcasts
        }
        return L10n.episodeFilterNoEpisodesTitle.sentenceCased
    }

    private var emptyStateDescription: String? {
        if viewModel.isManualPlaylist {
            return viewModel.hasSubscribedPodcasts ? nil : L10n.playlistManualEmptyStateSubtitleNoPodcasts
        }
        return L10n.playlistSmartNoEpisodesMsg
    }

    private var emptyStateImage: UIImage? {
        return UIImage(named: viewModel.isManualPlaylist ? "playlists_tab" : "empty-playlist-info")
    }

    private var emptyStateButtonTitle: String {
        if viewModel.isManualPlaylist {
            return viewModel.hasSubscribedPodcasts ? L10n.playlistManualAddEpisodes : L10n.playlistManualBrowseShowsTitle
        }
        return L10n.playlistSmartRulesTitle
    }

    func reloadEmptyState() {
        if viewModel.isSearching { return }

        var config: UIContentConfiguration?

        UIView.animate(withDuration: 0.3) {
            self.tableView.isHidden = self.viewModel.shouldShowEmptyPlaceholder
        }

        updateNavTitleVisibility(animated: false)

        if viewModel.shouldShowEmptyPlaceholder {
            // Empty State when playlists is empty
            config = ContentUnavailableConfiguration.nativeEmptyState(
                title: emptyStateTitle,
                message: emptyStateDescription,
                image: emptyStateImage,
                action: .init(title: emptyStateButtonTitle) { [weak self] in
                    self?.emptyStateAction()
                }
            )
        }
        set(configuration: config)
    }

    func set(configuration: UIContentConfiguration?) {
        self.contentUnavailableConfiguration = configuration
    }

    private func emptyStateAction() {
        if !viewModel.isManualPlaylist {
            track(.filterEditRulesCtaEmptyTapped)
            editPlaylist()
            return
        }
        if viewModel.hasSubscribedPodcasts {
            track(.filterAddEpisodesCtaEmptyTapped)
            addEpisodes()
            return
        }
        track(.filterBrowseShowsCtaEmptyTapped)
        NavigationManager.sharedManager.navigateTo(NavigationManager.explorePageKey)
    }
}
