import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

nonisolated enum PodcastFeedReloadNotification {
    public static let loading = NSNotification.Name(rawValue: "PodcastFeedReloadNotificationLoading")
    public static let episodesFound = NSNotification.Name(rawValue: "PodcastFeedReloadNotificationEpisodesFound")
    public static let noEpisodesFound = NSNotification.Name(rawValue: "PodcastFeedReloadNotificationNoEpisodesFound")
}

/// A podcast feed reload started (pull-to-refresh); the refresh control shows
/// its loading text. No payload.
nonisolated struct PodcastFeedReloadLoading: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { PodcastFeedReloadNotification.loading }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A podcast feed reload finished and found new episodes. No payload.
nonisolated struct PodcastFeedReloadEpisodesFound: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { PodcastFeedReloadNotification.episodesFound }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A podcast feed reload finished without new episodes. No payload.
nonisolated struct PodcastFeedReloadNoEpisodesFound: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { PodcastFeedReloadNotification.noEpisodesFound }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

@MainActor
class PodcastFeedViewModel {
    enum LoadingState {
        case idle
        case loading
        case cancelled
    }

    let uuid: String?

    private(set) var loadingState: LoadingState = .idle
    private var podcastFeedReloadTask: Task<Bool, Never>?

    init(uuid: String?) {
        self.uuid = uuid
    }

    func cancelTask() {
        if loadingState == .loading,
           let task = podcastFeedReloadTask,
           !task.isCancelled {
            loadingState = .cancelled
            task.cancel()
        }
    }

    func checkIfNewEpisodesAreAvailable(from source: PodcastFeedReloadSource) async -> Bool {
        // This runs on the main actor and `Podcast` is non-Sendable, so the lookup can't move
        // off-main without sending the result back across an isolation boundary (a warning the
        // GRDB-model Sendable work will resolve). The single indexed read is cheap enough here.
        guard let uuid, let podcast = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) else {
            return false
        }

        FileLog.shared.console("Reload podcast feed for podcast \(uuid) - last episode \(podcast.latestEpisodeUuid ?? "none")")

        // This Task inherits the class's @MainActor isolation, so its body already runs on the main actor.
        podcastFeedReloadTask = Task { [weak self] in
            guard let self else { return false }
            self.loadingState = .loading

            Analytics.track(.podcastScreenRefreshEpisodeList, properties: ["action": source.analyticsValue, "podcast_uuid": uuid])

            if source == .refreshControl {
                NotificationCenter.postOnMainThread(PodcastFeedReloadLoading())
            } else {
                Toast.show(L10n.podcastFeedReloadLoading, dismissAfter: .never)
            }

            let success: Bool
            do {
                success = try await MainServerHandler.shared.updatePodcast(uuid: uuid, lastEpisodeUuid: podcast.latestEpisodeUuid)
            } catch {
                success = false
                FileLog.shared.console("Failed update podcast \(uuid) - \(error.localizedDescription)")
            }

            if success {
                FileLog.shared.console("Refresh manager update podcast \(uuid)")
                await RefreshManager.shared.refresh(podcast: podcast, from: uuid)
            }

            if self.loadingState != .cancelled {
                let event: AnalyticsEvent = success ? .podcastScreenRefreshNewEpisodeFound : .podcastScreenRefreshNoEpisodesFound
                Analytics.track(event, properties: ["action": source.analyticsValue, "podcast_uuid": uuid])

                if source == .refreshControl {
                    if success {
                        NotificationCenter.postOnMainThread(PodcastFeedReloadEpisodesFound())
                    } else {
                        NotificationCenter.postOnMainThread(PodcastFeedReloadNoEpisodesFound())
                    }
                } else {
                    let message = success ? L10n.podcastFeedReloadNewEpisodesFound : L10n.podcastFeedReloadNoEpisodesFound
                    Toast.show(message)
                }
            }
            self.loadingState = .idle
            return success
        }
        return await podcastFeedReloadTask?.value ?? false
    }
}
