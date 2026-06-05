import Foundation
import PocketCastsDataModel
import PocketCastsServer
import UIKit

protocol NavigationProtocol: AnyObject {
    func navigateToPodcastList(_ animated: Bool)
    func navigateToPodcast(_ podcast: Podcast)
    func navigateToPodcastInfo(_ podcastInfo: PodcastInfo)
    func navigateTo(podcast searchResult: PodcastFolderSearchResult)

    func navigateToFolder(_ folder: Folder, popToRootViewController: Bool)
    func navigateToSuggestedFolders()

    func navigateToEpisode(_ episodeUuid: String, podcastUuid: String?, timestamp: TimeInterval?)

    func navigateToDiscover(_ animated: Bool)
    func navigateToDiscover(category: String, animated: Bool)
    func navigateToDiscover(listID: String, animated: Bool)

    func navigateToProfile(row: ProfileViewController.TableRow?, animated: Bool)

    func navigateToFilter(_ filter: EpisodeFilter?, animated: Bool)
    func navigateToEditFilter(_ filter: EpisodeFilter)
    func navigateToAddFilter()
    func presentManualPlaylistsChooser(for episode: Episode, rootViewController: UIViewController?, source: String)

    func navigateToUpNext(_ animated: Bool)

    func navigateToFiles()
    func navigateToAddCustom(_ fileURL: URL)

    func showSettings(row: SettingsViewController.TableRow?)
    func showSettingsAppearance(showThemeSelection: Bool)
    func showProfilePage()
    func showHeadphoneSettings()
    func showGeneralSettings(row: GeneralSettingsViewController.TableRow?)

    func showSignUp()
    func showTermsOfUse()
    func showPrivacyPolicy()

    func showInSafariViewController(urlString: String)

    func dismissPresentedViewController(completion: (() -> Void)?)
    func showOnboardingFlow(flow: OnboardingFlow.Flow?)
    func showNotificationsPermissions()
}
