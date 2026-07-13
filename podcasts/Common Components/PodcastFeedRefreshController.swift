import Foundation

/// Owns a `CustomRefreshControl` and wires it up to a podcast feed reload:
/// invokes the supplied `perform` closure on pull, and observes
/// `PodcastFeedReloadNotification` to update the status text and dismiss the
/// control when the reload finishes.
///
/// The owner is responsible for assigning `refreshControl` to a scroll view.
@MainActor
final class PodcastFeedRefreshController {
    let refreshControl = CustomRefreshControl()

    var perform: (() -> Void)?

    private var messageTokens = [NotificationCenter.ObservationToken]()

    init() {
        refreshControl.perform = { [weak self] _ in
            self?.perform?()
        }

        let center = NotificationCenter.default
        messageTokens.append(center.addObserver(for: PodcastFeedReloadLoading.self) { [weak self] _ in
            self?.refreshControl.set(text: L10n.podcastFeedReloadLoading.uppercased())
        })
        messageTokens.append(center.addObserver(for: PodcastFeedReloadEpisodesFound.self) { [weak self] _ in
            self?.processRefreshCompleted(L10n.podcastFeedReloadNewEpisodesFound)
        })
        messageTokens.append(center.addObserver(for: PodcastFeedReloadNoEpisodesFound.self) { [weak self] _ in
            self?.processRefreshCompleted(L10n.podcastFeedReloadNoEpisodesFound)
        })
    }

    deinit {
        // Property reads must precede removeObserver(self); after it, deinit may
        // only touch nonisolated state (Swift 6.2 isolated-deinit rule).
        let tokens = messageTokens
        NotificationCenter.default.removeObserver(self)
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func processRefreshCompleted(_ message: String) {
        refreshControl.set(text: message.uppercased())
        refreshControl.endRefreshing()
    }
}
