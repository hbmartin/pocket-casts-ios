import PocketCastsDataModel
import PocketCastsServer
import UIKit
import PocketCastsUtils

@MainActor
class NavigationManager {
    static let podcastPageKey = "podcastPage"
    static let podcastKey = "podcast"

    static let folderPageKey = "folderPage"
    static let folderKey = "folder"
    static let popToRootViewController = "popToRootViewController"

    static let episodePageKey = "episodePage"
    static let episodeUuidKey = "episode"
    static let episodeTimestamp = "episodeTimestamp"

    private static let homePageKey = "homePage"
    static let podcastListPageKey = "podcastList"

    static let filterPageKey = "filterPage"
    static let filterUuidKey = "filterUuid"

    static let filterAddKey = "filterPageAdd"

    static let uploadedPageKey = "uploadedPage"
    static let uploadFileKey = "uploadFile"

    static let filesPageKey = "filesPage"

    static let showPrivacyPolicyPageKey = "showPrivacyPage"
    static let showTermsOfUsePageKey = "showTermsOfUsePage"

    static let openUrlInSafariVCKey = "openSafariVCUrlPage"
    static let safariVCUrlKey = "safariVCUrlKey"

    static let settingsPageKey = "settingsPage"
    static let settingsRowKey = "settingsRow"
    static let settingsAppearanceKey = "appearancePage"
    static let settingsAppearanceShowThemeKey = "appearanceShowThemeKey"
    static let settingsProfileKey = "profilePage"
    static let profileRowKey = "profileRow"
    static let profileRowDownloadsKey = "downloads"
    static let settingsHeadphoneKey = "headphoneSettings"

    static let onboardingFlow = "onboardingFlow"

    static let settingsGeneralKey = "generalSettingsPage"
    static let settingsGeneralRowKey = "generalSettingsRow"

    static let upNextPageKey = "upNextPage"
    static let signUpPageKey = "signUpPage"
    static let importPageKey = "importPage"

    static let featurePageKey = "featurePageKey"
    static let featureKey = "featureKey"

    static let manualPlaylistsChooserKey = "manualPlaylistsChooserKey"
    static let manualPlaylistsChooserEpisodeKey = "manualPlaylistsChooserEpisodeKey"
    static let manualPlaylistsChooserRootKey = "manualPlaylistsChooserRootKey"
    static let manualPlaylistsChooserSourceKey = "manualPlaylistsChooserSourceKey"

    static let sharedManager = NavigationManager()

    private weak var mainController: NavigationProtocol?
    var dimmingView: UIView?
    var miniPlayer: MiniPlayerViewController?

    private var firstSetupCompleted = false
    var isPhone = false

    private var lastNavKey = ""
    private var lastNavData: NSDictionary?

    init() {
        isPhone = UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.phone
    }

    // MARK: - Navigation

    func navigateTo(_ place: String, data: NSDictionary? = nil, animated: Bool = true) {
        performNavigation(place, data: data, animated: animated)
    }

    func mainViewControllerDidLoad(controller: NavigationProtocol) {
        mainController = controller
    }

    func dismissPresentedViewController(completion: (() -> Void)? = nil) {
        mainController?.dismissPresentedViewController(completion: completion)
    }

