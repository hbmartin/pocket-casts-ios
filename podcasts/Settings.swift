import PocketCastsDataModel
import PocketCastsServer
import UIKit
import SwiftUI
import PocketCastsUtils

nonisolated class Settings: NSObject {

    // nonisolated(unsafe): developer-menu debug knob; written only from the debug UI
    nonisolated(unsafe) static var debugPlaylistsLimit = Constants.Limits.maxFilterItems

    static var isLockScreenScrubbingDisabled: Bool {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.isLockScreenScrubbingDisabled)
            NotificationCenter.postOnMainThread(notification: Constants.Notifications.remoteCommandSettingsChanged, object: nil)
        }
        get {
            return UserDefaults.standard.bool(forKey: Constants.UserDefaults.isLockScreenScrubbingDisabled)
        }
    }

    static var openLinks: Bool {
        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.openLinks = newValue
            }
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.openLinksInExternalBrowser)
        }
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                return SettingsStore.appSettings.openLinks
            } else {
                return UserDefaults.standard.bool(forKey: Constants.UserDefaults.openLinksInExternalBrowser)
            }
        }
    }

    // MARK: - Library Type

    static let podcastLibraryGridTypeKey = "SJPodcastLibraryGridType"
    // The caches below are read from list-building code on background queues and
    // written from settings UI on main; each access is lock-guarded.
    private static let cacheLock = NSLock()

    // nonisolated(unsafe): backing storage only ever accessed through the cacheLock-guarded computed twin below
    nonisolated(unsafe) private static var _cachedlibrarySortType: LibraryType?
    private static var cachedlibrarySortType: LibraryType? {
        get { cacheLock.withLock { _cachedlibrarySortType } }
        set { cacheLock.withLock { _cachedlibrarySortType = newValue } }
    }
    class func setLibraryType(_ type: LibraryType) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.gridLayout = type
        }
        UserDefaults.standard.set(type.old.rawValue, forKey: Settings.podcastLibraryGridTypeKey)
        cachedlibrarySortType = type
    }

    class func libraryType() -> LibraryType {

        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.gridLayout
        }

        if let type = cachedlibrarySortType {
            return type
        }

        let storedValue = UserDefaults.standard.integer(forKey: Settings.podcastLibraryGridTypeKey)
        if let type = LibraryType(oldValue: storedValue) {
            cachedlibrarySortType = type

            return type
        }

        return LibraryType.threeByThree // default value
    }

    // MARK: - Podcast Badge

    static let badgeKey = "SJBadgeType"
    class func podcastBadgeType() -> BadgeType {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.badges
        }

        let storedBadgeType = UserDefaults.standard.integer(forKey: Settings.badgeKey)

        if let type = BadgeType(rawValue: Int32(storedBadgeType)) {
            return type
        }

        return .off
    }

    class func setPodcastBadgeType(_ badgeType: BadgeType) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.badges = badgeType
        }
        UserDefaults.standard.set(badgeType.rawValue, forKey: Settings.badgeKey)
    }

    // MARK: - Up Next Auto Download

    private static let autoDownloadUpNext = "SJAutoDownloadUpNext"
    class func downloadUpNextEpisodes() -> Bool {
        UserDefaults.standard.bool(forKey: Settings.autoDownloadUpNext)
    }

    class func setDownloadUpNextEpisodes(_ download: Bool) {
        UserDefaults.standard.set(download, forKey: Settings.autoDownloadUpNext)
        trackValueToggled(.settingsAutoDownloadUpNextToggled, enabled: download)
    }

    // MARK: - On-device feed refresh (local-first ingest)

    private static let localFeedIngestEnabledKey = "SJLocalFeedIngestEnabled"

    /// When on, new subscriptions from add-by-URL and OPML import are ingested by
    /// fetching and parsing the feed on device (no Pocket Casts servers) and refresh
    /// locally from then on. Existing podcasts are unaffected.
    class func localFeedIngestEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Settings.localFeedIngestEnabledKey)
    }

    class func setLocalFeedIngestEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Settings.localFeedIngestEnabledKey)
    }

    // MARK: - Mobile Data

    static let allowCellularDownloadKey = "SJUserCellular"
    class func mobileDataAllowed() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return !SettingsStore.appSettings.warnDataUsage
        } else {
            return UserDefaults.standard.bool(forKey: Settings.allowCellularDownloadKey)
        }
    }

    class func setMobileDataAllowed(_ allow: Bool, userInitiated: Bool = false) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.warnDataUsage = !allow
        }
        UserDefaults.standard.set(allow, forKey: Settings.allowCellularDownloadKey)

        guard userInitiated else { return }
        trackValueToggled(.settingsStorageWarnBeforeUsingDataToggled, enabled: allow)
    }

    // MARK: - Auto Download Mobile Data

    private static let allowCellularAutoDownloadKey = "SJUserCellularAutoDownload"
    class func autoDownloadMobileDataAllowed() -> Bool {
        UserDefaults.standard.bool(forKey: Settings.allowCellularAutoDownloadKey)
    }

    class func setAutoDownloadMobileDataAllowed(_ allow: Bool, userInitiated: Bool = false) {
        UserDefaults.standard.set(allow, forKey: Settings.allowCellularAutoDownloadKey)

        guard userInitiated else { return }
        trackValueToggled(.settingsAutoDownloadOnlyOnWifiToggled, enabled: !allow)
    }

    // MARK: - Auto Download

    private static let autoDownloadEnabledKey = "AutoDownloadEnabled"
    class func autoDownloadEnabled() -> Bool {
        guard UserDefaults.standard.object(forKey: Settings.autoDownloadEnabledKey) != nil else {
            return FeatureFlag.autoDownloadOnSubscribe.enabled
        }
        return UserDefaults.standard.bool(forKey: Settings.autoDownloadEnabledKey)
    }

    class func setAutoDownloadEnabled(_ allow: Bool, userInitiated: Bool = false) {
        UserDefaults.standard.set(allow, forKey: Settings.autoDownloadEnabledKey)

        guard userInitiated else { return }
        trackValueToggled(.settingsAutoDownloadNewEpisodesToggled, enabled: allow)
    }

    private static let autoDownloadOnFollowKey = "AutoDownloadOnFollow"
    class func autoDownloadOnFollow() -> Bool {
        guard UserDefaults.standard.object(forKey: Settings.autoDownloadOnFollowKey) != nil else {
            return false
        }
        return UserDefaults.standard.bool(forKey: Settings.autoDownloadOnFollowKey)
    }

    class func setAutoDownloadOnFollow(_ allow: Bool, userInitiated: Bool = false) {
        UserDefaults.standard.set(allow, forKey: Settings.autoDownloadOnFollowKey)

        guard userInitiated else { return }
        trackValueToggled(.settingsAutoDownloadOnFollowPodcastToggled, enabled: allow)
    }

    private static let autoDownloadLimitKey = "AutoDownloadLimit"
    class func autoDownloadLimits() -> AutoDownloadLimit {
        AutoDownloadLimit(rawValue: UserDefaults.standard.integer(forKey: Settings.autoDownloadLimitKey)) ?? .two
    }

    class func setAutoDownloadLimits(_ limit: AutoDownloadLimit) {
        UserDefaults.standard.set(limit.rawValue, forKey: Settings.autoDownloadLimitKey)
        trackValueChanged(.settingsAutoDownloadLimitDownloadsChanged, value: limit.rawValue)
    }

    class func shouldDeleteWhenPlayed() -> Bool {
        let finishedAction = UserDefaults.standard.integer(forKey: Constants.UserDefaults.episodeFinishedAction)

        return finishedAction == PodcastFinishedAction.delete.rawValue
    }

    class func setShouldDeleteWhenPlayed(_ shouldDelete: Bool) {
        let finishedAction = shouldDelete ? PodcastFinishedAction.delete : PodcastFinishedAction.doNothing

        UserDefaults.standard.setValue(finishedAction.rawValue, forKey: Constants.UserDefaults.episodeFinishedAction)
    }

    // MARK: - Default Archive Hiding

    static let defaultArchiveBehaviour = "SJDefaultArchive"
    class func showArchivedDefault() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.showArchived
        } else {
            return UserDefaults.standard.bool(forKey: defaultArchiveBehaviour)
        }
    }

    class func setShowArchivedDefault(_ showArchived: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.showArchived = showArchived
        }
        UserDefaults.standard.set(showArchived, forKey: defaultArchiveBehaviour)

        trackValueChanged(.settingsGeneralArchivedEpisodesChanged, value: showArchived ? "show" : "hide")
    }

    // MARK: - Primary Row Action

    static let primaryRowActionKey = "SJRowAction"
    // nonisolated(unsafe): backing storage only ever accessed through the cacheLock-guarded computed twin below
    nonisolated(unsafe) private static var _cachedPrimaryRowAction: PrimaryRowAction?
    private static var cachedPrimaryRowAction: PrimaryRowAction? {
        get { cacheLock.withLock { _cachedPrimaryRowAction } }
        set { cacheLock.withLock { _cachedPrimaryRowAction = newValue } }
    }
    class func primaryRowAction() -> PrimaryRowAction {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.rowAction
        } else {
            if let action = cachedPrimaryRowAction { return action }
            let storedValue = UserDefaults.standard.integer(forKey: primaryRowActionKey)
            return PrimaryRowAction(rawValue: Int32(storedValue)) ?? .stream
        }
    }

    class func setPrimaryRowAction(_ action: PrimaryRowAction) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.rowAction = action
        } else {
            UserDefaults.standard.set(
                action.rawValue,
                forKey: primaryRowActionKey
            )
        }
        cachedPrimaryRowAction = action

        trackValueChanged(.settingsGeneralRowActionChanged, value: action)
    }

    // MARK: - Podcast Sort Order

    class func homeFolderSortOrder() -> LibrarySort {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.gridOrder
        }

        let sortInt = ServerSettings.homeGridSortOrder()
        if let librarySort = LibrarySort(oldValue: sortInt) {
            return librarySort
        }

        return .dateAddedNewestToOldest
    }

    class func setHomeFolderSortOrder(order: LibrarySort) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.gridOrder = order
        }
        ServerSettings.setHomeGridSortOrder(order.old.rawValue, syncChange: true)
    }

    // MARK: - Podcast Grouping Default

    static let podcastGroupingDefaultKey = "SJDefaultPodcastGrouping"
    // nonisolated(unsafe): backing storage only ever accessed through the cacheLock-guarded computed twin below
    nonisolated(unsafe) private static var _cachedPodcastGrouping: PodcastGrouping?
    private static var cachedPodcastGrouping: PodcastGrouping? {
        get { cacheLock.withLock { _cachedPodcastGrouping } }
        set { cacheLock.withLock { _cachedPodcastGrouping = newValue } }
    }
    class func defaultPodcastGrouping() -> PodcastGrouping {
        guard FeatureFlag.newSettingsStorage.enabled == false else {
            return SettingsStore.appSettings.episodeGrouping
        }

        if let grouping = cachedPodcastGrouping { return grouping }

        let storedValue = UserDefaults.standard.integer(forKey: podcastGroupingDefaultKey)
        let defaultGrouping = PodcastGrouping(rawValue: Int32(storedValue)) ?? .none
        cachedPodcastGrouping = defaultGrouping

        return defaultGrouping
    }

    class func setDefaultPodcastGrouping(_ grouping: PodcastGrouping) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.episodeGrouping = grouping
        }
        UserDefaults.standard.set(grouping.rawValue, forKey: podcastGroupingDefaultKey)
        cachedPodcastGrouping = grouping

        trackValueChanged(.settingsGeneralEpisodeGroupingChanged, value: grouping)
    }

    // MARK: - Primary Up Next Swipe Action

    static let primaryUpNextSwipeActionKey = "SJUpNextSwipe"
    // nonisolated(unsafe): backing storage only ever accessed through the cacheLock-guarded computed twin below
    nonisolated(unsafe) private static var _cachedPrimaryUpNextSwipeAction: PrimaryUpNextSwipeAction?
    private static var cachedPrimaryUpNextSwipeAction: PrimaryUpNextSwipeAction? {
        get { cacheLock.withLock { _cachedPrimaryUpNextSwipeAction } }
        set { cacheLock.withLock { _cachedPrimaryUpNextSwipeAction = newValue } }
    }
    class func primaryUpNextSwipeAction() -> PrimaryUpNextSwipeAction {
        guard FeatureFlag.newSettingsStorage.enabled == false else {
            return SettingsStore.appSettings.upNextSwipe
        }

        if let action = cachedPrimaryUpNextSwipeAction { return action }

        let storedValue = UserDefaults.standard.integer(forKey: primaryUpNextSwipeActionKey)
        let primaryAction = PrimaryUpNextSwipeAction(rawValue: Int32(storedValue)) ?? .playNext
        cachedPrimaryUpNextSwipeAction = primaryAction

        return primaryAction
    }

    class func setPrimaryUpNextSwipeAction(_ action: PrimaryUpNextSwipeAction) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.upNextSwipe = action
        }
        UserDefaults.standard.set(action.rawValue, forKey: primaryUpNextSwipeActionKey)
        cachedPrimaryUpNextSwipeAction = action

        trackValueChanged(.settingsGeneralUpNextSwipeChanged, value: action)
    }

    // MARK: - Play Up Next On Tap

    static let playUpNextOnTapKey = "SJPlayUpNextOnTap"
    class func playUpNextOnTap() -> Bool {
        guard FeatureFlag.newSettingsStorage.enabled == false else {
            return SettingsStore.appSettings.playUpNextOnTap
        }
        return UserDefaults.standard.bool(forKey: Settings.playUpNextOnTapKey)
    }

    class func setPlayUpNextOnTap(_ isOn: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.playUpNextOnTap = isOn
        }
        UserDefaults.standard.set(isOn, forKey: Settings.playUpNextOnTapKey)
    }

    static let upNextShuffleKey = "SJUpNextShuffleKey"
    class func upNextShuffleToggle() {
        guard FeatureFlag.upNextShuffle.enabled else { return }

        let isOn = upNextShuffleEnabled()
        UserDefaults.standard.set(!isOn, forKey: Settings.upNextShuffleKey)

        NotificationCenter.postOnMainThread(notification: Constants.Notifications.upNextShuffleToggle)
    }

    class func upNextShuffleEnabled() -> Bool {
        if !FeatureFlag.upNextShuffle.enabled || !SyncManager.isUserLoggedIn() {
            return false
        }
        return UserDefaults.standard.bool(forKey: Settings.upNextShuffleKey)
    }

    // MARK: - Discover Region

    private static let chartRegion = "SJChartRegion"
    class func discoverRegion(discoverLayout: DiscoverLayout) -> String {
        return convertRegion(userRegion: userRegion(), discoverLayout: discoverLayout)
    }

    class func userRegion() -> String? {
        var userRegion: String?
        if let savedRegion = UserDefaults.standard.string(forKey: chartRegion) {
            userRegion = savedRegion.lowercased()
        } else if let region = (Locale.current as NSLocale).object(forKey: NSLocale.Key.countryCode) as? String {
            userRegion = region.lowercased()
        }
        return userRegion
    }

    private class func convertRegion(userRegion: String?, discoverLayout: DiscoverLayout) -> String {
        guard let userRegion else { return discoverLayout.defaultRegionCode }

        if let _ = discoverLayout.regions?[userRegion.lowercased()] {
            return userRegion
        }

        return discoverLayout.defaultRegionCode
    }

    class func setDiscoverRegion(region: String) {
        UserDefaults.standard.set(region, forKey: chartRegion)
        UserDefaults.standard.synchronize()

        NotificationCenter.postOnMainThread(notification: Constants.Notifications.chartRegionChanged)

        if FeatureFlag.enableLocalizationHeaders.enabled {
            LocalizationHelper.update(userRegion: region)
        }
    }

    // MARK: - Auto Archiving

    static let autoArchivePlayedAfterKey = "AutoArchivePlayedAfer"
    class func autoArchivePlayedAfter() -> TimeInterval {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.autoArchivePlayed.time.rawValue
        } else {
            return UserDefaults.standard.double(forKey: Settings.autoArchivePlayedAfterKey)
        }
    }

    class func setAutoArchivePlayedAfter(_ after: TimeInterval, userInitiated: Bool = false) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.autoArchivePlayed = AutoArchiveAfterPlayed(time: AutoArchiveAfterTime(rawValue: after)!)!
        }
        UserDefaults.standard.set(after, forKey: Settings.autoArchivePlayedAfterKey)

        guard userInitiated else { return }
        if let archiveTime = AutoArchiveAfterTime(rawValue: after) {
            trackValueChanged(.settingsAutoArchivePlayedChanged, value: archiveTime)
        }
    }

    static let autoArchiveInactiveAfterKey = "AutoArchiveInactiveAfer"
    class func autoArchiveInactiveAfter() -> TimeInterval {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.autoArchiveInactive.time.rawValue
        } else {
            return UserDefaults.standard.double(forKey: Settings.autoArchiveInactiveAfterKey)
        }
    }

    class func setAutoArchiveInactiveAfter(_ after: TimeInterval, userInitiated: Bool = false) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.autoArchiveInactive = AutoArchiveAfterInactive(time: AutoArchiveAfterTime(rawValue: after)!)!
        }
        UserDefaults.standard.set(after, forKey: Settings.autoArchiveInactiveAfterKey)

        guard userInitiated else { return }
        if let archiveTime = AutoArchiveAfterTime(rawValue: after) {
            trackValueChanged(.settingsAutoArchiveInactiveChanged, value: archiveTime)
        }
    }

    static let archiveStarredEpisodesKey = "ArchiveStarredEpisodes"
    class func archiveStarredEpisodes() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.autoArchiveIncludesStarred
        } else {
            return UserDefaults.standard.bool(forKey: Settings.archiveStarredEpisodesKey)
        }
    }

    class func setArchiveStarredEpisodes(_ archive: Bool, userInitiated: Bool = false) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.autoArchiveIncludesStarred = archive
        }
        UserDefaults.standard.set(archive, forKey: Settings.archiveStarredEpisodesKey)

        guard userInitiated else { return }
        trackValueToggled(.settingsAutoArchiveIncludeStarredToggled, enabled: archive)
    }

    // MARK: - App Info

    @objc class func appVersion() -> String {
        guard let infoDictionary = Bundle.main.infoDictionary, let shortVersion = infoDictionary["CFBundleShortVersionString"] as? String else {
            return "6.0" // this should never fail, but it's a nicer API to not return nil
        }

        return shortVersion
    }

    class func displayableVersion() -> String {
#if STAGING
        return L10n.appVersion(Settings.appVersion(), Settings.buildNumber()) + " - STAGING"
#else
        return L10n.appVersion(Settings.appVersion(), Settings.buildNumber())
#endif
    }

    class func buildNumber() -> String {
        guard let infoDictionary = Bundle.main.infoDictionary, let buildNumber = infoDictionary[kCFBundleVersionKey as String] as? String else {
            return "1" // this should never fail, but it's a nicer API to not return nil
        }

        return buildNumber
    }

    // MARK: - Sleep Time

    private static let customSleepTimeKey = "CustomSleepTime"
    class func customSleepTime() -> TimeInterval {
        let savedTime = UserDefaults.standard.double(forKey: Settings.customSleepTimeKey)
        if savedTime < Constants.Limits.minSleepTime { return Constants.Limits.minSleepTime }

        return savedTime
    }

    class func setCustomSleepTime(_ time: TimeInterval) {
        let adjustedTime = time < Constants.Limits.minSleepTime ? Constants.Limits.minSleepTime : time
        UserDefaults.standard.set(adjustedTime, forKey: "CustomSleepTime")
    }

    static var sleepTimerNumberOfEpisodes: Int {
        get {
            UserDefaults.standard.object(forKey: "sleep_timer_custom_number_of_episodes") as? Int ?? 1
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "sleep_timer_custom_number_of_episodes")
        }
    }

    // MARK: - Lock Screen actions

    static let mediaSessionActionsKey = "MediaSessionActions"
    class func extraMediaSessionActionsEnabled() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.playbackActions
        } else {
            return UserDefaults.standard.bool(forKey: Settings.mediaSessionActionsKey)
        }
    }

    class func setExtraMediaSessionActionsEnabled(_ enabled: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.playbackActions = enabled
        }
        UserDefaults.standard.set(enabled, forKey: Settings.mediaSessionActionsKey)

        NotificationCenter.postOnMainThread(notification: Constants.Notifications.extraMediaSessionActionsChanged)

        Settings.trackValueToggled(.settingsGeneralExtraPlaybackActionsToggled, enabled: enabled)
    }

    // MARK: - Legacy Bluetooth Support

    static let legacyBtSupportKey = "LegacyBtSupport"
    class func legacyBluetoothModeEnabled() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.legacyBluetooth
        } else {
            return UserDefaults.standard.bool(forKey: Settings.legacyBtSupportKey)
        }
    }

    class func setLegacyBluetoothModeEnabled(_ enabled: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.legacyBluetooth = enabled
        }
        UserDefaults.standard.set(enabled, forKey: Settings.legacyBtSupportKey)
        Settings.trackValueToggled(.settingsGeneralLegacyBluetoothToggled, enabled: enabled)
    }

    // MARK: - Publish Chapter Titles

    static let publishChapterTitlesKey = "PublishChapterTitles"
    class func publishChapterTitlesEnabled() -> Bool {
        guard FeatureFlag.newSettingsStorage.enabled == false else {
            return SettingsStore.appSettings.chapterTitles
        }

        if let isEnabled = UserDefaults.standard.value(forKey: Settings.publishChapterTitlesKey) as? Bool {
            return isEnabled
        }

        return true
    }

    class func setPublishChapterTitlesEnabled(_ enabled: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.chapterTitles = enabled
        }
        UserDefaults.standard.set(enabled, forKey: Settings.publishChapterTitlesKey)
    }

    // MARK: - User Episode Settings

    public static let userEpisodeSortByKey = "UserEpisodeSortBy"
    class func userEpisodeSortBy() -> Int32 {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.filesSortOrder.rawValue
        } else {
            Int32(UserDefaults.standard.integer(forKey: userEpisodeSortByKey))
        }
    }

    class func setUserEpisodeSortBy(_ value: Int32) {
        if FeatureFlag.newSettingsStorage.enabled, let order = UploadedSort(rawValue: value) {
            SettingsStore.appSettings.filesSortOrder = order
        }
        UserDefaults.standard.set(value, forKey: userEpisodeSortByKey)
    }

    private static let userEpisodeAutoUploadKey = "UserEpisodeAutoUpload"
    class func userFilesAutoUpload() -> Bool {
        UserDefaults.standard.bool(forKey: userEpisodeAutoUploadKey)
    }

    class func setUserEpisodeAutoUpload(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: userEpisodeAutoUploadKey)
        trackValueToggled(.settingsFilesAutoUploadToCloudToggled, enabled: value)
    }

    static let userEpisodeAutoAddToUpNextKey = "UserEpisodeAutoAddToUpNext"
    class func userEpisodeAutoAddToUpNext() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.filesAutoUpNext
        } else {
            return UserDefaults.standard.bool(forKey: userEpisodeAutoAddToUpNextKey)
        }
    }

    class func setUserEpisodeAutoAddToUpNext(_ value: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.filesAutoUpNext = value
            return
        }
        UserDefaults.standard.set(value, forKey: userEpisodeAutoAddToUpNextKey)
        trackValueToggled(.settingsFilesAutoAddUpNextToggled, enabled: value)
    }

    static let userEpisodeRemoveFileAfterPlayingKey = "UserEpisodeRemoveFileAfterPlaying"
    class func userEpisodeRemoveFileAfterPlaying() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.filesAfterPlayingDeleteLocal
        } else {
            return UserDefaults.standard.bool(forKey: userEpisodeRemoveFileAfterPlayingKey)
        }
    }

    class func setUserEpisodeRemoveFileAfterPlaying(_ value: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.filesAfterPlayingDeleteLocal = value
        }
        UserDefaults.standard.set(value, forKey: userEpisodeRemoveFileAfterPlayingKey)
        trackValueToggled(.settingsFilesDeleteLocalFileAfterPlayingToggled, enabled: value)
    }

    static let userEpisodeRemoveFromCloudAfterPlayingKey = "UserEpisodeRemoveFromCloudAfterPlaying"
    class func userEpisodeRemoveFromCloudAfterPlaying() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.filesAfterPlayingDeleteCloud
        } else {
            return UserDefaults.standard.bool(forKey: userEpisodeRemoveFromCloudAfterPlayingKey)
        }
    }

    class func setUserEpisodeRemoveFromCloudAfterPlayingKey(_ value: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.filesAfterPlayingDeleteCloud = value
        }
        UserDefaults.standard.set(value, forKey: userEpisodeRemoveFromCloudAfterPlayingKey)
        trackValueToggled(.settingsFilesDeleteCloudFileAfterPlayingToggled, enabled: value)
    }

    // MARK: - Full Player Chapters Expanded

    private static let playerChaptersExpandedKey = "PlayerChaptersExpanded"
    class func playerChaptersExpanded() -> Bool {
        if let expanded = UserDefaults.standard.value(forKey: playerChaptersExpandedKey) as? Bool {
            return expanded
        }

        return true
    }

    class func setPlayerChaptersExpanded(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: playerChaptersExpandedKey)
    }

    class func uniqueAppId() -> String? {
        if let appId = UserDefaults.standard.object(forKey: Constants.UserDefaults.appId) as? String {
            return appId
        }

        return nil
    }

    // MARK: What's new

    private static let whatsNewLastAcknowledgedKey = "SJWhatsNewLastAcknowledged"

    class func setWhatsNewLastAcknowledged(_ value: Int) {
        UserDefaults.standard.set(value, forKey: whatsNewLastAcknowledgedKey)
    }

    class func whatsNewLastAcknowledged() -> Int {
        UserDefaults.standard.integer(forKey: whatsNewLastAcknowledgedKey)
    }


    private static let lastWhatsNewShownKey = "LastWhatsNewShown"
    class var lastWhatsNewShown: String? {
        set {
            UserDefaults.standard.setValue(newValue, forKey: lastWhatsNewShownKey)
            UserDefaults.standard.synchronize()
        }

        get {
            UserDefaults.standard.string(forKey: lastWhatsNewShownKey)
        }
    }

    class func setShouldFollowSystemTheme(_ value: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.useSystemTheme = value
        }
        UserDefaults.standard.set(value, forKey: Constants.UserDefaults.shouldFollowSystemThemeKey)
    }

    class func shouldFollowSystemTheme() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.useSystemTheme
        } else {
            UserDefaults.standard.bool(forKey: Constants.UserDefaults.shouldFollowSystemThemeKey)
        }
    }

    // MARK: Player Actions

    fileprivate static let playerActionsKey = "PlayerActions"
    class func playerActions() -> [PlayerAction] {
        let defaultActions = PlayerAction.defaultActions.filter { $0.isAvailable }

        var playerActions: [PlayerAction]

        if FeatureFlag.newSettingsStorage.enabled {
            playerActions = SettingsStore.appSettings.playerShelf
                .compactMap { action in
                    switch action {
                        case .known(let present):
                            return present
                        case .unknown:
                            return nil
                    }
                }
                .filter { $0.isAvailable }
        } else {
            playerActions = UserDefaults.standard.playerActions ?? defaultActions
        }

        return playerActions + defaultActions.filter { !playerActions.contains($0) }
    }

    class func updatePlayerActions(_ actions: [PlayerAction]) {
        if FeatureFlag.newSettingsStorage.enabled {
            let unknowns = SettingsStore.appSettings.playerShelf.compactMap { action -> ActionOption? in
                switch action {
                    case .known:
                        return nil
                    case .unknown(let absent):
                        return .unknown(absent)
                }
            }
            SettingsStore.appSettings.playerShelf = actions.map({ .known($0) }) + unknowns
        } else {
            let actionInts = actions.map(\.intValue)
            UserDefaults.standard.set(actionInts, forKey: Settings.playerActionsKey)
        }

        NotificationCenter.postOnMainThread(notification: Constants.Notifications.playerActionsUpdated)
    }

    // MARK: Multi Select Gesture

    static let multiSelectGestureKey = "MultiSelectGestureEnabled"
    class func multiSelectGestureEnabled() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.multiSelectGesture
        } else {
            return UserDefaults.standard.bool(forKey: multiSelectGestureKey)
        }
    }

    class func setMultiSelectGestureEnabled(_ enabled: Bool, userInitiated: Bool = false) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.multiSelectGesture = enabled
        }
        UserDefaults.standard.set(enabled, forKey: multiSelectGestureKey)

        guard userInitiated else { return }
        Settings.trackValueToggled(.settingsGeneralMultiSelectGestureToggled, enabled: enabled)
    }

    // MARK: Multi Select Actions

    private static let multiSelectActionsKey = "MultiSelectActions"
    class func multiSelectActions() -> [MultiSelectAction] {
        let defaultActions: [MultiSelectAction] = [.playNext, .playLast, .removeFromUpNext, .addToPlaylist, .download, .archive, .share, .markAsPlayed, .star]
        guard let savedInts = UserDefaults.standard.object(forKey: Settings.multiSelectActionsKey) as? [Int32] else {
            return defaultActions
        }

        let actions = savedInts.compactMap { MultiSelectAction(rawValue: $0) }

        // Make sure new items are shown
        return actions + defaultActions.filter { !actions.contains($0) }
    }

    class func updateMultiSelectActions(_ actions: [MultiSelectAction]) {
        let actionInts = actions.map(\.rawValue)
        UserDefaults.standard.set(actionInts, forKey: Settings.multiSelectActionsKey)
    }

    private static let listeningHistoryMultiSelectActionsKey = "ListeningHistoryMultiSelectActions"
    class func listeningHistoryMultiSelectActions() -> [MultiSelectAction] {
        let defaultActions: [MultiSelectAction] = [.playNext, .playLast, .removeFromUpNext, .download, .archive, .share, .removeListeningHistory, .markAsPlayed, .star]
        guard let savedInts = UserDefaults.standard.object(forKey: Settings.listeningHistoryMultiSelectActionsKey) as? [Int32] else {
            return defaultActions
        }

        let actions = savedInts.compactMap { MultiSelectAction(rawValue: $0) }

        // Make sure new items are shown
        return actions + defaultActions.filter { !actions.contains($0) }
    }

    class func updateListeningHistoryMultiSelectActions(_ actions: [MultiSelectAction]) {
        let actionInts = actions.map(\.rawValue)
        UserDefaults.standard.set(actionInts, forKey: Settings.listeningHistoryMultiSelectActionsKey)
    }

    private static let filesMultiSelectActionsKey = "FilesMultiSelectActionsV2"
    class func fileMultiSelectActions() -> [MultiSelectAction] {
        guard let savedInts = UserDefaults.standard.object(forKey: Settings.filesMultiSelectActionsKey) as? [Int32] else {
            return [.playNext, .playLast, .download, .markAsPlayed, .delete]
        }

        let actions = savedInts.compactMap { MultiSelectAction(rawValue: $0) }

        return actions
    }

    class func updateFilesMultiSelectActions(_ actions: [MultiSelectAction]) {
        let actionInts = actions.map(\.rawValue)
        UserDefaults.standard.set(actionInts, forKey: Settings.filesMultiSelectActionsKey)
    }

    private static let upNextMultiSelectActionsKey = "UpNextMultiSelectActions"
    class func upNextMultiSelectActions() -> [MultiSelectAction] {
        let defaultActions: [MultiSelectAction] = [.moveToTop, .moveToBottom, .removeFromUpNext, .download, .markAsPlayed, .archive, .addToPlaylist, .star]
        guard let savedInts = UserDefaults.standard.object(forKey: Settings.upNextMultiSelectActionsKey) as? [Int32] else {
            return defaultActions
        }

        let actions = savedInts.compactMap { MultiSelectAction(rawValue: $0) }

        // Make sure new items are shown
        return actions + defaultActions.filter { !actions.contains($0) }
    }

    class func updateUpNextMultiSelectActions(_ actions: [MultiSelectAction]) {
        let actionInts = actions.map(\.rawValue)
        UserDefaults.standard.set(actionInts, forKey: Settings.upNextMultiSelectActionsKey)
    }

    // MARK: - App Store Review Requests

    class func addReviewRequested() {
        var reviewRequestDates = Self.reviewRequestDates()
        reviewRequestDates.append(Date())
        UserDefaults.standard.set(reviewRequestDates, forKey: Constants.UserDefaults.reviewRequestDates)
    }

    class func reviewRequestDates() -> [Date] {
        UserDefaults.standard.array(forKey: Constants.UserDefaults.reviewRequestDates) as? [Date] ?? [Date]()
    }

    class func resetReviewRequests() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.reviewRequestDates)
    }

    // MARK: - Tracks

    class func setAnalytics(optOut: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.privacyAnalytics = !optOut
        }
        UserDefaults.standard.set(optOut, forKey: Constants.UserDefaults.analyticsOptOut)
    }

    class func analyticsOptOut() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return !SettingsStore.appSettings.privacyAnalytics
        } else {
            return UserDefaults.standard.bool(forKey: Constants.UserDefaults.analyticsOptOut)
        }
    }

    // MARK: - Sleep Timer (internal)

    class var sleepTimerFinishedDate: Date? {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.sleepTimerFinishedDate)
        }

        get {
            UserDefaults.standard.object(forKey: Constants.UserDefaults.sleepTimerFinishedDate) as? Date
        }
    }

    class var sleepTimerLastSetting: SleepTimerManager.SleepTimerSetting? {
        set {
            UserDefaults.standard.setJSONObject(newValue, forKey: Constants.UserDefaults.sleepTimerSetting)
        }

        get {
            try? UserDefaults.standard.jsonObject(SleepTimerManager.SleepTimerSetting.self, forKey: Constants.UserDefaults.sleepTimerSetting)
        }
    }

    class func hasSyncedEpisodesForPlayback(year: Int) -> Bool {
        let key = String(format: Constants.UserDefaults.hasSyncedEpisodesForPlayback, year)
        return UserDefaults.standard.bool(forKey: key)
    }

    class func setHasSyncedEpisodesForPlayback(_ newValue: Bool, year: Int) {
        let key = String(format: Constants.UserDefaults.hasSyncedEpisodesForPlayback, year)
        UserDefaults.standard.set(newValue, forKey: key)
    }

    class func hasSyncedEpisodesForPlaybackAsPlusUser(year: Int) -> Bool {
        let key = String(format: Constants.UserDefaults.hasSyncedEpisodesForPlaybackAsPlusUser, year)
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Whether the user was plus or not by the time the sync happened
    class func setHasSyncedEpisodesForPlaybackAsPlusUser(_ newValue: Bool, year: Int) {
        let key = String(format: Constants.UserDefaults.hasSyncedEpisodesForPlaybackAsPlusUser, year)
        UserDefaults.standard.set(newValue, forKey: key)
    }

    class var top5PodcastsListLink: String? {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.top5PodcastsListLink)
        }

        get {
            UserDefaults.standard.string(forKey: Constants.UserDefaults.top5PodcastsListLink)
        }
    }

    static var shouldShowInitialOnboardingFlow: Bool {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.shouldShowInitialOnboardingFlow)
        }
        get {
            UserDefaults.standard.bool(forKey: Constants.UserDefaults.shouldShowInitialOnboardingFlow)
        }
    }

    static var hasSeenInitialOnboardingBefore: Bool {
        get {
            UserDefaults.standard.object(forKey: Constants.UserDefaults.shouldShowInitialOnboardingFlow) != nil
        }
    }

    // MARK: - Embedded Artwork

    static var loadEmbeddedImages: Bool {
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.useEmbeddedArtwork
            } else {
                UserDefaults.standard.bool(forKey: Constants.UserDefaults.loadEmbeddedImages)
            }
        }
        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.useEmbeddedArtwork = newValue
            }
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.loadEmbeddedImages)
            Settings.trackValueToggled(.settingsAppearanceUseEmbeddedArtworkToggled, enabled: newValue)
        }
    }

    // MARK: - Autoplay

    static var autoplay: Bool {
        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.autoPlayEnabled = newValue
            }
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.autoplay)
        }
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                return SettingsStore.appSettings.autoPlayEnabled
            } else {
                return UserDefaults.standard.bool(forKey: Constants.UserDefaults.autoplay)
            }
        }
    }

    // MARK: - Sleep Timer

    static var autoRestartSleepTimer: Bool {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.autoRestartSleepTimer)
        }
        get {
            UserDefaults.standard.object(forKey: Constants.UserDefaults.autoRestartSleepTimer) as? Bool ?? true
        }
    }

    static var shakeToRestartSleepTimer: Bool {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.shakeToRestartSleepTimer)
        }
        get {
            UserDefaults.standard.bool(forKey: Constants.UserDefaults.shakeToRestartSleepTimer)
        }
    }

    // MARK: - Headphone Controls

    static var headphonesPreviousAction: HeadphoneControlAction {
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                return SettingsStore.appSettings.headphoneControlsPreviousAction.action
            } else {
                return Constants.UserDefaults.headphones.previousAction.value
            }
        }

        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.headphoneControlsPreviousAction = HeadphoneControl(action: newValue)
            }
            Constants.UserDefaults.headphones.previousAction.save(newValue)
        }
    }

    static var headphonesNextAction: HeadphoneControlAction {
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                return SettingsStore.appSettings.headphoneControlsNextAction.action
            } else {
                return Constants.UserDefaults.headphones.nextAction.value
            }
        }

        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.headphoneControlsNextAction = HeadphoneControl(action: newValue)
            }
            Constants.UserDefaults.headphones.nextAction.save(newValue)
        }
    }


    /// Returns whether the bookmark creation sound option is enabled
    static var isPlayBookmarkCreationSoundAvailable: Bool {
        [Settings.headphonesNextAction, Settings.headphonesPreviousAction].contains(.addBookmark)
    }

    /// Determines if we should play the sound when a bookmark is created
    static var shouldPlayBookmarkSound: Bool {
        isPlayBookmarkCreationSoundAvailable && playBookmarkCreationSound
    }

    static var playBookmarkCreationSound: Bool {
        get {
            Constants.UserDefaults.bookmarks.creationSound.value
        }

        set {
            Constants.UserDefaults.bookmarks.creationSound.save(newValue)
        }
    }

    static var darkUpNextTheme: Bool {
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.useDarkUpNextTheme
            } else {
                Constants.UserDefaults.appearance.darkUpNextTheme.value
            }
        }

        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.useDarkUpNextTheme = newValue
            }
            Constants.UserDefaults.appearance.darkUpNextTheme.save(newValue)
        }
    }

    static var tabBarMinimizingEnabled: Bool {
        get { Constants.UserDefaults.appearance.tabBarMinimizingEnabled.value }
        set { Constants.UserDefaults.appearance.tabBarMinimizingEnabled.save(newValue) }
    }

    static var skipBackTime: Int {
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                return Int(SettingsStore.appSettings.skipBack)
            } else {
                return ServerSettings.skipBackTime()
            }
        }
        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.skipBack = Int32(newValue)
            }
            ServerSettings.setSkipBackTime(newValue)
        }
    }

    static var skipForwardTime: Int {
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                return Int(SettingsStore.appSettings.skipForward)
            } else {
                return ServerSettings.skipForwardTime()
            }
        }
        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.skipForward = Int32(newValue)
            }
            ServerSettings.setSkipForwardTime(newValue)
        }
    }

    static var playerBookmarksSort: Binding<BookmarkSortOption> {
        Binding {
            if FeatureFlag.newSettingsStorage.enabled {
                return SettingsStore.appSettings.playerBookmarksSortType.option(lastOption: .timestamp)
            } else {
                return Constants.UserDefaults.bookmarks.playerSort.value
            }
        } set: { newValue in
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.playerBookmarksSortType = BookmarksSort(option: newValue)
            }
            Constants.UserDefaults.bookmarks.playerSort.save(newValue)
        }
    }

    static var episodeBookmarksSort: Binding<BookmarkSortOption> {
        Binding {
            if FeatureFlag.newSettingsStorage.enabled {
                return SettingsStore.appSettings.episodeBookmarksSortType.option(lastOption: .timestamp)
            } else {
                return Constants.UserDefaults.bookmarks.episodeSort.value
            }
        } set: { newValue in
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.episodeBookmarksSortType = BookmarksSort(option: newValue)
            }
            Constants.UserDefaults.bookmarks.episodeSort.save(newValue)
        }
    }

    static var podcastBookmarksSort: Binding<BookmarkSortOption> {
        Binding {
            if FeatureFlag.newSettingsStorage.enabled {
                return SettingsStore.appSettings.podcastBookmarksSortType.option(lastOption: .episode)
            } else {
                return Constants.UserDefaults.bookmarks.podcastSort.value
            }
        } set: { newValue in
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.podcastBookmarksSortType = BookmarksSort(option: newValue)
            }
            Constants.UserDefaults.bookmarks.podcastSort.save(newValue)
        }
    }

    static var profileBookmarksSort: Binding<BookmarkSortOption> {
        Binding {
            if FeatureFlag.newSettingsStorage.enabled {
                return SettingsStore.appSettings.profileBookmarksSortType.option(lastOption: .podcastAndEpisode)
            } else {
                return Constants.UserDefaults.bookmarks.profileSort.value
            }
        } set: { newValue in
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.profileBookmarksSortType = BookmarksSort(option: newValue)
            }
            Constants.UserDefaults.bookmarks.profileSort.save(newValue)
        }
    }

    static var appBadge: AppBadge? {
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.appBadge
            } else {
                AppBadge(rawValue: Int32(UserDefaults.standard.integer(forKey: Constants.UserDefaults.appBadge)))
            }
        }
        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.appBadge = newValue ?? .off
            }
            UserDefaults.standard.set(newValue?.rawValue, forKey: Constants.UserDefaults.appBadge)
        }
    }

    static var appBadgeFilterUuid: String? {
        get {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.appBadgeFilter
            } else {
                UserDefaults.standard.string(forKey: Constants.UserDefaults.appBadgeFilterUuid)
            }
        }
        set {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.appBadgeFilter = newValue ?? ""
            }
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.appBadgeFilterUuid)
        }
    }



    // MARK: - Podcast Feed Reload

    static var shouldShowPodcastFeeReloadTip: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.podcastFeedReload.showTip) as? Bool ?? true
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.podcastFeedReload.showTip)
        }
    }

    // MARK: - Manage Downloads

    class var manageDownloadsLastCheckDate: Date? {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.manageDownloads.lastCheckDate)
        }

        get {
            UserDefaults.standard.object(forKey: Constants.UserDefaults.manageDownloads.lastCheckDate) as? Date
        }
    }

    // MARK: - Smart Folders Upsell display
    class var suggestedFoldersLastUpsellDate: Date? {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.suggestedFolders.lastUpsellDate)
        }

        get {
            UserDefaults.standard.object(forKey: Constants.UserDefaults.suggestedFolders.lastUpsellDate) as? Date
        }
    }

    class var suggestedFoldersUpsellCount: Int {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.suggestedFolders.upsellCount)
        }

        get {
            UserDefaults.standard.object(forKey: Constants.UserDefaults.suggestedFolders.upsellCount) as? Int ?? 0
        }
    }

    class var suggestedFoldersLastPodcastsUsed: String? {
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.suggestedFolders.lastPodcastsUsed)
        }

        get {
            UserDefaults.standard.object(forKey: Constants.UserDefaults.suggestedFolders.lastPodcastsUsed) as? String
        }
    }

    // MARK: - Podcast View Changes Tip

    static var shouldShowPodcastViewChangesTip: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.podcastViewChanges.showTip) as? Bool ?? true
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.podcastViewChanges.showTip)
        }
    }

    // MARK: - Recent Played Sorting Tip

    static var shouldShowRecentlyPlayedSortingTip: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.shouldShowRecentlyPlayedSortingTip) as? Bool ?? true
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.shouldShowRecentlyPlayedSortingTip)
        }
    }

    // MARK: - Playlists

    static var shouldShowNewFilterTip: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.newFilterTip) as? Bool ?? true
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.newFilterTip)
        }
    }

    static var shouldShowNewFilterTipInCreationView: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.newFilterTipCreationView) as? Bool ?? true
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.newFilterTipCreationView)
        }
    }

    static var shouldShowDragAndDropTip: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.playlistDragAndDropTip) as? Bool ?? false
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.playlistDragAndDropTip)
        }
    }

    static var shouldShowPlaylistsOnboarding: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.playlistsOnboarding) as? Bool ?? true
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.playlistsOnboarding)
        }
    }

    static var firstTimePlaylistCreated: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.firstTimePlaylistCreated) as? Bool ?? true
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.firstTimePlaylistCreated)
        }
    }

    static var saveCurrentUpNextQueueIntoPlaylist: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.saveCurrentUpNextQueueIntoPlaylist) as? Bool ?? true
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.saveCurrentUpNextQueueIntoPlaylist)
        }
    }

    // MARK: - Informational Banner
