import Foundation
import PocketCastsDataModel
import PocketCastsServer
import Combine
import UserNotifications

class BadgeHelper {
    // isolated deinit: main-actor-owned helper; deinit removes isolated notification observers
    isolated deinit {
        teardown()
    }

    private var cancelable: Cancellable?
    private var messageTokens: [NotificationCenter.ObservationToken] = []

    /// Feeds the shared 3s debounce; typed observers and string publishers both
    /// funnel through it so a burst of mixed events still badges only once.
    private let updateRequests = PassthroughSubject<Void, Never>()

    func setup() {
        teardown()

        // Names whose domains have no typed message structs yet (playback 5.2,
        // playlist 5.4, OPML) stay on the string API; the bridge keeps them firing.
        let stringNotifications: [NSNotification.Name] = [Constants.Notifications.playlistChanged,
                                                          Constants.Notifications.opmlImportCompleted,
                                                          Constants.Notifications.playbackTrackChanged,
                                                          Constants.Notifications.playbackEnded,
                                                          Constants.Notifications.playbackStarted]

        let mergedNotifications = stringNotifications
            .map { NotificationCenter.default.publisher(for: $0).map { _ in () }.eraseToAnyPublisher() }
            .reduce(updateRequests.eraseToAnyPublisher()) { acc, pub in
                acc.merge(with: pub).eraseToAnyPublisher()
            }
            .debounce(for: .seconds(3), scheduler: RunLoop.main)

        cancelable = mergedNotifications.sink { [weak self] _ in
            self?.updateBadge()
        }

        messageTokens = [
            NotificationCenter.default.addObserver(for: EpisodePlayStatusChanged.self) { [weak self] _ in
                self?.updateRequests.send()
            },
            NotificationCenter.default.addObserver(for: EpisodeArchiveStatusChanged.self) { [weak self] _ in
                self?.updateRequests.send()
            },
            NotificationCenter.default.addObserver(for: EpisodeStarredChanged.self) { [weak self] _ in
                self?.updateRequests.send()
            },
            NotificationCenter.default.addObserver(for: EpisodeDownloadStatusChanged.self) { [weak self] _ in
                self?.updateRequests.send()
            },
            NotificationCenter.default.addObserver(for: EpisodeDownloaded.self) { [weak self] _ in
                self?.updateRequests.send()
            },
            NotificationCenter.default.addObserver(for: ManyEpisodesChanged.self) { [weak self] _ in
                self?.updateRequests.send()
            },
            NotificationCenter.default.addObserver(for: PodcastsRefreshed.self) { [weak self] _ in
                self?.updateRequests.send()
            }
        ]
    }

    func teardown() {
        cancelable?.cancel()
        cancelable = nil

        for token in messageTokens {
            NotificationCenter.default.removeObserver(token)
        }
        messageTokens.removeAll()
    }

    func updateBadge() {
        guard let badgeSetting = Settings.appBadge else { return }

        let pushOn = NotificationsHelper.shared.pushEnabled()

        if badgeSetting == .off && !pushOn { return } // user has both the badge and push turned off, don't attempt to badge their app. Results in iOS 8 push message request popup

        if badgeSetting == .off || !pushOn {
            clearBadge(clearNotificationsToo: false)
        } else if badgeSetting == .totalUnplayed {
            let unplayedCount = DataManager.sharedManager.subscribedUnplayedEpisodeCount()
            setBadgeTo(unplayedCount)
        } else if badgeSetting == .newSinceLastOpened {
            guard let lastClosedDate = UserDefaults.standard.object(forKey: Constants.UserDefaults.lastAppCloseDate) as? Date else {
                clearBadge(clearNotificationsToo: false)

                return
            }

            let newCount = DataManager.sharedManager.subscribedUnplayedEpisodeCount(addedAfter: lastClosedDate)
            setBadgeTo(newCount)
        } else if badgeSetting == .filterCount {
            guard let playlistId = Settings.appBadgeFilterUuid else {
                Settings.appBadge = .off

                return
            }

            guard let playlist = DataManager.sharedManager.findPlaylist(uuid: playlistId) else {
                Settings.appBadge = .off

                return
            }

            let episodeCount = DataManager.sharedManager.episodeCount(for: playlist, episodeUuidToAdd: playlist.episodeUuidToAddToQueries())
            setBadgeTo(episodeCount)
        }
    }

    func clearNotifications() {
        clearBadge(clearNotificationsToo: true)
        updateBadge()
    }

    private func clearBadge(clearNotificationsToo: Bool) {
        let notificationCenter = UNUserNotificationCenter.current()
        if clearNotificationsToo {
            notificationCenter.removeAllDeliveredNotifications()
        }
        notificationCenter.setBadgeCount(0)
    }

    private func setBadgeTo(_ badgeNumber: Int) {
        UNUserNotificationCenter.current().setBadgeCount(badgeNumber)
    }
}
