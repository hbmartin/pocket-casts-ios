import PocketCastsDataModel
import PocketCastsServer
import SafariServices
import UIKit
import Combine
import PocketCastsUtils
import SwiftUI

class MainTabBarController: UITabBarController, NavigationProtocol {

    enum Tab: Int { case podcasts, filter, explore, profile }
    private enum LegacyTab: Int { case podcasts, discover, filter, upNext, profile }
    /// Tab layout before Explore was added (indices persisted in `lastTabOpened`).
    private enum PreExploreTab: Int { case podcasts, filter, profile }
    private static let removedTabsMigrationKey = "SJLastTabOpenedRemovedDiscoverMigrated"
    private static let exploreTabMigrationKey = "SJLastTabOpenedExploreTabMigrated"

    var pcTabs = [Tab]()

    let playPauseCommand = UIKeyCommand(title: L10n.keycommandPlayPause, action: #selector(handlePlayPauseKey), input: " ", modifierFlags: [])

    private lazy var profileTabBarItem = UITabBarItem(title: L10n.profile, image: UIImage(named: "profile_tab"), tag: pcTabs.firstIndex(of: .profile) ?? -1)

    /// The last Up Next count observed, used to pulse the mini player artwork only
    /// when the queue actually changes (not on every refresh notification).
    private var previousUpNextCount: Int?

    /// Typed-message observations, registered once in `viewDidLoad` and removed in deinit.
    private var messageTokens = [NotificationCenter.ObservationToken]()

    deinit {
        // Read isolated stored properties into locals before any observer removal
        // (Swift 6.2 isolated-deinit rule).
        let tokens = messageTokens
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// `true` while the Up Next "pulse" spring is in flight, so a burst of
    /// rapid adds doesn't stack overlapping transforms on the mini player artwork.
    /// Not `private`: set from the pulse code in `+Animations`.
    var isPulsingUpNextTarget = false


    /// The viewDidAppear can trigger more than once per lifecycle, setting this flag on the first did appear prevents use from prompting more than once per lifecycle. But still wait until the tab bar has appeared to do so.
    var viewDidAppearBefore: Bool = false

    /// Displayed during database migrations
    var alert: ShiftyLoadingAlert?

    func loginAgain() {
        // Ensure the new sync is a full sync (so podcasts and episodes are retrieved)
        SyncManager.syncReason = .login
        ServerSettings.clearLastSyncTime()
        UserDefaults.standard.removeObject(forKey: "PCLastModifiedServerDate")

        // Copy data from the previous corrupted database (if possible)
        alert = ShiftyLoadingAlert(title: "Corrupted database. Recovering...")
        alert?.showAlert(self, hasProgress: false, completion: nil)
        DataManager.sharedManager.copyAllData()

        alert?.hideAlert(true, completion: {
            // Start the full sync
            let controller = SyncSigninViewController()
            controller.loginAgain = true
            SceneHelper.rootViewController()?.dismiss(animated: true)
            SceneHelper.rootViewController()?.present(controller, animated: true, completion: nil)
        })
    }

    private let errorBanner: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.clear
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.alpha = 0
        return view
    }()

    private var errorBottomSpacing: NSLayoutConstraint?
    private var dismissErrorWorkItem: DispatchWorkItem?

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = AppTheme.mainTextColor()
        label.font = .font(ofSize: 14, weight: .medium, scalingWith: .largeTitle)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontForContentSizeCategory = false
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        return label
    }()

    // MARK: - State

