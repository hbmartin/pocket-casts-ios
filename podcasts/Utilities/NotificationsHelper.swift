
import PocketCastsDataModel
import PocketCastsServer
import UIKit
@preconcurrency import UserNotifications
import PocketCastsUtils

/// Stateless (constants only); UN-delegate callbacks arrive on arbitrary queues,
/// so the instance crosses isolation domains by contract.
nonisolated final class NotificationsHelper: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let downloadEpisodeActionId = "SJEpDownload"
    private let playNowActionid = "SJPlayNow"
    private let addToQueueFirstActionId = "SJEpAddQueueFirst"
    private let addToQueueLastActionId = "SJEpAddQueueLast"
    private let archiveActionId = "SJEpArchive"

    @objc static let shared = NotificationsHelper()

    enum NotificationsCategory: String {
        case deepLink = "DEEP_LINK"
        case episodes = "ep"
        case podcasts = "po"
        case social = "so"
    }

    func checkNotificationsDenied(completion: @escaping @Sendable (Bool) -> ()) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus == .denied)
        }
    }

    @objc func pushEnabled() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.notifications
        } else {
            UserDefaults.standard.bool(forKey: Constants.UserDefaults.pushEnabled)
        }
    }

    func enablePush() {
        if pushEnabled() { return } // already enabled

        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.notifications = true
        }
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.pushEnabled)
    }

    func disablePush() {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.notifications = false
        }
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.pushEnabled)
    }

    /// Calls registration APIs if push is enabled
    /// - Parameter checkToken: Whether to check the token before registering. This would be `false` on app launch but could be checked while app is running to avoid extra work.
    func register(checkToken: Bool) {
        guard pushEnabled(),
              checkToken == false || ServerSettings.pushToken() == nil
        else { return }
        registerForPushNotifications()
    }

    /// Handles a user-initiated change to per-podcast push notifications: requests permission if needed, persists the change, notifies observers, and shows a confirmation toast. Callers are responsible for tracking their own analytics event.
    func setNotificationsEnabled(_ enabled: Bool, for podcast: Podcast, completion: ((Podcast) -> Void)? = nil) {
        // The permission callback is @Sendable; the podcast and completion cross in
        // boxed and are used exactly once
        let box = PocketCastsUtils.UncheckedSendable((podcast, completion))
        registerForPushNotifications { granted in
            guard granted || !enabled else {
                Task { @MainActor in
                    Toast.show(L10n.notificationsPermissionsNeedsAction, actions: [.init(title: L10n.notificationsPermissionsOpenSettings, action: {
                        Analytics.track(.notificationsPermissionsOpenSystemSettings)
                        Task { @MainActor in
                            UIApplication.shared.openNotificationSettings()
                        }
                    })])
                }
                return
            }
            let (podcast, completion) = box.value
            let savedPodcast = PodcastManager.shared.setNotificationsEnabled(podcast: podcast, enabled: enabled)
            completion?(savedPodcast)
            NotificationCenter.postOnMainThread(PodcastUpdated(uuid: savedPodcast.uuid))
            var message = enabled ? L10n.notificationsOn : L10n.notificationsOff
            if let title = savedPodcast.title, enabled {
                message = L10n.notificationsOnForPodcast(title)
            }
            Task { @MainActor in Toast.show(message) }
        }
    }

    func registerForPushNotifications(completion: (@Sendable (Bool) -> ())? = nil) {
        let downloadAction = UNNotificationAction(identifier: downloadEpisodeActionId, title: L10n.download, options: [])
        let playNowAction = UNNotificationAction(identifier: playNowActionid, title: L10n.notificationsPlayNow, options: [])
        let addQueueFirstAction = UNNotificationAction(identifier: addToQueueFirstActionId, title: L10n.playNext, options: [])
        let addQueueLastAction = UNNotificationAction(identifier: addToQueueLastActionId, title: L10n.playLast, options: [])
        let archiveAction = UNNotificationAction(identifier: archiveActionId, title: L10n.archive, options: [])

        let episodeCategory = UNNotificationCategory(identifier: NotificationsCategory.episodes.rawValue, actions: [downloadAction, playNowAction, addQueueFirstAction, addQueueLastAction, archiveAction], intentIdentifiers: [], options: [])

        // multiple podcast episode actions
        let podcastCategory = UNNotificationCategory(identifier: NotificationsCategory.podcasts.rawValue, actions: [], intentIdentifiers: [], options: [])

        let deepLinkCategory = UNNotificationCategory(identifier: NotificationsCategory.deepLink.rawValue, actions: [], intentIdentifiers: [], options: [])

        let socialCategory = UNNotificationCategory(identifier: NotificationsCategory.social.rawValue, actions: [], intentIdentifiers: [], options: [])

        // register actions
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.setNotificationCategories([episodeCategory, podcastCategory, deepLinkCategory, socialCategory])

        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                let authorized = settings.authorizationStatus != .denied
                Task { @MainActor in
                    completion?(authorized)
                    UIApplication.shared.registerForRemoteNotifications()
                }
                return
            }

            notificationCenter.requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { granted, _ in
                if granted {
                    Analytics.track(.notificationsOptInAllowed)
                } else {
                    Analytics.track(.notificationsOptInDenied)
                }
                Task { @MainActor in
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    completion?(granted)
                }
            })

            Analytics.track(.notificationsOptInShown)
        }
    }

    // called when the user taps a notification action, or just the notification itself
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        FileLog.shared.addMessage("[Notifications] push notification received with category: \(response.notification.request.content.categoryIdentifier)")
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let category = NotificationsCategory(rawValue: categoryIdentifier)

        var properties: [String: String] = ["category": categoryIdentifier]
        let identifier = response.notification.request.identifier
        if let type = NotificationType(rawValue: identifier) {
            properties["type"] = type.rawValue
            NotificationsCoordinator.shared.markNotification(type)
        }
        Analytics.track(.notificationOpened, properties: properties)

        switch category {
        case .episodes, .podcasts, .none:
            handleEpisodeNotification(response: response, completionHandler: completionHandler)
        case .deepLink:
            handleDeepLinkNotification(response: response, completionHandler: completionHandler)
        case .social:
            handleSocialNotification(response: response, completionHandler: completionHandler)
        }
    }

    /// Social pushes (Slice 8, docs/Social.md): the server sends category "so"
    /// with a typed payload; each type deep-links to its home surface.
    private func handleSocialNotification(response: UNNotificationResponse, completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let rawType = Int(userInfo["social_type"] as? String ?? "") ?? 0
        let actorHandle = userInfo["actor_handle"] as? String ?? ""
        Analytics.track(.socialPushTapped, properties: ["social_type": "\(rawType)"])

        let episodeUuid = userInfo["episode_uuid"] as? String ?? ""
        let podcastUuid = userInfo["podcast_uuid"] as? String ?? ""
        let commentId = Int64(userInfo["comment_id"] as? String ?? "") ?? 0
        // The system only needs to know handling finished; routing continues
        // on the main actor with Sendable captures.
        completionHandler()
        Task { @MainActor in
            switch SocialPushType(rawValue: rawType) {
            case .followRequest, .sharedItem:
                SocialCoordinator.openInbox()
            case .followApproved, .newFollower:
                SocialCoordinator.openPublicProfile(handle: actorHandle)
            case .commentReply:
                SocialCoordinator.openComments(episodeUuid: episodeUuid, podcastUuid: podcastUuid,
                                               focusCommentId: commentId > 0 ? commentId : nil)
            case .listInvite:
                SocialCoordinator.openSharedLists()
            case .none:
                break
            }
        }
    }

    private func handleEpisodeNotification(response: UNNotificationResponse, completionHandler rawCompletionHandler: @escaping () -> Void) {
        // Boxed: each branch below hands it to a main-actor closure and calls it exactly once
        let completionHandler = PocketCastsUtils.UncheckedSendable(rawCompletionHandler)

        guard let episodeUuid = response.notification.request.content.userInfo["eu"] as? String, !episodeUuid.isEmpty else {
            completionHandler.value()
            return
        }

        if downloadEpisodeActionId == response.actionIdentifier {
            AnalyticsHelper.downloadFromNotification()
            findEpisode(episodeUuid: episodeUuid) { episode in
                if let episode {
                    DownloadManager.shared.addToQueue(episodeUuid: episode.uuid)
                }

                completionHandler.value()
            }
        } else if addToQueueFirstActionId == response.actionIdentifier || addToQueueLastActionId == response.actionIdentifier {
            let playFirst = addToQueueFirstActionId == response.actionIdentifier
            AnalyticsHelper.addToUpNextFromNotification(playFirst: playFirst)

            findEpisode(episodeUuid: episodeUuid) { episode in
                if let episode {
                    PlaybackManager.shared.addToUpNext(episode: episode, ignoringQueueLimit: true, toTop: playFirst, userInitiated: true)
                }

                completionHandler.value()
            }
        } else if playNowActionid == response.actionIdentifier {
            AnalyticsHelper.playNowFromNotification()
            findEpisode(episodeUuid: episodeUuid) { episode in
                if let episode {
                    PlaybackManager.shared.load(episode: episode, autoPlay: true, overrideUpNext: false)
                }

                completionHandler.value()
            }
        } else if archiveActionId == response.actionIdentifier {
            AnalyticsHelper.archiveFromNotification()
            findEpisode(episodeUuid: episodeUuid) { episode in
                if let episode = episode as? Episode {
                    EpisodeManager.archiveEpisode(episode: episode, fireNotification: false)
                }

                completionHandler.value()
            }
        } else {
            // none of the actions where 3D Touched, the user just wants to open this episode if there is one
            findEpisode(episodeUuid: episodeUuid) { [weak self] episode in
                guard let self else { return }

                if let episode = episode as? Episode, let podcast = DataManager.sharedManager.findPodcast(uuid: episode.podcastUuid) {
                    self.appDelegate()?.openEpisode(episode.uuid, from: podcast)
                } else if let podcastUuid = response.notification.request.content.userInfo["podcast_uuid"] as? String, let podcast = DataManager.sharedManager.findPodcast(uuid: podcastUuid) {
                    // This closure is executed on the main actor, so navigate directly.
                    NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: podcast])
                }

                completionHandler.value()
            }
        }
    }

    // Called when a notification is delivered to a foreground app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Looks up the episode, refreshing from the server if it isn't found locally, then
    /// delivers it to `action`. `action` is always invoked on the **main actor** (both
    /// branches hop via `Task { @MainActor }`), so delivery no longer depends on which
    /// thread the notification callback happens to run on.
    ///
    /// `action` is wrapped in `UncheckedSendable` because it captures the non-`Sendable`
    /// notification completion handler and must cross into the `@Sendable` refresh
    /// completion; that hand-off is safe because `action` is invoked **at most once**.
    /// `RefreshManager` now fires its completion on the no-result path too (see
    /// `processPodcastRefreshResponse`), closing the common case where it never called back —
    /// though a refresh *cancelled* mid-flight still won't, so delivery isn't fully guaranteed.
    /// The episode is fetched *inside* the `@MainActor` closure so the non-`Sendable`
    /// `BaseEpisode` is never sent across an isolation boundary.
    private func findEpisode(episodeUuid: String, performing action: @escaping @MainActor (BaseEpisode?) -> Void) {
        let action = UncheckedSendable(action)
        Task { @MainActor in
            if let existingEpisode = DataManager.sharedManager.findEpisode(uuid: episodeUuid) {
                action.value(existingEpisode)
            } else {
                RefreshManager.shared.refreshPodcasts(completion: { _ in
                    Task { @MainActor in
                        action.value(DataManager.sharedManager.findEpisode(uuid: episodeUuid))
                    }
                })
            }
        }
    }

    func handleDeepLinkNotification(response: UNNotificationResponse, completionHandler: @escaping () -> Void) {
        guard let destinationURLString = response.notification.request.content.userInfo["destination_url"] as? String,
              let url = URL(string: destinationURLString)
        else {
            completionHandler()
            return
        }
        FileLog.shared.addMessage("[Notifications] push notification received with deep link to:\(destinationURLString)")
        let completionHandler = UncheckedSendable(completionHandler)
        Task { @MainActor in
            let _ = UIApplication.shared.delegate?.application?(UIApplication.shared, open: url)
            completionHandler.value()
        }
    }
}
