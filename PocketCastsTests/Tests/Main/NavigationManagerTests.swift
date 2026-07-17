import PocketCastsDataModel
import PocketCastsServer
import UIKit
import XCTest

@testable import podcasts

/// Routing for `NavigationManager` page keys, in particular that "go to Discover"
/// entry points land on the Explore tab rather than the Podcasts library.
@MainActor
final class NavigationManagerTests: XCTestCase {
    private var navigationManager: NavigationManager!
    private var mainController: MockMainController!

    override func setUp() async throws {
        navigationManager = NavigationManager()
        mainController = MockMainController()
        navigationManager.mainViewControllerDidLoad(controller: mainController)
    }

    func testExplorePageKeyRoutesToExplore() {
        navigationManager.navigateTo(NavigationManager.explorePageKey)

        XCTAssertTrue(mainController.didNavigateToExplore)
        XCTAssertFalse(mainController.didNavigateToPodcastList, "Explore must not fall back to the Podcasts library")
    }

    func testPodcastListPageKeyStillRoutesToLibrary() {
        navigationManager.navigateTo(NavigationManager.podcastListPageKey)

        XCTAssertTrue(mainController.didNavigateToPodcastList)
        XCTAssertFalse(mainController.didNavigateToExplore)
    }

    func testExplorePageKeyPassesAnimatedFlag() {
        navigationManager.navigateTo(NavigationManager.explorePageKey, animated: false)

        XCTAssertEqual(mainController.navigateToExploreAnimated, false)
    }
}

/// Records the `NavigationProtocol` calls the manager routes to; everything else is a no-op stub.
private class MockMainController: NavigationProtocol {
    var didNavigateToPodcastList = false
    var didNavigateToExplore = false
    var navigateToExploreAnimated: Bool?

    func navigateToPodcastList(_ animated: Bool) {
        didNavigateToPodcastList = true
    }

    func navigateToExplore(_ animated: Bool) {
        didNavigateToExplore = true
        navigateToExploreAnimated = animated
    }

    func navigateToPodcast(_ podcast: Podcast) {}
    func navigateToPodcastInfo(_ podcastInfo: PodcastInfo) {}
    func navigateTo(podcast searchResult: PodcastFolderSearchResult) {}
    func navigateToFolder(_ folder: Folder, popToRootViewController: Bool) {}
    func navigateToSuggestedFolders() {}
    func navigateToEpisode(_ episodeUuid: String, podcastUuid: String?, timestamp: TimeInterval?, quote: String?) {}
    func navigateToProfile(row: ProfileViewController.TableRow?, animated: Bool) {}
    func navigateToFilter(_ filter: EpisodeFilter?, animated: Bool) {}
    func navigateToEditFilter(_ filter: EpisodeFilter) {}
    func navigateToAddFilter() {}
    func presentManualPlaylistsChooser(for episode: Episode, rootViewController: UIViewController?, source: String) {}
    func navigateToUpNext(_ animated: Bool) {}
    func navigateToFiles() {}
    func navigateToAddCustom(_ fileURL: URL) {}
    func showSettings(row: SettingsViewController.TableRow?) {}
    func showSettingsAppearance(showThemeSelection: Bool) {}
    func showProfilePage() {}
    func showHeadphoneSettings() {}
    func showGeneralSettings(row: GeneralSettingsViewController.TableRow?) {}
    func showSignUp() {}
    func showTermsOfUse() {}
    func showPrivacyPolicy() {}
    func showInSafariViewController(urlString: String) {}
    func dismissPresentedViewController(completion: (() -> Void)?) {}
    func showOnboardingFlow(flow: OnboardingFlow.Flow?) {}
    func showNotificationsPermissions() {}
}