#if !APPCLIP && !os(tvOS)
    static func dismissBanner(for type: InformationalBannerType) {
        UserDefaults.standard.set(true, forKey: "kInformational\(type.rawValue.capitalized)Banner")
    }

    static func shouldShowBanner(for type: InformationalBannerType) -> Bool {
        return !UserDefaults.standard.bool(forKey: "kInformational\(type.rawValue.capitalized)Banner")
    }
#endif

    // MARK: - Notifications
    static var notificationsNewEpisodes: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.notifications.newEpisodes) as? Bool ?? false
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.notifications.newEpisodes)
        }
    }

    static var notificationsDailyReminders: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.notifications.dailyReminders) as? Bool ?? false
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.notifications.dailyReminders)
        }
    }

    static var notificationsNewFeaturesAndTips: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.notifications.newFeaturesAndTips) as? Bool ?? false
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.notifications.newFeaturesAndTips)
        }
    }

    static var notificationsRecommendations: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.notifications.recommendations) as? Bool ?? false
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.notifications.recommendations)
        }
    }

    static var notificationsOffers: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.notifications.offers) as? Bool ?? false
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.notifications.offers)
        }
    }

    static var notificationsLastTriggerDate: [String: Date] {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.notifications.triggerDates) as? [String: Date] ?? [:]
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.notifications.triggerDates)
        }
    }

    // MARK: - Encourage Account Creation

    static var hasShownInformationalViewModal: Bool {
        get {
            UserDefaults.standard.value(forKey: Constants.UserDefaults.informationalModal.hasShownViewModal) as? Bool ?? false
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Constants.UserDefaults.informationalModal.hasShownViewModal)
        }
    }

    // MARK: - VoiceBoostN

    /// Facade over `audioTuning.voiceBoost.useVoiceBoostN` so the General
    /// settings toggle and the Advanced Audio screen share one source of truth.
    static var isVoiceBoostNEnabled: Bool {
        get {
            guard FeatureFlag.voiceBoostN.enabled else { return false }
            return audioTuning.voiceBoost.useVoiceBoostN
        }
        set {
            var tuning = audioTuning
            tuning.voiceBoost.useVoiceBoostN = newValue
            audioTuning = tuning
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.voiceBoostNEnabled)
            FileLog.shared.addMessage("[Settings] VoiceBoostN \(newValue ? "enabled" : "disabled")")
        }
    }

    // MARK: - Advanced Audio Tuning

    /// The full advanced-audio tuning snapshot, persisted as one JSON blob so
    /// the engine mirror always sees a consistent value. Default tuning stores
    /// nothing; a corrupt blob falls back to defaults rather than crashing.
    static var audioTuning: AudioTuning {
        get {
            guard let data = UserDefaults.standard.data(forKey: Constants.UserDefaults.audioTuning),
                  let tuning = try? JSONDecoder().decode(AudioTuning.self, from: data) else {
                var tuning = AudioTuning.default
                // Honor a legacy VoiceBoostN opt-out recorded before this blob existed
                if UserDefaults.standard.object(forKey: Constants.UserDefaults.voiceBoostNEnabled) != nil {
                    tuning.voiceBoost.useVoiceBoostN = UserDefaults.standard.bool(forKey: Constants.UserDefaults.voiceBoostNEnabled)
                }
                return tuning
            }
            return tuning
        }
        set {
            guard newValue != audioTuning else { return }
            if newValue == .default {
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.audioTuning)
                // keep the legacy VoiceBoostN key from resurrecting an old opt-out
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.voiceBoostNEnabled)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Constants.UserDefaults.audioTuning)
            }
            FileLog.shared.addMessage("[Settings] AudioTuning changed (default: \(newValue == .default))")
            NotificationCenter.postOnMainThread(notification: Constants.Notifications.audioTuningDidChange)
        }
    }

    // MARK: - Database (internal)

    class var lastAppVersionThatRunVacuum: String? {
        set {
            UserDefaults.standard.setValue(newValue, forKey: "last_app_version_that_run_vacuum")
        }

        get {
            UserDefaults.standard.string(forKey: "last_app_version_that_run_vacuum")
        }
    }

    // MARK: - Configurable Defaults

        class func minTimeBetweenProgressSaves() -> TimeInterval {
            millisecondsToTime(
                configuredDouble(
                    key: Constants.RemoteParams.periodicSaveTimeMs,
                    default: Constants.RemoteParams.periodicSaveTimeMsDefault
                )
            )
        }

        class func podcastSearchDebounceTime() -> TimeInterval {
            if FeatureFlag.searchPredictive.enabled {
                return 0.2
            } else {
                return millisecondsToTime(
                    configuredDouble(
                        key: Constants.RemoteParams.podcastSearchDebounceMs,
                        default: Constants.RemoteParams.podcastSearchDebounceMsDefault
                    )
                )
            }
        }

        class func episodeSearchDebounceTime() -> TimeInterval {
            millisecondsToTime(
                configuredDouble(
                    key: Constants.RemoteParams.episodeSearchDebounceMs,
                    default: Constants.RemoteParams.episodeSearchDebounceMsDefault
                )
            )
        }

        static var addMissingEpisodes: Bool {
            configuredBool(
                key: Constants.RemoteParams.addMissingEpisodes,
                default: Constants.RemoteParams.addMissingEpisodesDefault
            )
        }

        static var plusCloudStorageLimit: Int {
            configuredInt(
                key: Constants.RemoteParams.customStorageLimitGB,
                default: Constants.RemoteParams.customStorageLimitGBDefault
            )
        }

        static var patronCloudStorageLimit: Int {
            configuredInt(
                key: Constants.RemoteParams.patronCloudStorageGB,
                default: Constants.RemoteParams.patronCloudStorageGBDefault
            )
        }

        static var errorLogoutHandling: Bool {
            configuredBool(
                key: Constants.RemoteParams.errorLogoutHandling,
                default: Constants.RemoteParams.errorLogoutHandlingDefault
            )
        }

        static var newSettingsStorage: Bool {
            FeatureFlag.newSettingsStorage.default
        }

        private class func millisecondsToTime(_ milliseconds: Double) -> TimeInterval {
            TimeInterval(milliseconds / 1000)
        }

        private static func configuredBool(key: String, default defaultValue: Bool) -> Bool {
            RemoteConfigValueStore().bool(forKey: key) ?? defaultValue
        }

        private static func configuredDouble(key: String, default defaultValue: Double) -> Double {
            RemoteConfigValueStore().double(forKey: key) ?? defaultValue
        }

        private static func configuredInt(key: String, default defaultValue: Int) -> Int {
            RemoteConfigValueStore().int(forKey: key) ?? defaultValue
        }
}