    private let errorBannerHeight: CGFloat = 60

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self]) { (controller: MainTabBarController, _) in
            controller.updateSystemThemeFromScene()
            controller.fixTabBarTraitCollectionOnIpad()
            controller.fireSystemThemeMayHaveChanged()
        }

        fixTabBarTraitCollectionOnIpad()

        pcTabs = [.podcasts, .filter, .explore, .profile]

        var vcsInTab = [UIViewController]()

        let podcastsController = PodcastListViewController()
        podcastsController.tabBarItem = UITabBarItem(title: L10n.podcastsPlural, image: UIImage(named: "podcasts_tab"), tag: pcTabs.firstIndex(of: .podcasts)!)

        let filtersViewController = PlaylistsViewController()
        filtersViewController.tabBarItem = UITabBarItem(title: L10n.playlists, image: UIImage(named: "playlists_tab"), tag: pcTabs.firstIndex(of: .filter)!)

        let exploreViewController = ExploreViewController()
        exploreViewController.tabBarItem = UITabBarItem(title: L10n.exploreTabTitle, image: UIImage(named: "discover_tab"), tag: pcTabs.firstIndex(of: .explore)!)

        let profileViewController = ProfileViewController()
        profileViewController.tabBarItem = profileTabBarItem

        vcsInTab = [podcastsController, filtersViewController, exploreViewController, profileViewController]

        viewControllers = vcsInTab.map { SJUIUtils.navController(for: $0) }
        selectedIndex = restoredLastTabIndex()

        // Track the initial tab opened event
        trackTabOpened(pcTabs[selectedIndex], isInitial: true)

        NavigationManager.sharedManager.mainViewControllerDidLoad(controller: self)
        setupMiniPlayer()
        updateTabBarColor()
        setupKeyboardShortcuts()

        messageTokens.append(NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.themeDidChange()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: TextEditingDidStart.self) { [weak self] _ in
            self?.textEditingDidStart()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: TextEditingDidEnd.self) { [weak self] _ in
            self?.textEditingDidEnd()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: FollowSystemThemeTurnedOn.self) { [weak self] _ in
            self?.handleFollowSystemThemeTurnedOn()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: UIApplication.WillEnterForegroundMessage.self) { [weak self] _ in
            self?.willEnterForeground()
        })

        messageTokens.append(NotificationCenter.default.addObserver(for: UpNextQueueChanged.self) { [weak self] _ in
            self?.upNextQueueDidChange()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: UpNextEpisodeRemoved.self) { [weak self] _ in
            self?.upNextQueueDidChange()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: PlaybackTrackChanged.self) { [weak self] _ in
            self?.upNextQueueDidChange()
        })
        // `UpNextEpisodeAdded` refreshes the count via the genie animation's tail, not here.
        messageTokens.append(NotificationCenter.default.addObserver(for: UpNextEpisodeAdded.self) { [weak self] message in
            self?.animateEpisodeAddedToUpNext(message)
        })
        upNextQueueDidChange()

        addBookmarkCreatedToastHandler()
        setupErrorBanner()
        setupErrorObservers()
    }

    private var cancellables = Set<AnyCancellable>()

    private var systemAppearanceObservation: Any?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        registerSceneAppearanceObserverIfNeeded()
        fireSystemThemeMayHaveChanged()

        if !viewDidAppearBefore {
            viewDidAppearBefore = true
        }

        // if this key was never set lets default to the Podcasts tab
        if UserDefaults.standard.object(forKey: Constants.UserDefaults.lastTabOpened) == nil {
            selectedIndex = pcTabs.firstIndex(of: .podcasts) ?? 0
        }

        showInitialOnboardingIfNeeded()

        optimizeDatabaseIfNeeded()

        if DataManager.loginAgain {
            loginAgain()
        }
    }

    private func optimizeDatabaseIfNeeded() {
        guard
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            appVersion != Settings.lastAppVersionThatRunVacuum,
            FeatureFlag.runVacuumOnVersionUpdate.enabled
        else {
            return
        }
        Settings.lastAppVersionThatRunVacuum = appVersion
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            // The loader is UI; the main actor's FIFO ordering guarantees present-then-dismiss
            if DataManager.sharedManager.podcastCount() > 100 {
                Task { @MainActor in self.presentLoader() }
            }
            DataManager.sharedManager.vacuumDatabase()
            Task { @MainActor in self.dismissLoader() }
        }
    }

    private func showInitialOnboardingIfNeeded() {
        // Show if the user is not logged in and has never seen the prompt before
        if SyncManager.isUserLoggedIn() || (Settings.shouldShowInitialOnboardingFlow == false && Settings.hasSeenInitialOnboardingBefore == true) {
            return
        }

        // Account-creation nagging was removed in the "fast & light" build; new users
        // still get the lightweight initial onboarding, and login stays optional via Profile.
        NavigationManager.sharedManager.navigateTo(NavigationManager.onboardingFlow, data: ["flow": OnboardingFlow.Flow.initialOnboarding])

        // Set the flag so the user won't see the on launch flow again
        Settings.shouldShowInitialOnboardingFlow = false
    }

    private func updateSystemThemeFromScene() {
        if let scene = view.window?.windowScene {
            Theme.systemIsDark = (scene.traitCollection.userInterfaceStyle == .dark)
        }
    }

    private func fixTabBarTraitCollectionOnIpad() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            traitOverrides.horizontalSizeClass = .compact
            if let rootHorizontalSizeClass = view.window?.traitCollection.horizontalSizeClass {
                tabBar.traitOverrides.horizontalSizeClass = rootHorizontalSizeClass
                if let viewControllers {
                    for vc in viewControllers {
                        vc.traitOverrides.horizontalSizeClass = rootHorizontalSizeClass
                    }
                }
            }
        }
    }
    func themeDidChange() {
        updateTabBarColor()
        updateErrorColor()
        setNeedsStatusBarAppearanceUpdate()
    }

    private func setupMiniPlayer() {
        let miniPlayer = MiniPlayerViewController(nibName: "MiniPlayerViewController", bundle: nil)
        NavigationManager.sharedManager.miniPlayer = miniPlayer

        // NOT addChild: on a UITabBarController that would register the mini
        // player as a fourth (unlabeled) tab. The accessory only needs the
        // view; NavigationManager keeps the controller alive.
        miniPlayer.containingTabController = self
        // Load the view so XIB outlets and observers are wired up before
        // it's installed as a tab accessory contentView.
        miniPlayer.loadViewIfNeeded()
    }

    // MARK: - UITabBarDelegate

    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        let tabIndex = item.tag
        guard pcTabs.indices.contains(tabIndex) else { return }

        if tabIndex == selectedIndex, let navController = selectedViewController as? UINavigationController, navController.visibleViewController == navController.viewControllers.first {
            // the user has tapped on a tab they are already at the root of, so trigger an action so we can handle this
            NotificationCenter.postOnMainThread(TappedOnSelectedTab(tabIndex: tabIndex))
        }

        if tabIndex != selectedIndex {
            let tab = pcTabs[tabIndex]
            trackTabOpened(tab)
        }

        UserDefaults.standard.set(tabIndex, forKey: Constants.UserDefaults.lastTabOpened)
    }

    private func restoredLastTabIndex() -> Int {
        guard UserDefaults.standard.object(forKey: Constants.UserDefaults.lastTabOpened) != nil else {
            UserDefaults.standard.set(true, forKey: Self.removedTabsMigrationKey)
            UserDefaults.standard.set(true, forKey: Self.exploreTabMigrationKey)
            return pcTabs.firstIndex(of: .podcasts) ?? 0
        }

        let savedIndex = UserDefaults.standard.integer(forKey: Constants.UserDefaults.lastTabOpened)

        // Saved before the discover/up next tabs were removed (5-tab layout)
        if !UserDefaults.standard.bool(forKey: Self.removedTabsMigrationKey) {
            let migratedIndex = migratedLastTabIndex(savedIndex)

            UserDefaults.standard.set(migratedIndex, forKey: Constants.UserDefaults.lastTabOpened)
            UserDefaults.standard.set(true, forKey: Self.removedTabsMigrationKey)
            UserDefaults.standard.set(true, forKey: Self.exploreTabMigrationKey)
            return migratedIndex
        }

        // Saved before the Explore tab was inserted (3-tab layout)
        if !UserDefaults.standard.bool(forKey: Self.exploreTabMigrationKey) {
            let migratedIndex = exploreMigratedLastTabIndex(savedIndex)

            UserDefaults.standard.set(migratedIndex, forKey: Constants.UserDefaults.lastTabOpened)
            UserDefaults.standard.set(true, forKey: Self.exploreTabMigrationKey)
            return migratedIndex
        }

        return clampedTabIndex(savedIndex)
    }

    private func migratedLastTabIndex(_ savedIndex: Int) -> Int {
        guard let legacyTab = LegacyTab(rawValue: savedIndex) else {
            return clampedTabIndex(savedIndex)
        }

        switch legacyTab {
        case .profile:
            return pcTabs.firstIndex(of: .profile) ?? 0
        case .filter:
            return pcTabs.firstIndex(of: .filter) ?? 0
        case .discover:
            return pcTabs.firstIndex(of: .explore) ?? 0
        case .podcasts, .upNext:
            return pcTabs.firstIndex(of: .podcasts) ?? 0
        }
    }

    /// Maps a tab index persisted by the 3-tab (pre-Explore) layout onto the
    /// current tab order, so a user restored onto e.g. Profile stays on Profile.
    private func exploreMigratedLastTabIndex(_ savedIndex: Int) -> Int {
        guard let preExploreTab = PreExploreTab(rawValue: savedIndex) else {
            return clampedTabIndex(savedIndex)
        }

        switch preExploreTab {
        case .podcasts:
            return pcTabs.firstIndex(of: .podcasts) ?? 0
        case .filter:
            return pcTabs.firstIndex(of: .filter) ?? 0
        case .profile:
            return pcTabs.firstIndex(of: .profile) ?? 0
        }
    }

    private func clampedTabIndex(_ index: Int) -> Int {
        min(max(index, 0), max(pcTabs.count - 1, 0))
    }

    // MARK: - NavigationProtocol

    func showInSafariViewController(urlString: String) {
        guard let url = URL(string: urlString) else { return }

        URLHelper.open(url, context: .externalContent, options: .init(presenter: topController()))
    }

    func navigateToPodcastList(_ animated: Bool) {
        if !switchToTab(.podcasts) { return }

        if let navController = selectedViewController as? UINavigationController {
            navController.popToRootViewController(animated: true)
        }
    }

    func navigateToExplore(_ animated: Bool) {
        if !switchToTab(.explore) { return }

        if let navController = selectedViewController as? UINavigationController {
            navController.popToRootViewController(animated: true)
        }
    }

    func navigateToFolder(_ folder: Folder, popToRootViewController: Bool = true) {
        guard let navController = selectedViewController as? UINavigationController else { return }

        if popToRootViewController {
            navController.popToRootViewController(animated: false)
        }

        let folderController = FolderViewController(folder: folder)
        navController.pushViewController(folderController, animated: true)
    }

    func navigateToSuggestedFolders() {
        guard let navController = selectedViewController as? UINavigationController else { return }

        navController.popToRootViewController(animated: false)

        guard let podcastListController = navController.topViewController as? PodcastListViewController else {
            return
        }

        podcastListController.showSuggestedFolders()
    }

    func navigateToPodcast(_ podcast: Podcast) {
        appDelegate()?.miniPlayer()?.closeUpNextAndFullPlayer(completion: { [weak self] in

            guard let strongSelf = self else { return }

            if let navController = strongSelf.selectedViewController as? UINavigationController {
                if let existingPodcastController = navController.topViewController as? PodcastViewController {
                    if let existingUuid = existingPodcastController.podcast?.uuid, existingUuid == podcast.uuid {
                        return // we're already on this podcast
                    } else {
                        navController.popViewController(animated: false)
                    }
                }

                let podcastController = PodcastViewController(podcast: podcast)
                navController.pushViewController(podcastController, animated: true)
            }
        })
    }

    func navigateToPodcastInfo(_ podcastInfo: PodcastInfo) {
        appDelegate()?.miniPlayer()?.closeUpNextAndFullPlayer(completion: { [weak self] in
            guard let navController = self?.selectedViewController as? UINavigationController else {
                return
            }

            navController.popToRootViewController(animated: false)
            let podcastController = PodcastViewController(podcastInfo: podcastInfo, existingImage: nil)
            navController.pushViewController(podcastController, animated: true)
        })
    }

    func navigateTo(podcast searchResult: PodcastFolderSearchResult) {
        if let navController = selectedViewController as? UINavigationController {
            let podcastController = PodcastViewController(podcastInfo: PodcastInfo(from: searchResult), existingImage: nil)
            navController.pushViewController(podcastController, animated: true)
        }
    }

    func navigateToEpisode(_ episodeUuid: String, podcastUuid: String?, timestamp: TimeInterval?, quote: String?) {
        if let navController = selectedViewController as? UINavigationController {
            navController.dismiss(animated: false, completion: nil)

            // I know it looks dodgy, but the episode card won't load properly if you just dismissed another view controller. Need to figure out the actual bug...but for now:
            // (before you ask, using the completion block doesn't work above, regardless of whether animated is true or false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5.seconds) {
                if EpisodeLoadingController.needsLoading(uuid: episodeUuid), let podcastUuid {
                    let episodeController = EpisodeLoadingController(episodeUuid: episodeUuid,
                                                                     podcastUuid: podcastUuid,
                                                                     timestamp: timestamp,
                                                                     quote: quote)

                    let nav = UINavigationController(rootViewController: episodeController)
                    nav.modalPresentationStyle = .formSheet
                    nav.isNavigationBarHidden = true

                    navController.present(nav, animated: true)
                } else {
                    let episodeController = EpisodeDetailViewController(episodeUuid: episodeUuid, source: .homeScreenWidget, timestamp: timestamp, quote: quote)
                    episodeController.modalPresentationStyle = .formSheet

                    navController.present(episodeController, animated: true)
                }
            }
        }
    }

    func navigateToUpNext(_ animated: Bool) {
        NavigationManager.sharedManager.miniPlayer?.showUpNext(from: .unknown)
    }

    func navigateToProfile(row: ProfileViewController.TableRow? = nil, animated: Bool) {
        switchToTab(.profile)
        guard let navController = selectedViewController as? UINavigationController else {
            return
        }
        navController.popToRootViewController(animated: animated)
        guard let profileViewController = navController.topViewController as? ProfileViewController,
            let row else {
            return
        }
        profileViewController.navigateToRow(row)
    }

    func navigateToFilter(_ filter: EpisodeFilter?, animated: Bool) {
        guard switchToTab(.filter) else { return }

        guard let navController = selectedViewController as? UINavigationController else {
            return
        }
        navController.popToRootViewController(animated: false)

        guard let filter,
              let filtersViewController = navController.topViewController as? PlaylistsViewController else {
            return
        }
        filtersViewController.showFilter(filter)
    }

    func navigateToEditFilter(_ filter: EpisodeFilter) {
        switchToTab(.filter)
    }

    func navigateToAddFilter() {
        switchToTab(.filter)
    }

    func presentManualPlaylistsChooser(for episode: Episode, rootViewController: UIViewController?, source: String) {
        guard let navController = selectedViewController as? UINavigationController else {
            return
        }
        let manualPlaylistsChooser = ManualPlaylistsChooserViewController(episode: episode, analyticsSource: source)
        let navVC = SJUIUtils.navController(for: manualPlaylistsChooser)
        if presentedViewController is PlayerContainerViewController {
            presentedViewController?.present(navVC, animated: true, completion: nil)
        } else {
            let root = rootViewController ?? navController.topViewController
            root?.present(navVC, animated: true, completion: nil)
        }
    }

    func navigateToAddCustom(_ url: URL) {
        appDelegate()?.miniPlayer()?.closeUpNextAndFullPlayer(completion: { [weak self] in
            guard let self, switchToTab(.profile),
                  let navController = selectedViewController as? UINavigationController else {
                return
            }

            if let existingUploadedViewController = navController.viewControllers.last as? UploadedViewController {
                existingUploadedViewController.closeAllChildrenViewControllers()
            }
            navController.popToRootViewController(animated: false)

            let uploadedViewController = UploadedViewController()
            uploadedViewController.fileURL = url
            navController.pushViewController(uploadedViewController, animated: false)
        })
    }

    func navigateToFiles() {
        guard switchToTab(.profile),
              let navController = selectedViewController as? UINavigationController else {
            return
        }

        navController.popToRootViewController(animated: false)

        let filesController = UploadedViewController()
        navController.pushViewController(filesController, animated: true)
    }

    func showPrivacyPolicy() {
        showInSafariViewController(urlString: ServerConstants.Urls.privacyPolicy)
    }

    func showTermsOfUse() {
        showInSafariViewController(urlString: ServerConstants.Urls.termsOfUse)
    }

    func navigateToFilterTab() {
        switchToTab(.filter)
    }

    func showSettings(row: SettingsViewController.TableRow?) {
        switchToTab(.profile)
        guard let navController = selectedViewController as? UINavigationController else { return }

        if navController.presentedViewController != nil {
            navController.dismiss(animated: false)
        }

        navController.popViewController(animated: false)
        let settingViewController = SettingsViewController()
        navController.pushViewController(settingViewController, animated: row == nil)

        guard let row else { return }

        settingViewController.selectRow(row)
    }

    func showSettingsAppearance(showThemeSelection: Bool = false) {
        switchToTab(.profile)
        if let navController = selectedViewController as? UINavigationController {
            navController.popToRootViewController(animated: false)

            navController.pushViewController(SettingsViewController(), animated: false)
            let appearanceViewController = AppearanceViewController()
            navController.pushViewController(appearanceViewController, animated: !showThemeSelection)
            if showThemeSelection {
                appearanceViewController.presentThemePicker(selectedTheme: Theme.preferredLightTheme()) { theme in
                    Theme.setPreferredLightTheme(theme, systemIsDark: Theme.systemIsDark)
                }
            }
        }
    }

    func showProfilePage() {
        switchToTab(.profile)

        if let navController = selectedViewController as? UINavigationController {
            navController.popToRootViewController(animated: false)
        }
    }

    func showHeadphoneSettings() {
        let state = NavigationManager.sharedManager.miniPlayer?.playerOpenState

        // Dismiss any presented views if the player is not already open/dismissing since it will dismiss itself
        if state != .open, state != .animating {
            dismissPresentedViewController()
        }

        switchToTab(.profile)
        if let navController = selectedViewController as? UINavigationController {
            navController.popToRootViewController(animated: false)
            navController.pushViewController(SettingsViewController(), animated: false)
            navController.pushViewController(HeadphoneSettingsViewController(), animated: true)
        }
    }

    func showGeneralSettings(row: GeneralSettingsViewController.TableRow?) {
        let state = NavigationManager.sharedManager.miniPlayer?.playerOpenState

        // Dismiss any presented views if the player is not already open/dismissing since it will dismiss itself
        if state != .open, state != .animating {
            dismissPresentedViewController()
        }

        switchToTab(.profile)
        if let navController = selectedViewController as? UINavigationController {
            navController.popToRootViewController(animated: false)
            navController.pushViewController(SettingsViewController(), animated: false)
            let generalSettingsController = GeneralSettingsViewController()
            generalSettingsController.scrollToRow = row
            navController.pushViewController(generalSettingsController, animated: true)
        }
    }

    func showSignUp() {
        switchToTab(.podcasts)
        selectedViewController?.dismiss(animated: false)
        if let rootController = view.window?.rootViewController {
            let controller = OnboardingFlow.shared.begin(flow: .loggedOut, source: .unknown)
            rootController.present(controller, animated: true, completion: nil)
        }
    }

    func dismissPresentedViewController(completion: (() -> Void)? = nil) {
        presentedViewController?.dismiss(animated: true, completion: completion)
    }

    func showOnboardingFlow(flow: OnboardingFlow.Flow?) {
        let controller = OnboardingFlow.shared.begin(flow: flow ?? .initialOnboarding, source: .onboarding)
        guard let presentedViewController else {
            present(controller, animated: true)
            return
        }

        presentedViewController.dismiss(animated: true) {
            self.present(controller, animated: true)
        }
    }

    private func topController() -> UIViewController {
        var topController: UIViewController = self
        while let presentedViewController = topController.presentedViewController {
            topController = presentedViewController
        }

        return topController
    }

    @discardableResult
    private func switchToTab(_ tab: Tab) -> Bool {
        guard let miniPlayer = NavigationManager.sharedManager.miniPlayer else { return false }

        if miniPlayer.playerOpenState == .animating {
            return false // can't switch tabs while animating
        }

        if miniPlayer.playerOpenState == .open {
            miniPlayer.closeFullScreenPlayer()
        }

        selectedIndex = pcTabs.firstIndex(of: tab)!

        return true
    }

    // MARK: - Orientation

    // we implement this here to lock all views (except presented modal VCs to portrait)
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    private func updateTabBarColor() {
        tabBar.unselectedItemTintColor = AppTheme.unselectedTabBarItemColor()
        tabBar.tintColor = AppTheme.tabBarItemTintColor()

        // Liquid Glass renders its own translucent material, so there is no opaque background
        // appearance to configure here; only the theme tint above applies.
    }

    private func willEnterForeground() {
        fireSystemThemeMayHaveChanged()
    }

    // The window's `overrideUserInterfaceStyle` masks system appearance changes
    // from view controllers inside it, so `traitCollectionDidChange` never fires
    // for system light/dark flips. Observe at the scene level instead — scene
    // traits aren't affected by the per-window override.
    private func registerSceneAppearanceObserverIfNeeded() {
        guard systemAppearanceObservation == nil,
              let scene = view.window?.windowScene else { return }
        systemAppearanceObservation = scene.registerForTraitChanges(
            [UITraitUserInterfaceStyle.self]
        ) { [weak self] (scene: UIWindowScene, _: UITraitCollection) in
            Theme.systemIsDark = (scene.traitCollection.userInterfaceStyle == .dark)
            self?.fireSystemThemeMayHaveChanged()
        }
    }

    private var lastNotifiedAboutDark: Bool?
    private func fireSystemThemeMayHaveChanged() {
        if !Settings.shouldFollowSystemTheme() { return } // if the user has turned this off, then ignore system theme changes

        let isDark = Theme.systemIsDark
        if lastNotifiedAboutDark == nil || isDark != lastNotifiedAboutDark {
            lastNotifiedAboutDark = isDark
            NotificationCenter.postOnMainThread(SystemThemeMayHaveChanged(isDark: isDark))
        }
    }

    private func handleFollowSystemThemeTurnedOn() {
        lastNotifiedAboutDark = nil
        fireSystemThemeMayHaveChanged()
    }


    // There are different areas of the app that relies on presenting VCs from the tab bar
    // However, sometimes the tab bar is already displaying the player.
    // This code simple checks if the tab bar is already presenting something and, if yes,
    // present the VC through the presentedViewController
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        if let presentedViewController, !presentedViewController.isBeingDismissed {
            presentedViewController.present(viewControllerToPresent, animated: flag, completion: completion)
            return
        }

        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }

        // Sleep-timer restart keeps priority while a timer is running; otherwise
        // debug/TestFlight builds get the feedback sheet (Deferred Item 67).
        if Settings.shakeToRestartSleepTimer, PlaybackManager.shared.sleepTimerActive() {
            PlaybackManager.shared.restartSleepTimer()
        } else if BuildEnvironment.current != .appStore {
            presentShakeFeedback()
        }
    }

    private func presentShakeFeedback() {
        // One sheet at a time; never shake-present over an existing modal.
        guard presentedViewController == nil else { return }

        let sheet = ThemedHostingController(rootView: ShakeFeedbackView(model: ShakeFeedbackViewModel()))
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium()]
            presentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }
}

