import Foundation
import PocketCastsServer

/// Owns a `CustomRefreshControl` and wires it up to a "full sync" refresh:
/// triggers `RefreshManager.shared.refreshPodcasts()` on pull, and observes
/// the resulting server/sync notifications to update the status text and
/// dismiss the control when the sync finishes.
///
/// The owner is responsible for assigning `refreshControl` to a scroll view.
@MainActor
final class FullSyncRefreshController {
    let refreshControl = CustomRefreshControl()

    private let source: AnalyticsSource

    private var messageTokens: [NotificationCenter.ObservationToken] = []

    init(source: AnalyticsSource) {
        self.source = source

        refreshControl.perform = { [weak self] _ in
            self?.beginRefreshing()
        }

        let center = NotificationCenter.default
        // opmlImportCompleted has no typed message struct yet; the bridge keeps
        // the string observer working.
        center.addObserver(self, selector: #selector(podcastsRefreshed), name: Constants.Notifications.opmlImportCompleted, object: nil)

        messageTokens = [
            center.addObserver(for: PodcastsRefreshed.self) { [weak self] _ in
                self?.podcastsRefreshed()
            },
            center.addObserver(for: PodcastRefreshFailed.self) { [weak self] _ in
                self?.podcastRefreshFailed()
            },
            center.addObserver(for: SyncCompleted.self) { [weak self] _ in
                self?.syncCompleted()
            },
            center.addObserver(for: PodcastRefreshThrottled.self) { [weak self] _ in
                self?.syncCompleted()
            },
            center.addObserver(for: SyncFailed.self) { [weak self] _ in
                self?.syncFailed()
            }
        ]
    }

    // isolated deinit: main-actor-owned helper; deinit removes isolated observation tokens
    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        for token in messageTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func beginRefreshing() {
        refreshControl.set(text: L10n.refreshControlFetchingEpisodes)
        RefreshManager.shared.refreshPodcasts()
        Analytics.track(.pulledToRefresh, properties: ["source": source])
    }

    @objc private func podcastsRefreshed() {
        if SyncManager.isUserLoggedIn() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.refreshControl.isRefreshing else { return }
                self.refreshControl.set(text: L10n.refreshControlSyncingPodcasts)
            }
            return
        }
        finishRefreshing(message: L10n.refreshControlRefreshComplete)
    }

    private func podcastRefreshFailed() {
        finishRefreshing(message: L10n.refreshControlRefreshFailed)
    }

    private func syncCompleted() {
        finishRefreshing(message: L10n.refreshControlRefreshComplete)
    }

    private func syncFailed() {
        finishRefreshing(message: L10n.refreshControlSyncFailed)
    }

    private func finishRefreshing(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.refreshControl.isRefreshing else { return }
            self.refreshControl.set(text: message)
            self.refreshControl.endRefreshing()
        }
    }
}
