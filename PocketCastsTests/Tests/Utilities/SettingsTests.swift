import XCTest
@testable import podcasts
@testable import PocketCastsServer
import PocketCastsDataModel
import PocketCastsUtils

@MainActor
final class SettingsTests: XCTestCase {

    private let userDefaultsSuiteName = "PocketCasts-SettingsTests"

    private var overriddenFlags = [FeatureFlag: Bool]()
    private lazy var defaultPlayerActions: [PlayerAction] = {
        var actions: [PlayerAction] = [
            .addBookmark,
            .markPlayed,
            .effects,
            .sleepTimer,
            .stopAfterEpisode,
            .routePicker,
            .shareEpisode,
            .addToPlaylist,
            .download,
            .transcript,
            .catchMeUp,
            .goToPodcast,
            .starEpisode,
            .archive
        ]
        return actions
    }()

    private struct ConfigurableDefaultRemoteConfigKeys {
        let errorLogoutHandling: String
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
    }

    private func override(flag: FeatureFlag, value: Bool) throws {
        overriddenFlags[flag] = flag.enabled
        try FeatureFlagOverrideStore().override(flag, withValue: value)
    }

    private func reset(flag: FeatureFlag) throws {
        if let oldValue = overriddenFlags[flag] {
            try FeatureFlagOverrideStore().override(flag, withValue: oldValue)
        }
    }