// MARK: - Bookmarks

private extension MainTabBarController {
    // Shows a toast notification when a bookmark is created and we're not in the full screen player
    func addBookmarkCreatedToastHandler() {
        let bookmarkManager = PlaybackManager.shared.bookmarkManager

        bookmarkManager.onBookmarkCreated
            .receive(on: RunLoop.main)
            .filter { _ in
                UIApplication.shared.applicationState == .active
                && NavigationManager.sharedManager.miniPlayer?.playerOpenState == .closed
            }
            .compactMap { event in
                bookmarkManager.bookmark(for: event.uuid)
            }
            .sink { [weak self] bookmark in
                self?.showToast(for: bookmark)
            }
            .store(in: &cancellables)
    }

    func showToast(for bookmark: Bookmark) {
        let bookmarkManager = PlaybackManager.shared.bookmarkManager

        let title = bookmark.title
        let message = title == L10n.bookmarkDefaultTitle ? L10n.bookmarkAdded : L10n.bookmarkAddedNotification(title)

        let action: Toast.Action
        if FeatureFlag.highlightEditor.enabled {
            // Full editor: trim + tags + title (Highlights program S4).
            action = Toast.Action(title: L10n.highlightToastEdit) { [weak self] in
                let controller = HighlightEditorPresenter.controller(
                    manager: bookmarkManager,
                    bookmark: bookmark,
                    source: .headphones
                )
                self?.presentFromRootController(controller)
            }
        } else {
            action = Toast.Action(title: L10n.changeBookmarkTitle) { [weak self] in
                let controller = BookmarkEditTitleViewController(manager: bookmarkManager, bookmark: bookmark, state: .updating, onDismiss: { [weak self] updatedTitle, _ in
                    guard title != updatedTitle else { return }

                    self?.handleBookmarkTitleUpdated(updatedTitle: updatedTitle)
                })

                controller.source = .headphones

                self?.presentFromRootController(controller)
            }
        }

        Toast.show(message, actions: [action], theme: .playerTheme)
    }

