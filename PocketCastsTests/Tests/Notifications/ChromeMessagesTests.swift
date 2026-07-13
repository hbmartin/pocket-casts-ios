import XCTest

@testable import podcasts

/// Round-trip tests for the UI chrome + account typed notification messages
/// (migration Phase 5.6). The bridged representations are frozen while
/// string-based posters/observers still exist, so these assert the exact
/// `object` shapes as well as the typed round trip.
@MainActor
final class ChromeMessagesTests: XCTestCase {
    // MARK: - TappedOnSelectedTab (tab index payload)

    func testTappedOnSelectedTabRoundTripsTabIndex() throws {
        let notification = TappedOnSelectedTab.makeNotification(TappedOnSelectedTab(tabIndex: 2))

        // Frozen bridged shape: the tab index rides in `object` (posted by the
        // still-string-based MainTabBarController).
        XCTAssertEqual(notification.name, Notification.Name("SJTappedOnSelectedTab"))
        XCTAssertEqual(notification.object as? Int, 2)

        let roundTripped = try XCTUnwrap(TappedOnSelectedTab.makeMessage(notification))
        XCTAssertEqual(roundTripped.tabIndex, 2)
    }

    func testTappedOnSelectedTabBridgesFromBareStringPost() throws {
        let notification = Notification(name: Notification.Name("SJTappedOnSelectedTab"))

        let message = try XCTUnwrap(TappedOnSelectedTab.makeMessage(notification))
        XCTAssertNil(message.tabIndex)
    }

    func testTappedOnSelectedTabBridgesFromStringPostWithIntObject() throws {
        // Matches the frozen bridged shape: the tab index rides in `object`.
        let notification = Notification(name: Notification.Name("SJTappedOnSelectedTab"), object: 3)

        let message = try XCTUnwrap(TappedOnSelectedTab.makeMessage(notification))
        XCTAssertEqual(message.tabIndex, 3)
    }

    // MARK: - SystemThemeMayHaveChanged (isDark payload)

    func testSystemThemeMayHaveChangedRoundTripsIsDark() throws {
        XCTAssertEqual(SystemThemeMayHaveChanged.name.rawValue, "SystemThemeChanged", "raw names are effectively ABI and must never change")

        for isDark in [true, false] {
            let notification = SystemThemeMayHaveChanged.makeNotification(SystemThemeMayHaveChanged(isDark: isDark))

            // Frozen bridged shape: the Bool rides in `object` (read by the
            // still-string-based Theme observer).
            XCTAssertEqual(notification.name, Notification.Name("SystemThemeChanged"))
            XCTAssertEqual(notification.object as? Bool, isDark)

            let roundTripped = try XCTUnwrap(SystemThemeMayHaveChanged.makeMessage(notification))
            XCTAssertEqual(roundTripped.isDark, isDark)
        }
    }

    func testSystemThemeMayHaveChangedBridgesFromBareStringPost() throws {
        let message = try XCTUnwrap(SystemThemeMayHaveChanged.makeMessage(Notification(name: Notification.Name("SystemThemeChanged"))))
        XCTAssertNil(message.isDark)
    }

    // MARK: - No-payload messages

    func testThemeChangedBridgesBothWays() {
        XCTAssertNotNil(ThemeChanged.makeMessage(Notification(name: Constants.Notifications.themeChanged)))
        XCTAssertEqual(ThemeChanged.makeNotification(ThemeChanged()).name, Constants.Notifications.themeChanged)
    }

    func testFollowSystemThemeTurnedOnBridgesBothWays() {
        XCTAssertNotNil(FollowSystemThemeTurnedOn.makeMessage(Notification(name: Notification.Name("FollowSystemThemeTurnedOn"))))
        XCTAssertEqual(FollowSystemThemeTurnedOn.makeNotification(FollowSystemThemeTurnedOn()).name, Notification.Name("FollowSystemThemeTurnedOn"))
    }

    func testTextEditingMessagesBridgeBothWays() {
        XCTAssertNotNil(TextEditingDidStart.makeMessage(Notification(name: Notification.Name("SJTextEditingStarted"))))
        XCTAssertEqual(TextEditingDidStart.makeNotification(TextEditingDidStart()).name, Notification.Name("SJTextEditingStarted"))

        XCTAssertNotNil(TextEditingDidEnd.makeMessage(Notification(name: Notification.Name("SJTextEditingEnded"))))
        XCTAssertEqual(TextEditingDidEnd.makeNotification(TextEditingDidEnd()).name, Notification.Name("SJTextEditingEnded"))
    }

    func testSearchRequestedBridgesBothWays() {
        XCTAssertNotNil(SearchRequested.makeMessage(Notification(name: Notification.Name("SJTriggerSearch"))))
        XCTAssertEqual(SearchRequested.makeNotification(SearchRequested()).name, Notification.Name("SJTriggerSearch"))
    }