nonisolated extension Settings {
    static func trackValueChanged(_ event: AnalyticsEvent, value: Any) {
        let promoted: any Sendable = switch value {
        case let v as String: v
        case let v as Int: v
        case let v as Double: v
        case let v as Bool: v
        case let v as AnalyticsDescribable: v.analyticsDescription
        default: String(describing: value)
        }
        Analytics.track(event, properties: ["value": promoted])
    }

    static func trackValueToggled(_ event: AnalyticsEvent, enabled: Bool) {
        Analytics.track(event, properties: ["enabled": enabled])
    }
}

#if !os(tvOS)
extension L10n {
    static var plusCloudStorageLimit: String {
        plusCloudStorageLimitFormat(Settings.plusCloudStorageLimit.localized())
    }

    static var patronCloudStorageLimit: String {
        plusCloudStorageLimitFormat(Settings.patronCloudStorageLimit.localized())
    }
}
#endif

nonisolated extension HeadphoneControl {
    init(action: HeadphoneControlAction) {
        switch action {
        case .addBookmark:
            self = .addBookmark
        case .nextChapter:
            self = .nextChapter
        case .previousChapter:
            self = .previousChapter
        case .skipBack:
            self = .skipBack
        case .skipForward:
            self = .skipForward
        }
    }

    var action: HeadphoneControlAction {
        switch self {
        case .addBookmark:
            return .addBookmark
        case .nextChapter:
            return .nextChapter
        case .previousChapter:
            return .previousChapter
        case .skipBack:
            return .skipBack
        case .skipForward:
            return .skipForward
        }
    }
}

nonisolated extension UserDefaults {
    var playerActions: [PlayerAction]? {
        guard let savedInts = UserDefaults.standard.object(forKey: Settings.playerActionsKey) as? [Int] else {
            return nil
        }

        return savedInts
            .compactMap { PlayerAction(int: $0) }
            .filter { $0.isAvailable }
    }
}
