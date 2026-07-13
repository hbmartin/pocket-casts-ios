import Foundation
import PocketCastsDataModel
import PocketCastsServer
import Combine
import UserNotifications

/// Keeps the app-icon badge in sync with the database via a GRDB `ValueObservation`
/// (B6 pilot): the badge count is observed straight from the episode tables instead
/// of being re-queried on a pile of change notifications.
///
/// Non-database inputs (the badge mode setting, push permission, last-close date,
/// and the pinned currently playing episode for filter badges) are re-read by
/// `updateBadge()`, which applies a fresh count immediately — so backgrounding
/// paths with no run loop still badge synchronously — and restarts the observation
/// for subsequent database-driven updates.
class BadgeHelper {
    // isolated deinit: main-actor-owned helper; deinit cancels the observation task and Combine subscriptions
    isolated deinit {
        teardown()
    }

    private var observationTask: Task<Void, Never>?
    private var cancelables: [AnyCancellable] = []

    /// Database-driven count changes funnel through a shared 3s debounce so bursty
    /// write storms (refresh, sync, OPML import) badge only once.
    private let badgeUpdates = PassthroughSubject<Int, Never>()

    /// The badge settings the running observation was started from, so settings
    /// writes can be detected without anyone explicitly pinging us.
    private struct AppliedBadgeSettings: Equatable {
        let setting: AppBadge?
        let filterUuid: String?
    }

    private var appliedBadgeSettings: AppliedBadgeSettings?

    func setup() {
        teardown()

        cancelables = [
            badgeUpdates
                .debounce(for: .seconds(3), scheduler: RunLoop.main)
                .sink { [weak self] badgeNumber in
                    self?.setBadgeTo(badgeNumber)
                }
        ]

        // The pinned playing episode in filter-badge counts comes from PlaybackManager,
        // not the database, so the observation can't see it change; playback transitions
        // restart the observation to refresh it. Every other badge-relevant change
        // reaches us through the database observation itself.
        let playbackNotifications: [Notification.Name] = [Constants.Notifications.playbackTrackChanged,
                                                          Constants.Notifications.playbackStarted,
                                                          Constants.Notifications.playbackEnded]
        cancelables += playbackNotifications.map { name in
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard Settings.appBadge == .filterCount else { return }
                    self?.updateBadge()
                }
        }

        // The badge settings screen writes UserDefaults without pinging us; restart
        // the observation when the badge settings actually change (cheap fingerprint
        // check, since this notification fires for every defaults write).
        cancelables += [
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self, self.currentBadgeSettings() != self.appliedBadgeSettings else { return }
                    self.updateBadge()
                }
        ]

        updateBadge()
    }

    private func currentBadgeSettings() -> AppliedBadgeSettings {
        AppliedBadgeSettings(setting: Settings.appBadge, filterUuid: Settings.appBadgeFilterUuid)
    }

    func teardown() {
        observationTask?.cancel()
        observationTask = nil

        cancelables.removeAll()
    }

    /// Re-reads the badge inputs, applies the current count immediately, and
    /// (re)starts the database observation that keeps it fresh.
    func updateBadge() {
        observationTask?.cancel()
        observationTask = nil
        appliedBadgeSettings = currentBadgeSettings()

        let badgeFilter: EpisodeFilter? = Settings.appBadge == .filterCount
            ? Settings.appBadgeFilterUuid.flatMap { DataManager.sharedManager.findPlaylist(uuid: $0) }
            : nil
        let action = Self.badgeAction(
            setting: Settings.appBadge,
            pushEnabled: NotificationsHelper.shared.pushEnabled(),
            lastAppCloseDate: UserDefaults.standard.object(forKey: Constants.UserDefaults.lastAppCloseDate) as? Date,
            badgeFilter: badgeFilter,
            episodeUuidToAdd: badgeFilter?.episodeUuidToAddToQueries()
        )

        switch action {
        case .leaveUntouched:
            break
        case .clear:
            clearBadge(clearNotificationsToo: false)
        case .disableBadgeSetting:
            Settings.appBadge = .off
        case .observe(let source):
            // Immediate synchronous set first: explicit updateBadge() callers
            // (launch, entering background) can't wait for an async emission.
            setBadgeTo(currentCount(for: source))
            startObserving(source)
        }
    }

    func clearNotifications() {
        clearBadge(clearNotificationsToo: true)
        updateBadge()
    }

    // MARK: - Badge input mapping

    /// What `updateBadge()` should do for a combination of the (non-database)
    /// badge inputs. Pure so it's unit-testable.
    enum BadgeAction: Equatable {
        /// Badge and push are both off: touch nothing (avoids triggering the push permission popup).
        case leaveUntouched
        /// The badge should show nothing: clear it and don't observe.
        case clear
        /// The filter badge points at a missing filter: turn the badge setting off.
        case disableBadgeSetting
        /// Keep the badge in sync with this database count.
        case observe(BadgeCountSource)
    }

    static func badgeAction(
        setting: AppBadge?,
        pushEnabled: Bool,
        lastAppCloseDate: Date?,
        badgeFilter: EpisodeFilter?,
        episodeUuidToAdd: String?
    ) -> BadgeAction {
        guard let setting else { return .leaveUntouched }

        if setting == .off, !pushEnabled { return .leaveUntouched }
        if setting == .off || !pushEnabled { return .clear }

        switch setting {
        case .totalUnplayed:
            return .observe(.subscribedUnplayed(addedAfter: nil))
        case .newSinceLastOpened:
            guard let lastAppCloseDate else { return .clear }
            return .observe(.subscribedUnplayed(addedAfter: lastAppCloseDate))
        case .filterCount:
            guard let badgeFilter else { return .disableBadgeSetting }
            return .observe(.playlistEpisodes(playlistUuid: badgeFilter.uuid, episodeUuidToAdd: episodeUuidToAdd))
        case .off:
            return .clear // unreachable: handled above
        }
    }

    // MARK: - Observation

    private func startObserving(_ source: BadgeCountSource) {
        observationTask = Task { [weak self] in
            // The initial emission goes through the debounce too: updateBadge()
            // already applied a synchronous count, and re-applying the observed
            // value 3s later is harmless while catching any write that raced in
            // between the synchronous read and the observation's first fetch.
            for await count in DataManager.sharedManager.observeBadgeCount(source) {
                guard let self else { return }
                self.badgeUpdates.send(count)
            }
        }
    }

    private func currentCount(for source: BadgeCountSource) -> Int {
        switch source {
        case .subscribedUnplayed(let addedAfter):
            return DataManager.sharedManager.subscribedUnplayedEpisodeCount(addedAfter: addedAfter)
        case .playlistEpisodes(let playlistUuid, let episodeUuidToAdd):
            guard let playlist = DataManager.sharedManager.findPlaylist(uuid: playlistUuid) else { return 0 }
            return DataManager.sharedManager.episodeCount(for: playlist, episodeUuidToAdd: episodeUuidToAdd)
        }
    }

    // MARK: - Applying the badge

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