    func handleBookmarkTitleUpdated(updatedTitle: String) {
        Toast.show(L10n.bookmarkUpdatedNotification(updatedTitle), actions: [
            .init(title: L10n.bookmarkAddedButtonTitle, action: { [weak self] in
                self?.showBookmarksInPlayer()
            })
        ], theme: .playerTheme)
    }

    func showBookmarksInPlayer() {
        dismissIfNeeded {
            NavigationManager.sharedManager.miniPlayer?.openFullScreenPlayer {
                NavigationManager.sharedManager.miniPlayer?.fullScreenPlayer?.scrollToBookmarks()
            }
        }
    }
}

// MARK: - Analytics

private extension MainTabBarController {
    /// Tracks when a tab is switched to.
    /// - Parameters:
    ///   - tab: Which tab we're switching to
    ///   - isInitial: Whether this is the tab that is being loaded on first launch
    func trackTabOpened(_ tab: Tab, isInitial: Bool = false) {
        let event: AnalyticsEvent
        switch tab {
        case .podcasts:
            event = .podcastsTabOpened
        case .filter:
            event = .filtersTabOpened
        case .explore:
            event = .discoverTabOpened
        case .profile:
            event = .profileTabOpened
        }

        Analytics.track(event, properties: ["initial": isInitial])
    }
}