    func testMiniPlayerMessagesBridgeBothWays() {
        XCTAssertNotNil(MiniPlayerDidAppear.makeMessage(Notification(name: Notification.Name("SJMiniPlayerAppeared"))))
        XCTAssertEqual(MiniPlayerDidAppear.makeNotification(MiniPlayerDidAppear()).name, Notification.Name("SJMiniPlayerAppeared"))

        XCTAssertNotNil(MiniPlayerDidDisappear.makeMessage(Notification(name: Notification.Name("SJMiniPlayerDisappeared"))))
        XCTAssertEqual(MiniPlayerDidDisappear.makeNotification(MiniPlayerDidDisappear()).name, Notification.Name("SJMiniPlayerDisappeared"))
    }

    // MARK: - Account (Notifications.swift names)

    func testUserLoginDidChangeBridgesBothWays() {
        XCTAssertNotNil(UserLoginDidChange.makeMessage(Notification(name: .userLoginDidChange)))
        XCTAssertEqual(UserLoginDidChange.makeNotification(UserLoginDidChange()).name, .userLoginDidChange)
    }

    func testUserSignedInBridgesBothWays() {
        XCTAssertNotNil(UserSignedIn.makeMessage(Notification(name: .userSignedIn)))
        XCTAssertEqual(UserSignedIn.makeNotification(UserSignedIn()).name, .userSignedIn)
    }

    func testOnboardingFlowDidDismissBridgesBothWays() {
        XCTAssertNotNil(OnboardingFlowDidDismiss.makeMessage(Notification(name: .onboardingFlowDidDismiss)))
        XCTAssertEqual(OnboardingFlowDidDismiss.makeNotification(OnboardingFlowDidDismiss()).name, .onboardingFlowDidDismiss)
    }

    func testEpisodeEmbeddedArtworkLoadedBridgesBothWays() {
        XCTAssertNotNil(EpisodeEmbeddedArtworkLoaded.makeMessage(Notification(name: .episodeEmbeddedArtworkLoaded)))
        XCTAssertEqual(EpisodeEmbeddedArtworkLoaded.makeNotification(EpisodeEmbeddedArtworkLoaded()).name, .episodeEmbeddedArtworkLoaded)
    }

    func testTableViewReorderMessagesBridgeBothWays() {
        XCTAssertNotNil(TableViewReorderWillBegin.makeMessage(Notification(name: .tableViewReorderWillBegin)))
        XCTAssertEqual(TableViewReorderWillBegin.makeNotification(TableViewReorderWillBegin()).name, .tableViewReorderWillBegin)

        XCTAssertNotNil(TableViewReorderDidEnd.makeMessage(Notification(name: .tableViewReorderDidEnd)))
        XCTAssertEqual(TableViewReorderDidEnd.makeNotification(TableViewReorderDidEnd()).name, .tableViewReorderDidEnd)
    }

    // MARK: - File-local names

    func testPodcastFeedReloadMessagesBridgeBothWays() {
        XCTAssertNotNil(PodcastFeedReloadLoading.makeMessage(Notification(name: PodcastFeedReloadNotification.loading)))
        XCTAssertEqual(PodcastFeedReloadLoading.makeNotification(PodcastFeedReloadLoading()).name, PodcastFeedReloadNotification.loading)

        XCTAssertNotNil(PodcastFeedReloadEpisodesFound.makeMessage(Notification(name: PodcastFeedReloadNotification.episodesFound)))
        XCTAssertEqual(PodcastFeedReloadEpisodesFound.makeNotification(PodcastFeedReloadEpisodesFound()).name, PodcastFeedReloadNotification.episodesFound)

        XCTAssertNotNil(PodcastFeedReloadNoEpisodesFound.makeMessage(Notification(name: PodcastFeedReloadNotification.noEpisodesFound)))
        XCTAssertEqual(PodcastFeedReloadNoEpisodesFound.makeNotification(PodcastFeedReloadNoEpisodesFound()).name, PodcastFeedReloadNotification.noEpisodesFound)
    }

    func testShareProfilePhotoDidChangeBridgesBothWays() {
        // The `notifications(named:)` observer in SubscriptionProfileImage is
        // still string-based, so the typed post must keep the legacy raw name.
        XCTAssertNotNil(ShareProfileViewModel.PhotoDidChange.makeMessage(Notification(name: ShareProfileViewModel.photoDidChangeNotification)))
        XCTAssertEqual(ShareProfileViewModel.PhotoDidChange.makeNotification(ShareProfileViewModel.PhotoDidChange()).name, ShareProfileViewModel.photoDidChangeNotification)
    }
}
