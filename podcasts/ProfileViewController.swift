import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit
import SwiftUI

class ProfileViewController: PCViewController, UITableViewDataSource, UITableViewDelegate {
    fileprivate enum StatValueType { case listened, saved }

    private var refreshController: FullSyncRefreshController?

    @IBOutlet var footerView: UIView!
    @IBOutlet var alertIcon: UIImageView!
    @IBOutlet var lastRefreshTime: ThemeableLabel! {
        didSet {
            lastRefreshTime.style = .primaryText02
            lastRefreshTime.font = UIFont.font(with: .subheadline, maxSizeCategory: .accessibilityMedium)
            lastRefreshTime.adjustsFontForContentSizeCategory = true
        }
    }
    @IBOutlet var refreshButtonContainer: UIView!

    private var refreshButtonTitle: String = L10n.refreshNow {
        didSet {
            updateRefreshButton()
        }
    }

    private var isRefreshAnimating: Bool = false {
        didSet {
            updateRefreshButton()
        }
    }

    private var refreshButtonHostingController: UIHostingController<AnyView>?

    private func setupRefreshButton() {
        updateRefreshButton()
        if let hostingController = refreshButtonHostingController {
            hostingController.sizingOptions = .intrinsicContentSize
            addChild(hostingController)
            refreshButtonContainer.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: refreshButtonContainer.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: refreshButtonContainer.bottomAnchor),
                hostingController.view.centerXAnchor.constraint(equalTo: refreshButtonContainer.centerXAnchor),
                hostingController.view.leadingAnchor.constraint(greaterThanOrEqualTo: refreshButtonContainer.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(lessThanOrEqualTo: refreshButtonContainer.trailingAnchor)
            ])
            hostingController.didMove(toParent: self)
        }
    }

    private func updateRefreshButton() {
        let refreshButton = ProfileRefreshButton(
            title: refreshButtonTitle,
            isAnimating: isRefreshAnimating,
            action: { [weak self] in
                self?.refreshTapped()
            }
        ).setupDefaultEnvironment()

        if let hostingController = refreshButtonHostingController {
            hostingController.rootView = AnyView(refreshButton)
        } else {
            let hostingController = UIHostingController(rootView: AnyView(refreshButton))
            hostingController.view.backgroundColor = .clear
            self.refreshButtonHostingController = hostingController
        }
    }

    private let settingsCellId = "SettingsCell"

    enum TableRow { case informationalBanner, allStats, downloaded, starred, listeningHistory, help, uploadedFiles, bookmarks, peopleDirectory, bookDirectory, socialProfile, socialInbox, socialLists, socialGroups }

    private lazy var informationalBannerCoordinator: InformationalBannerViewCoordinator = {
        let viewModel = InformationalBannerViewModel(bannerType: .profile)
        return InformationalBannerViewCoordinator(viewModel: viewModel)
    }()

    @IBOutlet var profileTable: UITableView! {
        didSet {
            profileTable.register(UINib(nibName: "TopLevelSettingsCell", bundle: nil), forCellReuseIdentifier: settingsCellId)
            profileTable.register(InformationalProfileBannerCell.self, forCellReuseIdentifier: InformationalProfileBannerCell.identifier)
        }
    }

    // MARK: - Profile Header
    private lazy var headerViewModel: ProfileHeaderViewModel = {
        let viewModel = ProfileHeaderViewModel(navigationController: navigationController)

        // Listen for view size changes and update the header view cell if needed
        viewModel.viewContentSizeChanged = { [weak self] in
            self?.profileTable.reloadData()
        }

        return viewModel
    }()

    private lazy var headerView: UIView = {
        let headerView = ProfileHeaderView(viewModel: headerViewModel)

        let view = headerView.themedUIView
        view.backgroundColor = .clear

        return view
    }()

    // MARK: - View Events

    override func viewDidLoad() {
        customRightBtn = UIBarButtonItem(image: UIImage(named: "profile-settings"), style: .plain, target: self, action: #selector(settingsTapped))
        customRightBtn?.accessibilityLabel = L10n.accessibilityProfileSettings
        customRightBtn?.accessibilityIdentifier = "Settings"

        super.viewDidLoad()
        registerForPreferredContentSizeCategoryChanges { $0.updateFooterFrame() }
        navigationItem.title = L10n.profile

        profileTable.tableFooterView = footerView

        setupRefreshButton()
        updateRefreshFooterColors()
        updateFooterFrame()
        setupRefreshControl()
        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: profileTable)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Register before updateDisplayedData() starts the asynchronous badge
        // refresh so even an immediately completed request updates this table.
        addCustomObserver(SocialInboxBadgeUpdated.self) { [weak self] _ in
            self?.profileTable.reloadData()
        }
        updateDisplayedData()

        Analytics.track(.profileShown)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        presentSocialAnnouncementIfNeeded()

        addCustomObserver(PodcastsRefreshed.self) { [weak self] _ in
            self?.refreshComplete()
        }
        addCustomObserver(PodcastAdded.self) { [weak self] _ in
            self?.handleDataChangedNotification()
        }
        addCustomObserver(PodcastDeleted.self) { [weak self] _ in
            self?.handleDataChangedNotification()
        }
        addCustomObserver(PodcastRefreshFailed.self) { [weak self] _ in
            self?.refreshComplete()
        }
        addCustomObserver(PodcastRefreshThrottled.self) { [weak self] _ in
            self?.refreshComplete()
        }
        addCustomObserver(SyncCompleted.self) { [weak self] _ in
            self?.refreshComplete()
        }
        addCustomObserver(SyncFailed.self) { [weak self] _ in
            self?.refreshComplete()
        }
        addCustomObserver(SubscriptionStatusChanged.self) { [weak self] _ in
            self?.handleDataChangedNotification()
        }
        addCustomObserver(UserLoginDidChange.self) { [weak self] _ in
            self?.handleDataChangedNotification()
        }
        addCustomObserver(UserWillBeSignedOut.self) { [weak self] _ in
            self?.handleDataChangedNotification()
        }
        addCustomObserver(TappedOnSelectedTab.self) { [weak self] message in
            self?.checkForScrollTap(message)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeAllCustomObservers()
    }

    override func handleThemeChanged() {
        updateRefreshFooterColors()
    }

    private func updateRefreshFooterColors() {
        alertIcon.tintColor = ThemeColor.primaryIcon02()
    }

    // MARK: - Actions

    private func checkForScrollTap(_ message: TappedOnSelectedTab) {
        if let index = message.tabIndex, index == tabBarItem.tag, profileTable.contentOffset.y > 0 {
            profileTable.setContentOffset(CGPoint.zero, animated: true)
        }
    }

    @objc private func settingsTapped() {
        Analytics.track(.profileSettingsButtonTapped)

        let settingsController = SettingsViewController()
        navigationController?.pushViewController(settingsController, animated: true)
    }

    private func showAccountController() {
        let accountVC = AccountViewController()
        navigationController?.pushViewController(accountVC, animated: true)
    }

    private func refreshTapped() {
        Analytics.track(.profileRefreshButtonTapped)

        isRefreshAnimating = true
        lastRefreshTime.text = L10n.refreshing
        RefreshManager.shared.refreshPodcasts()
    }

    // MARK: - Data Updates

    private func refreshComplete() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.isRefreshAnimating = false
            self.updateLastRefreshDetails()
        }
    }

    private func handleDataChangedNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.updateDisplayedData()
        }
    }

    private func updateDisplayedData() {
        // Update the new header's data
        headerViewModel.update()

        updateLastRefreshDetails()
        updateFooterFrame()
        refreshTableData()
    }

    private func updateLastRefreshDetails() {
        if !ServerSettings.lastRefreshSucceeded() || !ServerSettings.lastSyncSucceeded() {
            lastRefreshTime.text = !ServerSettings.lastRefreshSucceeded() ? L10n.refreshFailed : L10n.syncFailed
            refreshButtonTitle = L10n.tryAgain
            alertIcon.isHidden = false
        } else if let lastUpdateTime = ServerSettings.lastRefreshEndTime() {
            refreshButtonTitle = L10n.refreshNow
            if abs(lastUpdateTime.timeIntervalSinceNow) > 2.days {
                lastRefreshTime.text = L10n.profileLastAppRefresh(TimeFormatter.shared.appleStyleElapsedString(date: lastUpdateTime))
                alertIcon.isHidden = false
            } else {
                lastRefreshTime.text = L10n.refreshPreviousRun(TimeFormatter.shared.appleStyleElapsedString(date: lastUpdateTime))
                alertIcon.isHidden = true
            }
        } else {
            refreshButtonTitle = L10n.refreshNow
            lastRefreshTime.text = L10n.refreshPreviousRun(L10n.timeFormatNever)
            alertIcon.isHidden = false
        }
    }

    // MARK: - UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        tableData.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableData[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = tableData[indexPath.section][indexPath.row]

        if row == .informationalBanner {
            let cell = tableView.dequeueReusableCell(withIdentifier: InformationalProfileBannerCell.identifier, for: indexPath) as! InformationalProfileBannerCell
            cell.onCloseBannerTap = { [weak self] cell in
                if let cell, let indexPath = tableView.indexPath(for: cell) {
                    self?.tableData[indexPath.section].remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                }
            }
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: settingsCellId, for: indexPath) as! TopLevelSettingsCell

        cell.settingsImage.tintColor = ThemeColor.primaryIcon01()
        cell.settingsLabel.setLetterSpacing(-0.01)
        cell.separatorInset = .zero

        switch row {
        case .informationalBanner:
            return cell
        case .allStats:
            cell.settingsImage.image = UIImage(named: "profile-stats")
            cell.settingsLabel.text = L10n.settingsStats
        case .downloaded:
            cell.settingsImage.image = UIImage(named: "profile-download")
            cell.settingsLabel.text = L10n.downloads
        case .uploadedFiles:
            cell.settingsImage.image = UIImage(named: "profile_files")
            cell.settingsLabel.text = L10n.files
        case .starred:
            cell.settingsImage.image = UIImage(named: "profile-star")
            cell.settingsLabel.text = L10n.statusStarred
        case .listeningHistory:
            cell.settingsImage.image = UIImage(named: "profile-history")
            cell.settingsLabel.text = L10n.listeningHistory
        case .help:
            cell.settingsImage.image = UIImage(named: "profile-help")
            cell.settingsLabel.text = L10n.settingsHelp
        case .bookmarks:
            cell.settingsImage.image = UIImage(named: "bookmarks-profile")
            cell.settingsLabel.text = L10n.bookmarks
        case .socialProfile:
            cell.settingsImage.image = UIImage(systemName: "at")
            if let handle = SocialIdentityStore.handle {
                cell.settingsLabel.text = "@" + handle
            } else {
                cell.settingsLabel.text = L10n.socialClaimHandle
            }
        case .socialInbox:
            cell.settingsImage.image = UIImage(systemName: "tray")
            let unread = SocialInboxBadge.unreadCount
            cell.settingsLabel.text = unread > 0 ? L10n.socialInboxRowUnread(unread) : L10n.socialInboxTitle
        case .socialLists:
            cell.settingsImage.image = UIImage(systemName: "list.star")
            cell.settingsLabel.text = L10n.socialListsTitle
        case .socialGroups:
            cell.settingsImage.image = UIImage(systemName: "person.3")
            cell.settingsLabel.text = L10n.socialGroupsTitle
        case .peopleDirectory:
            cell.settingsImage.image = UIImage(systemName: "person.2")
            cell.settingsLabel.text = L10n.peopleDirectoryTitle
        case .bookDirectory:
            cell.settingsImage.image = UIImage(systemName: "book.closed")
            cell.settingsLabel.text = L10n.bookDirectoryTitle
        }

        return cell
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        let row = tableData[indexPath.section][indexPath.row]
        return row != .informationalBanner
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let row = tableData[indexPath.section][indexPath.row]
        switch row {
        case .informationalBanner:
            return 160
        default:
            return 70
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let row = tableData[indexPath.section][indexPath.row]
        navigateToRow(row)
    }

    func navigateToRow(_ row: TableRow) {
        switch row {
        case .informationalBanner:
            break
        case .allStats:
            let statsViewController = StatsViewController()
            navigationController?.pushViewController(statsViewController, animated: true)
        case .downloaded:
            let downloadController = DownloadsViewController()
            navigationController?.pushViewController(downloadController, animated: true)
        case .uploadedFiles:
            let uploadedController = UploadedViewController()
            navigationController?.pushViewController(uploadedController, animated: true)
        case .starred:
            let starredController = StarredViewController()
            navigationController?.pushViewController(starredController, animated: true)
        case .listeningHistory:
            let historyController = ListeningHistoryViewController()
            navigationController?.pushViewController(historyController, animated: true)
        case .help:
            dismiss(animated: true)
            let navController = SJUIUtils.navController(for: OnlineSupportController())
            present(navController, animated: true, completion: nil)
        case .bookmarks:
            let bookmarksController = BookmarksProfileListController()
            navigationController?.pushViewController(bookmarksController, animated: true)
        case .peopleDirectory:
            let directoryController = ThemedHostingController(rootView: PersonDirectoryView())
            navigationController?.pushViewController(directoryController, animated: true)
        case .bookDirectory:
            let booksController = ThemedHostingController(rootView: NavigationStack { BookDirectoryView() })
            navigationController?.pushViewController(booksController, animated: true)
        case .socialProfile:
            if SocialIdentityStore.isJoined, let navigationController {
                SocialCoordinator.pushOwnProfile(on: navigationController)
            } else {
                SocialCoordinator.presentJoinFlow(from: self, navigationController: navigationController)
            }
        case .socialInbox:
            let inboxController = ThemedHostingController(rootView: SocialInboxView(viewModel: SocialInboxViewModel()))
            navigationController?.pushViewController(inboxController, animated: true)
        case .socialLists:
            let listsController = ThemedHostingController(rootView: SharedListsView(viewModel: SharedListsViewModel()))
            navigationController?.pushViewController(listsController, animated: true)
        case .socialGroups:
            let groupsController = ThemedHostingController(rootView: SocialGroupsView(viewModel: SocialGroupsViewModel()))
            navigationController?.pushViewController(groupsController, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        18
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return headerViewModel.contentSize?.height ?? UITableView.automaticDimension
    }

    private var tableData: [[ProfileViewController.TableRow]] = []

    /// One-time social announcement (grill decision: CTA row + one-time
    /// prompt). Never re-shown after any dismissal.
    private func presentSocialAnnouncementIfNeeded() {
        guard SocialAnnouncement.shouldShow, presentedViewController == nil else { return }
        SocialAnnouncement.markShown()

        let announcement = SocialAnnouncementView(
            onJoin: { [weak self] in
                guard let self else { return }
                dismiss(animated: true) {
                    SocialCoordinator.presentJoinFlow(from: self, navigationController: self.navigationController)
                }
            },
            onDismiss: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        let hosting = ThemedHostingController(rootView: announcement)
        hosting.modalPresentationStyle = .formSheet
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.medium()]
        }
        present(hosting, animated: true)
    }

    private func refreshTableData() {
        var data: [[ProfileViewController.TableRow]]
        data = [[.allStats, .downloaded, .starred, .bookmarks, .listeningHistory, .help, .uploadedFiles]]

        if FeatureFlag.speakerDirectory.enabled, let bookmarksIndex = data[0].firstIndex(of: .bookmarks) {
            data[0].insert(.peopleDirectory, at: bookmarksIndex + 1)
        }

        // Mentioned Books (Highlights S11): needs the entity substrate.
        if FeatureFlag.mentionedEntityIndex.enabled, let anchorIndex = data[0].firstIndex(of: .peopleDirectory) ?? data[0].firstIndex(of: .bookmarks) {
            data[0].insert(.bookDirectory, at: anchorIndex + 1)
        }

        // The social CTA/entry row: "Claim your @handle" before joining, the
        // owner's profile afterward (docs/Social.md; requires a synced account).
        if FeatureFlag.socialProfiles.enabled, SyncManager.isUserLoggedIn() {
            data[0].insert(.socialProfile, at: 0)
            if SocialIdentityStore.isJoined {
                data[0].insert(.socialInbox, at: 1)
                data[0].insert(.socialLists, at: 2)
                data[0].insert(.socialGroups, at: 3)
                SocialInboxBadge.refresh()
            }
        }

        if informationalBannerCoordinator.shouldShowBanner() {
            data[0].insert(.informationalBanner, at: 0)
        }

        tableData = data
        profileTable.reloadData()
    }

    private func updateFooterFrame() {
        footerView.setNeedsLayout()
        footerView.layoutIfNeeded()

        let targetSize = CGSize(width: profileTable.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let height = footerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height

        footerView.frame = CGRect(x: footerView.frame.minX, y: footerView.frame.minY, width: footerView.frame.width, height: height)
        profileTable.tableFooterView = footerView
    }
}

extension ProfileViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        // Return no adaptive presentation style, use default presentation behaviour
        return .none
    }
}

// MARK: - Refresh Control

extension ProfileViewController {
    private func setupRefreshControl() {
        let controller = FullSyncRefreshController(source: .profile)
        refreshController = controller
        profileTable.refreshControl = controller.refreshControl
    }
}