// MARK: - Notifications

extension MainTabBarController {

    func showNotificationsPermissions() {
        present(NotificationsPermissionsViewModel.makeController(), animated: true)
    }
}

// MARK: - Error Status

extension MainTabBarController {

    private func setupErrorBanner() {
        view.addSubview(errorBanner)
        errorBanner.addSubview(errorLabel)

        let bottomSpacing = errorBanner.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        bottomSpacing.priority = .defaultLow
        self.errorBottomSpacing = bottomSpacing

        errorBanner.isUserInteractionEnabled = true
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(errorTapped))
        errorBanner.addGestureRecognizer(tapRecognizer)

        NSLayoutConstraint.activate([
            // Pin banner to the very bottom of the view (below tab bar)
            errorBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomSpacing,
            errorBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            // Error label
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: errorBanner.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: errorBanner.trailingAnchor, constant: -16),
            errorLabel.centerXAnchor.constraint(equalTo: errorBanner.centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: errorBanner.topAnchor, constant: 0),
            errorLabel.bottomAnchor.constraint(equalTo: errorBanner.bottomAnchor, constant: 0),
        ])
    }

    private func setupErrorObservers() {
        // Only events that can change the active playback error are relevant:
        // failure, start, and pause.
        messageTokens.append(NotificationCenter.default.addObserver(for: PlaybackFailed.self) { [weak self] _ in
            self?.updateError()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: PlaybackStarted.self) { [weak self] _ in
            self?.updateError()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: PlaybackPaused.self) { [weak self] _ in
            self?.updateError()
        })
    }

    private func updateError() {
        DispatchQueue.main.async { [weak self] in
            guard let error = PlaybackManager.shared.activeError else {
                self?.hideError()
                return
            }
            if self?.errorBanner.isHidden == true {
                self?.showError(error, autoDismissAfter: 5)
            }
        }
    }

    private func showError(_ error: PlaybackManager.PlaybackError, autoDismissAfter seconds: TimeInterval? = nil) {
        if !(presentedViewController is PlayerContainerViewController) {
            // do not track this if the full screen player is visible
            AnalyticsPlaybackHelper.shared.playbackErrorShown(playerSource: .miniPlayer)
        }
        errorLabel.attributedText = error.shortUserAttributedMessage(mainColor: AppTheme.mainTextColor(), interactiveColor: ThemeColor.primaryInteractive01())
        errorBanner.isUserInteractionEnabled = error.userAction != nil
        errorBanner.layoutIfNeeded()
        errorBanner.isHidden = false
        errorBottomSpacing?.priority = .required
        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: .curveEaseInOut) { [weak self] in
            guard let self else { return }
            self.errorBanner.alpha = 1
            let baseBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
            // Push child content up so it doesn't hide behind the shifted tab bar
            self.additionalSafeAreaInsets = UIEdgeInsets(
                top: 0, left: 0, bottom: self.errorBannerHeight - baseBottom, right: 0
            )
            self.view.layoutIfNeeded()
        }

        dismissErrorWorkItem?.cancel()
        if let seconds {
            let item = DispatchWorkItem { [weak self] in self?.hideError() }
            dismissErrorWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        }
    }

    private func hideError() {
        errorBottomSpacing?.priority = .defaultLow
        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: .curveEaseInOut) { [weak self] in
            guard let self else { return }
            self.errorBanner.alpha = 0

            // Reset content insets
            self.additionalSafeAreaInsets = .zero
            self.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.errorBanner.isHidden = true
        }
    }

    @objc private func errorTapped() {
        guard let error = PlaybackManager.shared.activeError,
              let url = error.userAction
        else {
            return
        }
        AnalyticsPlaybackHelper.shared.playbackErrorTapped(playerSource: .miniPlayer)
        URLHelper.open(url, context: .trustedDocumentation, options: .init(presenter: self, modalPresentationStyle: .formSheet))
    }

    private func updateErrorColor() {
        errorBanner.backgroundColor = UIColor.clear
        errorLabel.textColor = AppTheme.mainTextColor()
    }
}

// MARK: - Up Next queue pulse

extension MainTabBarController {
    func upNextQueueDidChange() {
        let count = PlaybackManager.shared.upNextCount()
        let previous = previousUpNextCount
        previousUpNextCount = count

        guard count != previous else { return }

        // Only celebrate the queue growing — a drain (playing/removing) shouldn't pop.
        if previous.map({ count > $0 }) ?? false { pulseUpNextTarget() }
    }
}