    private func setupSettingsStore() throws {
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName), "User Defaults suite should load")
        SettingsStore.appSettings = SettingsStore(userDefaults: userDefaults, key: "app_settings", value: AppSettings.defaults)
    }

    private func configurableDefaultRemoteConfigKeys() -> ConfigurableDefaultRemoteConfigKeys {
        let valueStore = RemoteConfigValueStore()
        return ConfigurableDefaultRemoteConfigKeys(
            errorLogoutHandling: valueStore.key(for: Constants.RemoteParams.errorLogoutHandling)
        )
    }

    private func removeConfigurableDefaultOverrides(keys: ConfigurableDefaultRemoteConfigKeys) {
        UserDefaults.standard.removeObject(forKey: Constants.RemoteParams.errorLogoutHandling)
        UserDefaults.standard.removeObject(forKey: keys.errorLogoutHandling)
    }

    func testImportOldHeadphoneControls() throws {
        try override(flag: .newSettingsStorage, value: false)
        try setupSettingsStore()

        let newNextAction = HeadphoneControlAction.nextChapter
        let newPreviousAction = HeadphoneControlAction.previousChapter

        Settings.headphonesNextAction = newNextAction
        Settings.headphonesPreviousAction = newPreviousAction

        try FeatureFlagOverrideStore().override(FeatureFlag.newSettingsStorage, withValue: true)

        SettingsStore.appSettings.importUserDefaults()

        XCTAssertEqual(newNextAction, Settings.headphonesNextAction, "Next action should be imported from old defaults")
        XCTAssertEqual(newPreviousAction, Settings.headphonesPreviousAction, "Previous action should be imported from old defaults")
        try reset(flag: .newSettingsStorage)
    }

    func testPlayerActions() throws {
        let unknownString = "test"
        try override(flag: .newSettingsStorage, value: true)
        try setupSettingsStore()
        Settings.updatePlayerActions(PlayerAction.defaultActions.filter { $0.isAvailable }) // Set defaults

        SettingsStore.appSettings.playerShelf = [.known(.markPlayed), .unknown(unknownString)]
        Settings.updatePlayerActions([.addBookmark, .markPlayed])

        XCTAssertEqual(defaultPlayerActions, Settings.playerActions(), "Player actions should exclude unknown actions and include defaults")
        XCTAssertEqual([.known(.addBookmark), .known(.markPlayed), .unknown(unknownString)], SettingsStore.appSettings.playerShelf, "Player shelf should include unknowns at end")

        try reset(flag: .newSettingsStorage)
    }

    func testOldPlayerActions() throws {
        try override(flag: .newSettingsStorage, value: false)

        Settings.updatePlayerActions(PlayerAction.defaultActions.filter { $0.isAvailable }) // Set defaults
        Settings.updatePlayerActions([.addBookmark, .markPlayed])

        XCTAssertEqual(defaultPlayerActions, Settings.playerActions(), "Player actions should include changes from update")

        try reset(flag: .newSettingsStorage)
    }

    func testImportOldPlayerActions() throws {
        // Start with disabled settingsSync
        try override(flag: .newSettingsStorage, value: false)

        Settings.updatePlayerActions(PlayerAction.defaultActions.filter { $0.isAvailable })
        Settings.updatePlayerActions([.addBookmark, .markPlayed]) // This update is tested in testOldPlayerActions

        // Enable settingsSync to flip `Settings` to use the new value
        try FeatureFlagOverrideStore().override(FeatureFlag.newSettingsStorage, withValue: true)

        try setupSettingsStore()
        SettingsStore.appSettings.importUserDefaults()

        XCTAssertEqual(defaultPlayerActions, Settings.playerActions(), "Player actions should include changes from update")

        try reset(flag: .newSettingsStorage)
    }

    func testPlayerActionRawValueInitializerHandlesAllCases() {
        PlayerAction.allCases.forEach { action in
            XCTAssertEqual(PlayerAction(rawValue: action.rawValue), action)
        }
    }

    func testPlayerActionIntValuesAreStable() {
        XCTAssertEqual(PlayerAction.stopAfterEpisode.intValue, 14, "stopAfterEpisode must keep int value 14 (persisted in UserDefaults)")
        XCTAssertEqual(PlayerAction(int: 14), .stopAfterEpisode)
        XCTAssertNil(PlayerAction(int: 7), "7 is a retired int value and must not be reused")

        PlayerAction.allCases.forEach { action in
            XCTAssertEqual(PlayerAction(int: action.intValue), action, "\(action) should round-trip through its int value")
        }
    }

    func testTapToPlayRoundTripsInBothStorageModes() throws {
        defer { UserDefaults.standard.removeObject(forKey: Settings.tapToPlayKey) }

        try override(flag: .newSettingsStorage, value: false)
        XCTAssertFalse(Settings.tapToPlay(), "Should default to off")
        Settings.setTapToPlay(true)
        XCTAssertTrue(Settings.tapToPlay(), "UserDefaults storage should round-trip")

        try FeatureFlagOverrideStore().override(FeatureFlag.newSettingsStorage, withValue: true)
        try setupSettingsStore()
        XCTAssertFalse(Settings.tapToPlay(), "Fresh synced storage should default to off")

        SettingsStore.appSettings.importUserDefaults()
        XCTAssertTrue(Settings.tapToPlay(), "Import should carry the old UserDefaults value across")

        Settings.setTapToPlay(false)
        XCTAssertFalse(Settings.tapToPlay(), "Synced storage should round-trip")

        try reset(flag: .newSettingsStorage)
    }

    func testSeekAccelerationRoundTripsInBothStorageModes() throws {
        defer { UserDefaults.standard.removeObject(forKey: Settings.seekAccelerationKey) }

        try override(flag: .newSettingsStorage, value: false)
        XCTAssertFalse(Settings.seekAccelerationEnabled(), "Should default to off")
        Settings.setSeekAccelerationEnabled(true)
        XCTAssertTrue(Settings.seekAccelerationEnabled(), "UserDefaults storage should round-trip")

        try FeatureFlagOverrideStore().override(FeatureFlag.newSettingsStorage, withValue: true)
        try setupSettingsStore()
        XCTAssertFalse(Settings.seekAccelerationEnabled(), "Fresh synced storage should default to off")

        SettingsStore.appSettings.importUserDefaults()
        XCTAssertTrue(Settings.seekAccelerationEnabled(), "Import should carry the old UserDefaults value across")

        Settings.setSeekAccelerationEnabled(false)
        XCTAssertFalse(Settings.seekAccelerationEnabled(), "Synced storage should round-trip")

        try reset(flag: .newSettingsStorage)
    }

    func testTapToPlayRoundTripInOldStorage() throws {
        try override(flag: .newSettingsStorage, value: false)

        Settings.setTapToPlay(true)
        XCTAssertTrue(Settings.tapToPlay(), "Tap to play should round-trip via UserDefaults")

        Settings.setTapToPlay(false)
        XCTAssertFalse(Settings.tapToPlay(), "Tap to play should round-trip via UserDefaults")

        try reset(flag: .newSettingsStorage)
    }

    func testTapToPlayRoundTripInNewStorage() throws {
        try override(flag: .newSettingsStorage, value: true)
        try setupSettingsStore()

        Settings.setTapToPlay(true)
        XCTAssertTrue(Settings.tapToPlay(), "Tap to play should round-trip via the settings store")

        Settings.setTapToPlay(false)
        XCTAssertFalse(Settings.tapToPlay(), "Tap to play should round-trip via the settings store")

        UserDefaults.standard.removeObject(forKey: Settings.tapToPlayKey)
        try reset(flag: .newSettingsStorage)
    }

    func testTapToPlayImportsFromOldDefaults() throws {
        // Start with disabled settingsSync
        try override(flag: .newSettingsStorage, value: false)

        Settings.setTapToPlay(true)

        // Enable settingsSync to flip `Settings` to use the new value
        try FeatureFlagOverrideStore().override(FeatureFlag.newSettingsStorage, withValue: true)

        try setupSettingsStore()
        SettingsStore.appSettings.importUserDefaults()

        XCTAssertTrue(Settings.tapToPlay(), "Tap to play should be imported from old defaults")

        UserDefaults.standard.removeObject(forKey: Settings.tapToPlayKey)
        try reset(flag: .newSettingsStorage)
    }

    func testSeekAccelerationRoundTripInOldStorage() throws {
        try override(flag: .newSettingsStorage, value: false)

        Settings.setSeekAccelerationEnabled(true)
        XCTAssertTrue(Settings.seekAccelerationEnabled(), "Seek acceleration should round-trip via UserDefaults")

        Settings.setSeekAccelerationEnabled(false)
        XCTAssertFalse(Settings.seekAccelerationEnabled(), "Seek acceleration should round-trip via UserDefaults")

        try reset(flag: .newSettingsStorage)
    }

    func testSeekAccelerationRoundTripInNewStorage() throws {
        try override(flag: .newSettingsStorage, value: true)
        try setupSettingsStore()

        Settings.setSeekAccelerationEnabled(true)
        XCTAssertTrue(Settings.seekAccelerationEnabled(), "Seek acceleration should round-trip via the settings store")

        Settings.setSeekAccelerationEnabled(false)
        XCTAssertFalse(Settings.seekAccelerationEnabled(), "Seek acceleration should round-trip via the settings store")

        UserDefaults.standard.removeObject(forKey: Settings.seekAccelerationKey)
        try reset(flag: .newSettingsStorage)
    }

    func testConfigurableDefaultsUseUserDefaultsOverrides() throws {
        let remoteConfigKeys = configurableDefaultRemoteConfigKeys()
        defer {
            removeConfigurableDefaultOverrides(keys: remoteConfigKeys)
        }

        UserDefaults.standard.set(true, forKey: remoteConfigKeys.errorLogoutHandling)

        XCTAssertTrue(Settings.errorLogoutHandling)
    }

    func testConfigurableDefaultsIgnoreBareUserDefaultsOverrides() throws {
        let remoteConfigKeys = configurableDefaultRemoteConfigKeys()
        defer {
            removeConfigurableDefaultOverrides(keys: remoteConfigKeys)
        }
        UserDefaults.standard.removeObject(forKey: remoteConfigKeys.errorLogoutHandling)

        UserDefaults.standard.set(true, forKey: Constants.RemoteParams.errorLogoutHandling)

        XCTAssertEqual(Settings.errorLogoutHandling, Constants.RemoteParams.errorLogoutHandlingDefault)
    }

    func testImportOldDefaults() throws {
        // Start with disabled settingsSync
        try override(flag: .newSettingsStorage, value: false)

        let newRowAction = PrimaryRowAction.stream
        let newSwipeAction = PrimaryUpNextSwipeAction.playLast
        let newAppBadge = AppBadge.newSinceLastOpened
        let newPlayedAfter = AutoArchiveAfterTime.after1Week
        let newInactiveAfter = AutoArchiveAfterTime.after90Days
        let newEpisodeSortBy = UploadedSort.titleAtoZ
        let newPlayerBookmarksSort = BookmarkSortOption.newestToOldest
        let newEpisodeBookmarksSort = BookmarkSortOption.oldestToNewest
        let newProfileBookmarksSort = BookmarkSortOption.podcastAndEpisode
        let newHeadphonesNextAction = HeadphoneControlAction.previousChapter
        let newHeadphonesPreviousAction = HeadphoneControlAction.skipForward
        let newHomeFolderSortOrder = LibrarySort.titleAtoZ
        let newPodcastBadgeType = BadgeType.latestEpisode
        let newAutoPlayPlaylist = AutoplayHelper.Playlist.podcast(uuid: "1234")
        let newTheme = ThemeType.contrastLight
        let newPreferredLightTheme = ThemeType.contrastLight
        let newPreferredDarkTheme = ThemeType.contrastDark

        Settings.setPrimaryRowAction(newRowAction)
        Settings.setPrimaryUpNextSwipeAction(newSwipeAction)
        Settings.appBadge = newAppBadge
        Settings.setAutoArchivePlayedAfter(newPlayedAfter.rawValue)
        Settings.setAutoArchiveInactiveAfter(newInactiveAfter.rawValue)
        Settings.setUserEpisodeSortBy(newEpisodeSortBy.rawValue)
        Settings.playerBookmarksSort.wrappedValue = newPlayerBookmarksSort
        Settings.episodeBookmarksSort.wrappedValue = newEpisodeBookmarksSort
        Settings.profileBookmarksSort.wrappedValue = newProfileBookmarksSort
        Settings.headphonesNextAction = newHeadphonesNextAction
        Settings.headphonesPreviousAction = newHeadphonesPreviousAction
        Settings.setHomeFolderSortOrder(order: newHomeFolderSortOrder)
        Settings.setPodcastBadgeType(newPodcastBadgeType)

        Theme.sharedTheme.activeTheme = newTheme
        Theme.setPreferredLightTheme(newPreferredLightTheme, systemIsDark: false)
        Theme.setPreferredDarkTheme(newPreferredDarkTheme, systemIsDark: false)
        AutoplayHelper.shared.playedFrom(playlist: newAutoPlayPlaylist)

        // Enable settingsSync to flip `Settings` to use the new value
        try FeatureFlagOverrideStore().override(FeatureFlag.newSettingsStorage, withValue: true)

        try setupSettingsStore()
        SettingsStore.appSettings.importUserDefaults()

        XCTAssertEqual(newRowAction, Settings.primaryRowAction())
        XCTAssertEqual(newSwipeAction, Settings.primaryUpNextSwipeAction())
        XCTAssertEqual(newAppBadge, Settings.appBadge)
        XCTAssertEqual(newPlayedAfter.rawValue, Settings.autoArchivePlayedAfter())
        XCTAssertEqual(newInactiveAfter.rawValue, Settings.autoArchiveInactiveAfter())
        XCTAssertEqual(newEpisodeSortBy.rawValue, Settings.userEpisodeSortBy())
        XCTAssertEqual(newPlayerBookmarksSort, Settings.playerBookmarksSort.wrappedValue)
        XCTAssertEqual(newEpisodeBookmarksSort, Settings.episodeBookmarksSort.wrappedValue)
        XCTAssertEqual(newProfileBookmarksSort, Settings.profileBookmarksSort.wrappedValue)
        XCTAssertEqual(newHeadphonesNextAction, Settings.headphonesNextAction)
        XCTAssertEqual(newHeadphonesPreviousAction, Settings.headphonesPreviousAction)
        XCTAssertEqual(newHomeFolderSortOrder, Settings.homeFolderSortOrder())
        XCTAssertEqual(newPodcastBadgeType, Settings.podcastBadgeType())
        XCTAssertEqual(newAutoPlayPlaylist, AutoplayHelper.shared.lastPlaylist)
        XCTAssertEqual(newTheme, Theme.sharedTheme.activeTheme)
        XCTAssertEqual(newPreferredLightTheme, Theme.preferredLightTheme())
        XCTAssertEqual(newPreferredDarkTheme, Theme.preferredDarkTheme())
    }
}
