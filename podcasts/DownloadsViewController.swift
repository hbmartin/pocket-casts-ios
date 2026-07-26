import SwiftUI
import Dependencies
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

class DownloadsViewController: PCViewController {
    @Dependency(\.downloadManager) var downloadManager: any DownloadManaging

    var episodes = [(title: String, episodes: [ListEpisode])]() {
        didSet {
            refreshContentUnavailable()
        }
    }

    var dataSource: EditableDiffableDataSource<String, String>!
    private(set) var episodesByUuid = [String: ListEpisode]()
    private var fingerprintsByUuid = [String: Int]()
    private var hasAppliedSnapshot = false
    private var refreshGate = LatestRefreshGate()

    private let episodesDataManager = EpisodesDataManager()

    private lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    @IBOutlet var downloadsTable: ThemeableTable! {
        didSet {
            registerTableCells()
            registerLongPress()
            downloadsTable.allowsMultipleSelectionDuringEditing = true
            downloadsTable.themeStyle = .primaryUi02
        }
    }

    @MainActor
    var isMultiSelectEnabled = false {
        didSet {
            setupNavBar()
            setEnclosingTabBarHidden(isMultiSelectEnabled, animated: false)
            downloadsTable.beginUpdates()
            downloadsTable.setEditing(isMultiSelectEnabled, animated: true)
            insetAdjuster.isMultiSelectEnabled = isMultiSelectEnabled
            downloadsTable.endUpdates()

            if isMultiSelectEnabled {
                Analytics.track(.downloadsMultiSelectEntered)
                multiSelectFooter.setSelectedCount(count: selectedEpisodes.count)
                multiSelectFooterBottomConstraint.constant = Constants.effectiveFooterViewPadding
                if let selectedIndexPath = longPressMultiSelectIndexPath {
                    downloadsTable.selectIndexPath(selectedIndexPath)
                    longPressMultiSelectIndexPath = nil
                }
            } else {
                Analytics.track(.downloadsMultiSelectExited)
                selectedEpisodes.removeAll()
            }
        }
    }

    var multiSelectGestureInProgress = false
    var longPressMultiSelectIndexPath: IndexPath?
    @IBOutlet var multiSelectFooter: MultiSelectFooterView! {
        didSet {
            multiSelectFooter.delegate = self
        }
    }

    @IBOutlet var multiSelectFooterBottomConstraint: NSLayoutConstraint!

    var selectedEpisodes = [ListEpisode]() {
        didSet {
            multiSelectFooter.setSelectedCount(count: selectedEpisodes.count)
            updateSelectAllBtn()
        }
    }

    // MARK: - View Methods

    override func viewDidLoad() {
        setupNavBar()
        super.viewDidLoad()
        registerForPreferredContentSizeCategoryChanges { $0.updateSize() }

        dataSource = makeDataSource()
        downloadsTable.tableFooterView = UIView(frame: CGRect.zero)
        downloadsTable.sectionFooterHeight = 0.0

        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: downloadsTable)

        title = L10n.downloads
        view.backgroundColor = ThemeColor.primaryUi02()

        showManageDownloadsBanner()

        Analytics.track(.downloadsShown)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.navigationBar.shadowImage = nil

