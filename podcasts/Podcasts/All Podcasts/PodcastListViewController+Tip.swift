import SwiftUI
import TipKit
import PocketCastsUtils

/// Tip pointing at the podcasts list overflow button to introduce the "Recently Played" sort option.
///
/// Fresh installs never see it (invalidated in `AppDelegate`); it keeps showing until the user dismisses it.
nonisolated struct RecentlyPlayedSortingTip: Tip {
    var title: Text {
        Text(L10n.podcastsLibrarySortEpisodeRecentlyPlayedTipTitle)
    }

    var message: Text? {
        Text(L10n.podcastsLibrarySortEpisodeRecentlyPlayedTipDescription)
    }
}

extension PodcastListViewController: UIPopoverPresentationControllerDelegate {
    func showRecentlyPlayedSortingTipIfNeeded() {
        guard
            FeatureFlag.podcastsSortChanges.enabled,
            recentlyPlayedSortingTip == nil,
            let button = customRightBtn
        else {
            return
        }

        let tip = RecentlyPlayedSortingTip()
        guard tip.shouldDisplay else { return }

        let tipVC = TipUIPopoverViewController(tip, sourceItem: button)
        tipVC.presentationDelegate = self
        present(tipVC, animated: true) {
            Analytics.track(.episodeRecentlyPlayedSortOptionTooltipShown)
        }
        recentlyPlayedSortingTip = tipVC

        // Dismiss the popover once the tip is invalidated (eg: via its close button).
        Task { [weak self] in
            for await shouldDisplay in tip.shouldDisplayUpdates where !shouldDisplay {
                self?.recentlyPlayedSortingTipInvalidated()
                break
            }
        }
    }

    private func recentlyPlayedSortingTipInvalidated() {
        guard let tipVC = recentlyPlayedSortingTip else { return }
        recentlyPlayedSortingTip = nil
        Analytics.track(.episodeRecentlyPlayedSortOptionTooltipDismissed)
        tipVC.dismiss(animated: true)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        // Return no adaptive presentation style, use default presentation behaviour
        return .none
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        // The user dismissed the popover by tapping outside of it: treat that as closing the tip.
        guard recentlyPlayedSortingTip != nil else { return }
        recentlyPlayedSortingTip = nil
        Analytics.track(.episodeRecentlyPlayedSortOptionTooltipDismissed)
        RecentlyPlayedSortingTip().invalidate(reason: .tipClosed)
    }
}