    private func performNavigation(_ place: String, data: NSDictionary?, animated: Bool) {
        lastNavKey = place
        lastNavData = data

        if place == NavigationManager.podcastPageKey {
            guard let data else { return }

            if let podcast = data[NavigationManager.podcastKey] as? Podcast {
                mainController?.navigateToPodcast(podcast)
            }
            if let podcastUuid = data[NavigationManager.podcastKey] as? String {
                if let podcast = DataManager.sharedManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true) {
                    mainController?.navigateToPodcast(podcast)
                }
            } else if let podcastInfo = data[NavigationManager.podcastKey] as? PodcastInfo {
                mainController?.navigateToPodcastInfo(podcastInfo)
            } else if let podcastHeader = data[NavigationManager.podcastKey] as? PodcastHeader {
                // legacy PodcastHeader support
                var podcastInfo = PodcastInfo()
                podcastInfo.uuid = podcastHeader.uuid
                podcastInfo.title = podcastHeader.title
                podcastInfo.shortDescription = podcastHeader.headerDescription
                podcastInfo.author = podcastHeader.author
                podcastInfo.iTunesId = podcastHeader.itunesId?.intValue

                mainController?.navigateToPodcastInfo(podcastInfo)
            } else if let searchResult = data[NavigationManager.podcastKey] as? PodcastFolderSearchResult {
                mainController?.navigateTo(podcast: searchResult)
            }
        } else if place == NavigationManager.folderPageKey {
            guard let data else { return }

            if let folder = data[NavigationManager.folderKey] as? Folder {
                mainController?.navigateToFolder(folder, popToRootViewController: (data[NavigationManager.popToRootViewController] as? Bool) ?? true)
            }
        } else if place == NavigationManager.episodePageKey {
            guard let data, let uuid = data[NavigationManager.episodeUuidKey] as? String else { return }

            mainController?.navigateToEpisode(uuid, podcastUuid: data[NavigationManager.podcastKey] as? String, timestamp: data[NavigationManager.episodeTimestamp] as? TimeInterval)
        } else if place == NavigationManager.podcastListPageKey {
            mainController?.navigateToPodcastList(animated)
        } else if place == NavigationManager.filterPageKey {
            if let data, let filterUuid = data[NavigationManager.filterUuidKey] as? String, let filter = DataManager.sharedManager.findPlaylist(uuid: filterUuid) {
                mainController?.navigateToFilter(filter, animated: animated)
            } else {
                mainController?.navigateToFilter(nil, animated: animated)
            }
        } else if place == NavigationManager.filterAddKey {
            mainController?.navigateToAddFilter()
        } else if place == NavigationManager.uploadedPageKey {
            if let data, let fileURL = data[NavigationManager.uploadFileKey] as? URL {
                mainController?.navigateToAddCustom(fileURL)
            }
        } else if place == NavigationManager.filesPageKey {
            mainController?.navigateToFiles()
        } else if place == NavigationManager.showPrivacyPolicyPageKey {
            mainController?.showPrivacyPolicy()
        } else if place == NavigationManager.showTermsOfUsePageKey {
            mainController?.showTermsOfUse()
        } else if place == NavigationManager.settingsAppearanceKey {
            var showThemeSelection = false
            if let data, let showThemeSelectionValue = data[NavigationManager.settingsAppearanceShowThemeKey] as? Bool {
                showThemeSelection = showThemeSelectionValue
            }
            mainController?.showSettingsAppearance(showThemeSelection: showThemeSelection)
        } else if place == NavigationManager.settingsProfileKey {
            navigateToProfile(data: data, animated: animated)
        }
        else if place == NavigationManager.settingsHeadphoneKey {
            mainController?.showHeadphoneSettings()
        }
        else if place == NavigationManager.openUrlInSafariVCKey {
            if let data, let urlString = data[NavigationManager.safariVCUrlKey] as? String {
                mainController?.showInSafariViewController(urlString: urlString)
            }
        } else if place == NavigationManager.onboardingFlow {
            let flow: OnboardingFlow.Flow? = data?["flow"] as? OnboardingFlow.Flow
            mainController?.showOnboardingFlow(flow: flow)
        } else if place == NavigationManager.settingsGeneralKey {
            mainController?.showGeneralSettings(row: data?[NavigationManager.settingsGeneralRowKey] as? GeneralSettingsViewController.TableRow)
        } else if place == NavigationManager.upNextPageKey {
            mainController?.navigateToUpNext(true)
        } else if place == NavigationManager.signUpPageKey {
            mainController?.showSignUp()
        } else if place == NavigationManager.settingsPageKey {
            let row = data?[NavigationManager.settingsRowKey] as? SettingsViewController.TableRow
            mainController?.showSettings(row: row)
        } else if place == NavigationManager.featurePageKey {
            navigateToFeature(data: data, animated: animated)
        } else if place == NavigationManager.manualPlaylistsChooserKey {
            if let episode = data?[NavigationManager.manualPlaylistsChooserEpisodeKey] as? Episode {
                let root = data?[NavigationManager.manualPlaylistsChooserRootKey] as? UIViewController
                let source = data?[NavigationManager.manualPlaylistsChooserSourceKey] as? String ?? "swipe"
                mainController?.presentManualPlaylistsChooser(for: episode, rootViewController: root, source: source)
            }
        }
    }

    func navigateToFeature(data: NSDictionary?, animated: Bool) {
        guard let feature = data?[NavigationManager.featureKey] as? String else {
            return
        }
        if feature == "suggestedFolders" {
            mainController?.navigateToSuggestedFolders()
        }
    }

    func navigateToProfile(data: NSDictionary?, animated: Bool) {
        guard let row = data?[NavigationManager.profileRowKey] as? String else {
            mainController?.navigateToProfile(row: nil, animated: animated)
            return
        }
        if row == NavigationManager.profileRowDownloadsKey {
            mainController?.navigateToProfile(row: .downloaded, animated: animated)
        }
    }

    func showNotificationsPermissionsModal() {
        mainController?.showNotificationsPermissions()
    }
}