        reloadEpisodes()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showManageDownloadsBanner()
        addEventObservers()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        removeAllCustomObservers()
    }

    private var firstShowOfBanner = true

    private func showManageDownloadsBanner() {
        guard ManageDownloadsCoordinator.shouldShowBanner
        else {
            downloadsTable.tableHeaderView = nil
            return
        }
        if firstShowOfBanner {
            firstShowOfBanner = false
            Analytics.track(.freeUpSpaceBannerShown)
        }
        downloadsTable.tableHeaderView = makeBannerView()
    }

    private func makeBannerView() -> UIView {
        let model = ManageDownloadsModel(initialSize: "",
                                         onManageTap: { [weak self] in
            Analytics.track(.freeUpSpaceManageDownloadsTapped, properties: ["source": "downloads"])
            self?.navigationController?.pushViewController(DownloadedFilesViewController(), animated: true)
        }, onNotNowTap: { [weak self] in
            Analytics.track(.freeUpSpaceMaybeLaterTapped, properties: ["source": "downloads"])
            Settings.manageDownloadsLastCheckDate = Date.now
            self?.showManageDownloadsBanner()
            self?.reapplySnapshotReloadingData()
        })
        let banner = ManageDownloadsBannerView(dataModel: model).themedUIView
        banner.translatesAutoresizingMaskIntoConstraints = false
        let largeCategories = Set<UIContentSizeCategory>([.accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge])
        let largeSize = largeCategories.contains(traitCollection.preferredContentSizeCategory)
        let metrics = UIFontMetrics(forTextStyle: .callout)
        let bannerHeight = metrics.scaledValue(for: largeSize ? 200 : 132)
        let wrapperView = UIView(frame: CGRect(x: 116, y: 0, width: 200, height: bannerHeight))
        wrapperView.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor, constant: -16),
            banner.topAnchor.constraint(equalTo: wrapperView.topAnchor, constant: 16),
            banner.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor, constant: 0),
        ])
        return wrapperView
    }

    // MARK: - App Backgrounding

    override func handleAppWillBecomeActive() {
        reloadEpisodes()
        addEventObservers()
    }

    override func handleAppDidEnterBackground() {
        // we don't need to keep our UI up to date while backgrounded, so remove all the notification observers we have
        removeAllCustomObservers()
    }

    private func refreshView() {
        reloadEpisodes()
    }

    private func refreshContentUnavailable() {
        var config: UIContentConfiguration?

        if episodes.isEmpty {
            let title = L10n.downloadsNoDownloadsTitle
            let message = L10n.downloadsNoDownloadsDesc
            config = ContentUnavailableConfiguration.nativeEmptyState(
                title: title,
                message: message,
                image: UIImage(named: "filter_downloaded")
            )
        }

        self.contentUnavailableConfiguration = config
    }

    override func handleThemeChanged() {
        reapplySnapshotReloadingData()
        view.backgroundColor = ThemeColor.primaryUi02()
        refreshContentUnavailable()
    }

    /// Re-populates every visible cell (new theme colours, banner changes)
    /// without diffing.
    private func reapplySnapshotReloadingData() {
        guard let dataSource else { return }
        dataSource.applySnapshotUsingReloadData(dataSource.snapshot())
    }

    private func addEventObservers() {
        addCustomObserver(PodcastsRefreshed.self) { [weak self] _ in
            self?.refreshView()
        }
        addCustomObserver(OpmlImportCompleted.self) { [weak self] _ in
            self?.refreshView()
        }

        addCustomObserver(EpisodeDownloaded.self) { [weak self] _ in
            self?.refreshView()
        }
        addCustomObserver(PlaybackTrackChanged.self) { [weak self] _ in
            self?.refreshView()
        }
        addCustomObserver(PlaybackEnded.self) { [weak self] _ in
            self?.refreshView()
        }
        addCustomObserver(EpisodeStarredChanged.self) { [weak self] _ in
            self?.refreshView()
        }
        addCustomObserver(EpisodeArchiveStatusChanged.self) { [weak self] _ in
            self?.refreshView()
        }
        addCustomObserver(EpisodeDownloadStatusChanged.self) { [weak self] _ in
            self?.refreshView()
        }
        addCustomObserver(ManyEpisodesChanged.self) { [weak self] _ in
            self?.refreshView()
        }
    }

    func reloadEpisodes() {
        let dataManager = PocketCastsUtils.UncheckedSendable(episodesDataManager)
        // latest-wins: a burst of change notifications collapses into one fetch+apply
        let generation = refreshGate.begin()
        operationQueue.cancelAllOperations()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled != true else { return }
            let newDataBox = PocketCastsUtils.UncheckedSendable(dataManager.value.downloadedEpisodeSections())
            guard operation?.isCancelled != true else { return }

            Task { @MainActor in
                guard let self, refreshGate.isCurrent(generation) else { return }
                applyDownloads(newDataBox.value, generation: generation)
            }
        }
        operationQueue.addOperation(operation)
    }

    private func applyDownloads(_ newData: [(title: String, episodes: [ListEpisode])], generation: Int) {
        downloadsTable.isHidden = newData.isEmpty
        episodes = newData

        var itemsByUuid = [String: ListEpisode]()
        var fingerprints = [String: Int]()
        for section in newData {
            for listEpisode in section.episodes {
                itemsByUuid[listEpisode.episode.uuid] = listEpisode
                fingerprints[listEpisode.episode.uuid] = listEpisode.renderFingerprint
            }
        }
        let changedUuids = DiffableHelpers.changedIDs(old: fingerprintsByUuid, new: fingerprints)
        episodesByUuid = itemsByUuid
        fingerprintsByUuid = fingerprints

        var snapshot = DiffableHelpers.snapshot(sections: newData.map { (section: $0.title, items: $0.episodes.map(\.episode.uuid)) })
        snapshot.reconfigureItems(changedUuids)
        apply(snapshot) { [weak self] in
            guard let self, refreshGate.isCurrent(generation) else { return }
            syncSelectionAfterApply()
        }
    }

    private func apply(_ snapshot: NSDiffableDataSourceSnapshot<String, String>, completion: (() -> Void)? = nil) {
        let shouldAnimate = hasAppliedSnapshot && view.window != nil
        hasAppliedSnapshot = true
        DiffableHelpers.apply(
            snapshot,
            to: dataSource,
            animatingDifferences: shouldAnimate,
            context: "DownloadsViewController",
            completion: completion
        )
    }

    /// Re-selects the still-present selected rows after an animated apply and
    /// prunes selections whose episodes left the list.
    private func syncSelectionAfterApply() {
        guard isMultiSelectEnabled else { return }
        selectedEpisodes = DiffableHelpers.refreshedSelection(
            selectedEpisodes,
            id: { $0.episode.uuid },
            modelsByID: episodesByUuid
        )
        for listEpisode in selectedEpisodes {
            if let indexPath = dataSource.indexPath(for: listEpisode.episode.uuid) {
                downloadsTable.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        }
    }

    func setupNavBar() {
        let rightButton = isMultiSelectEnabled ? UIBarButtonItem(title: L10n.cancel, style: .plain, target: self, action: #selector(cancelTapped)) : UIBarButtonItem(image: UIImage(named: "more"), style: .plain, target: self, action: #selector(menuTapped))
        rightButton.accessibilityLabel = isMultiSelectEnabled ? L10n.accessibilityCancelMultiselect : L10n.accessibilitySortAndOptions
        super.setCustomRightBtn(rightButton, animated: true)

        navigationItem.setLeftBarButton(isMultiSelectEnabled ? UIBarButtonItem(title: L10n.selectAll, style: .plain, target: self, action: #selector(selectAllTapped)) : nil, animated: true)
        navigationItem.setHidesBackButton(isMultiSelectEnabled, animated: true)
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func menuTapped(_ sender: UIBarButtonItem) {
        Analytics.track(.downloadsOptionsButtonTapped)

        let optionsPicker = OptionsPicker(title: nil)

        let MultiSelectAction = OptionAction(label: L10n.selectEpisodes, icon: "option-multiselect") { [weak self] in
            Analytics.track(.downloadsOptionsModalOptionTapped, properties: ["option": "select_episodes"])
            self?.isMultiSelectEnabled = true
        }
        optionsPicker.addAction(action: MultiSelectAction)

        let settingsAction = OptionAction(label: L10n.downloadsAutoDownload, icon: "podcast-settings") { [weak self] in
            Analytics.track(.downloadsOptionsModalOptionTapped, properties: ["option": "auto_download_settings"])
            self?.navigationController?.pushViewController(DownloadSettingsViewController(), animated: true)
        }
        optionsPicker.addAction(action: settingsAction)

        if !failedEpisodes().isEmpty {
            let retryAction = OptionAction(label: L10n.downloadsRetryFailedDownloads, icon: "option-download-retry") { [weak self] in
                Analytics.track(.downloadsOptionsModalOptionTapped, properties: ["option": "retry_failed_downloads"])
                self?.retryAllFailed(sender)
            }
            optionsPicker.addAction(action: retryAction)
        }

        if !downloadingEpisodes().isEmpty {
            let stopAction = OptionAction(label: L10n.downloadsStopAllDownloads, icon: "option-cross-circle") { [weak self] in
                Analytics.track(.downloadsOptionsModalOptionTapped, properties: ["option": "stop_all_downloads"])
                self?.pauseAllDownloads()
            }
            optionsPicker.addAction(action: stopAction)
        }

        let cleanupAction = OptionAction(label: L10n.cleanUp, icon: "list_delete") { [weak self] in
            Analytics.track(.downloadsOptionsModalOptionTapped, properties: ["option": "clean_up"])
            self?.navigationController?.pushViewController(DownloadedFilesViewController(), animated: true)
        }
        optionsPicker.addAction(action: cleanupAction)

        optionsPicker.show(statusBarStyle: preferredStatusBarStyle)
    }

    private func pauseAllDownloads() {
        let episodeToPause = downloadingEpisodes()
        for episode in episodeToPause {
            downloadManager.removeFromQueue(episodeUuid: episode.uuid, fireNotification: false, userInitiated: false)
        }

        refreshView()
    }

    private func retryAllFailed(_ barButton: UIBarButtonItem) {
        retryAllFailed()
    }

    private func retryAllFailed() {
        NetworkUtils.shared.downloadEpisodeRequested(autoDownloadStatus: .notSpecified, { [weak self] later in
            guard let self else { return }

            let failedList = self.failedEpisodes()
            for episode in failedList {
                if later {
                    self.downloadManager.queueForLaterDownload(episodeUuid: episode.uuid, fireNotification: false, autoDownloadStatus: .notSpecified)
                } else {
                    self.downloadManager.addToQueue(episodeUuid: episode.uuid, fireNotification: false, autoDownloadStatus: .notSpecified)
                }
            }

            self.refreshView()
        }, disallowed: nil)
    }

    private func failedEpisodes() -> [Episode] {
        episodes.flatMap { $0.episodes.map(\.episode).filter { $0.downloadFailed() } }
    }

    private func downloadingEpisodes() -> [Episode] {
        episodes.flatMap { $0.episodes.map(\.episode).filter { $0.downloading() || $0.queued() } }
    }

    private func updateSize() {
        showManageDownloadsBanner()
    }
}

// MARK: - Analytics

extension DownloadsViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource {
        .downloads
    }
}
