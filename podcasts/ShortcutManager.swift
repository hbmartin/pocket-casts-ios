import PocketCastsDataModel
import UIKit
import Combine
import PocketCastsUtils

class ShortcutManager: CustomObserver {

    private var cancelable: Cancellable?

    func listenForShortcutChanges() {
        //Cleans up existing observers
        stopListeningForShortcutChanges()

        let notifications: [NSNotification.Name] = [Constants.Notifications.playbackStarted,
                                                    Constants.Notifications.playbackPaused,
                                                    Constants.Notifications.playbackEnded,
                                                    Constants.Notifications.playlistChanged,
                                                    Constants.Notifications.podcastAdded,
                                                    Constants.Notifications.episodePlayStatusChanged,
                                                    Constants.Notifications.episodeArchiveStatusChanged,
                                                    Constants.Notifications.episodeStarredChanged,
                                                    Constants.Notifications.episodeDownloadStatusChanged,
                                                    Constants.Notifications.manyEpisodesChanged]

        let mergedNotifications = notifications
            .map { NotificationCenter.default.publisher(for: $0) }
            .reduce(Empty<Notification, Never>().eraseToAnyPublisher()) { acc, pub in
                acc.merge(with: pub).eraseToAnyPublisher()
            }
            .debounce(for: .seconds(3), scheduler: RunLoop.main)

        cancelable = mergedNotifications.sink { [weak self] _ in
            self?.shortcutsRequireUpdate()
        }

        shortcutsRequireUpdate()
    }

    func stopListeningForShortcutChanges() {
        cancelable?.cancel()
        cancelable = nil
    }

    @objc private func shortcutsRequireUpdate() {
        DispatchQueue.global().async {
            Self.updateShortcuts()
        }
    }

    nonisolated private static func updateShortcuts() {
        var shortcutItems = [UIMutableApplicationShortcutItem]()

        // top playlist
        if let topPlaylist = DataManager.sharedManager.allPlaylists(includeDeleted: false).first, let iconName = topPlaylist.iconImageName() {
            shortcutItems.append(
                UIMutableApplicationShortcutItem(
                    type: "au.com.shiftyjelly.podcasts",
                    localizedTitle: topPlaylist.playlistName,
                    localizedSubtitle: "\(DataManager.sharedManager.episodeCount(for: topPlaylist, episodeUuidToAdd: topPlaylist.episodeUuidToAddToQueries())) items",
                    icon: UIApplicationShortcutIcon(templateImageName: iconName),
                    userInfo: ["url": "thcast://shortcuts/filter/\(topPlaylist.uuid)" as NSSecureCoding]
                )
            )
        }

        let playbackSnapshot = PlaybackManager.onMainSync { ($0.currentEpisode(), $0.playing()) }
        if let currentEpisode = playbackSnapshot.0 {
            // add a play/pause shortcut
            if playbackSnapshot.1 {
                shortcutItems.append(
                    UIMutableApplicationShortcutItem(
                        type: "au.com.shiftyjelly.podcasts",
                        localizedTitle: L10n.pause,
                        localizedSubtitle: currentEpisode.displayableTitle(),
                        icon: UIApplicationShortcutIcon(type: .pause),
                        userInfo: ["url": "thcast://shortcuts/pause" as NSSecureCoding]
                    )
                )
            } else {
                shortcutItems.append(
                    UIMutableApplicationShortcutItem(
                        type: "au.com.shiftyjelly.podcasts",
                        localizedTitle: L10n.play,
                        localizedSubtitle: currentEpisode.displayableTitle(),
                        icon: UIApplicationShortcutIcon(type: .play),
                        userInfo: ["url": "thcast://shortcuts/play" as NSSecureCoding]
                    )
                )
            }
        } else {
            // discover
            shortcutItems.append(
                UIMutableApplicationShortcutItem(
                    type: "au.com.shiftyjelly.podcasts",
                    localizedTitle: "Find New Podcasts",
                    localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(type: .search),
                    userInfo: ["url": "thcast://shortcuts/discover" as NSSecureCoding]
                )
            )
        }

        let boxedItems = PocketCastsUtils.UncheckedSendable(shortcutItems)
        Task { @MainActor in
            UIApplication.shared.shortcutItems = boxedItems.value
        }
    }
}
