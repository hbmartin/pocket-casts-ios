import Combine
import SwiftUI
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

/// Section identity for the Files table: the root group hosts the storage
/// header and is always present; named sync subfolders follow A-Z.
// nonisolated: diffable snapshot identifiers must be Sendable, so the Hashable
// conformance cannot be implicitly MainActor-isolated under default isolation.
nonisolated enum UploadedFilesSection: Hashable {
    case root
    case group(String)
}

class UploadedViewController: PCViewController, UserEpisodeDetailProtocol {
    private let episodesDataManager = EpisodesDataManager()
    private var cancellables = Set<AnyCancellable>()

    private lazy var reloadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    @IBOutlet var uploadsTable: ThemeableTable! {
        didSet {
            registerLongPress()
            uploadsTable.themeStyle = .primaryUi02
            uploadsTable.allowsMultipleSelectionDuringEditing = true
            uploadsTable.rowHeight = UITableView.automaticDimension
            uploadsTable.estimatedRowHeight = 80
            uploadsTable.sectionHeaderHeight = UITableView.automaticDimension
            uploadsTable.estimatedSectionHeaderHeight = 56
            uploadsTable.sectionHeaderTopPadding = 0
        }
    }

    var dataSource: EditableDiffableDataSource<UploadedFilesSection, String>!
    private(set) var episodesByUuid = [String: UserEpisode]()
    private var fingerprintsByUuid = [String: Int]()
    private var hasAppliedSnapshot = false
    private var hasLoadedOnce = false

    func episodeAt(_ indexPath: IndexPath) -> UserEpisode? {
        guard let uuid = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return episodesByUuid[uuid]
    }

    let headerView = UploadedStorageHeaderView()

    private var tableRefreshController: UploadedFilesRefreshController?
    var userEpisodeDetailVC: UserEpisodeDetailViewController?

    private func refreshContentUnavailable() {
        var config: UIContentConfiguration?

        // hasLoadedOnce keeps the async first fetch from flashing the empty state
        if hasLoadedOnce, episodesByUuid.isEmpty {
            let title = L10n.fileUploadNoFilesTitle
            let message = L10n.fileSyncFilesEmptyMessage
            config = ContentUnavailableConfiguration.emptyState(title: title, message: message, icon: { Image("profile_files") }, actions: [
                .init(title: L10n.fileUploadAddFile) {
                    self.addFile()
                },
                .init(id: L10n.fileUploadNoFilesHelper) {
                    Button(action: {
                        self.howTo()
                    }, label: {
                        Text(L10n.fileUploadNoFilesHelper)
                            .font(.body)
                    }).buttonStyle(SimpleTextButtonStyle(theme: .sharedTheme, textColor: .primaryInteractive01))
                }
            ])
        }

        self.contentUnavailableConfiguration = config
    }

    @MainActor
    var isMultiSelectEnabled = false {
        didSet {
            setupNavBar()
            setEnclosingTabBarHidden(isMultiSelectEnabled, animated: false)
            uploadsTable.beginUpdates()
            uploadsTable.setEditing(isMultiSelectEnabled, animated: true)
            insetAdjuster.isMultiSelectEnabled = isMultiSelectEnabled
            uploadsTable.endUpdates()

            if isMultiSelectEnabled {
                Analytics.track(.uploadedFilesMultiSelectEntered)
                multiSelectActionBar.setSelectedCount(count: selectedEpisodes.count)
                multiSelectActionBarBottomConstraint.constant = Constants.effectiveFooterViewPadding
                if let selectedIndexPath = longPressMultiSelectIndexPath {
                    uploadsTable.selectIndexPath(selectedIndexPath)
                    longPressMultiSelectIndexPath = nil
                }
            } else {
                Analytics.track(.uploadedFilesMultiSelectExited)
                selectedEpisodes.removeAll()
            }
        }
    }

    var multiSelectGestureInProgress = false
    var longPressMultiSelectIndexPath: IndexPath?
    @IBOutlet var multiSelectActionBar: MultiSelectFooterView! {
        didSet {
            multiSelectActionBar.delegate = self
            multiSelectActionBar.getActionsFunc = Settings.fileMultiSelectActions
            multiSelectActionBar.setActionsFunc = Settings.updateFilesMultiSelectActions
        }
    }

    @IBOutlet var multiSelectActionBarBottomConstraint: NSLayoutConstraint!

    var selectedEpisodes = [UserEpisode]() {
        didSet {
            multiSelectActionBar.setSelectedCount(count: selectedEpisodes.count)
            updateSelectAllBtn()
        }
    }

    // MARK: - View Methods

    override func viewDidLoad() {
        setupNavBar()
        super.viewDidLoad()

        registerCells()
        dataSource = makeDataSource()
        title = L10n.files

        let controller = UploadedFilesRefreshController(source: .files)
        tableRefreshController = controller
        uploadsTable.refreshControl = controller.refreshControl

        updateHeaderView()
        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: uploadsTable)
        reloadLocalFiles()

        Analytics.track(.uploadedFilesShown)

        listenForChangedBookmarks()
    }

    var fileURL: URL?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.navigationBar.shadowImage = nil

        addUIObservers()
        reloadAllFiles()

        if let fileURL {
            let addCustomVC = AddCustomViewController(fileUrl: fileURL)

            present(SJUIUtils.popupNavController(for: addCustomVC), animated: true, completion: nil)
            self.fileURL = nil
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeAllCustomObservers()
    }

    // MARK: - App Backgrounding

    override func handleAppWillBecomeActive() {
        addUIObservers()
        reloadAllFiles()
    }

    override func handleAppDidEnterBackground() {
        // we don't need to keep our UI up to date while backgrounded, so remove all the notification observers we have
        removeAllCustomObservers()
    }

    private func addUIObservers() {
        // Diffable table diff tracked in hbmartin/pocket-casts-ios#283

        addCustomObserver(UserEpisodeDeleted.self) { [weak self] _ in
            self?.handleReloadFromNotification()
        }
        addCustomObserver(PlaybackFailed.self) { [weak self] _ in
            self?.handleReloadFromNotification()
        }
        addCustomObserver(EpisodePlayStatusChanged.self) { [weak self] _ in
            self?.handleReloadFromNotification()
        }
        addCustomObserver(EpisodeDownloadStatusChanged.self) { [weak self] _ in
            self?.handleReloadFromNotification()
        }
        addCustomObserver(ManyEpisodesChanged.self) { [weak self] _ in
            self?.handleReloadFromNotification()
        }
        addCustomObserver(FileSyncUploadsChanged.self) { [weak self] _ in
            self?.handleReloadFromNotification()
        }
    }

    func setupNavBar() {
        let rightButton = isMultiSelectEnabled ? UIBarButtonItem(title: L10n.cancel, style: .plain, target: self, action: #selector(cancelTapped)) : UIBarButtonItem(image: UIImage(named: "more"), style: .plain, target: self, action: #selector(menuTapped))
        rightButton.accessibilityLabel = isMultiSelectEnabled ? L10n.accessibilityCancelMultiselect : L10n.accessibilitySortAndOptions
        super.setCustomRightBtn(rightButton, animated: true)

        navigationItem.setLeftBarButton(isMultiSelectEnabled ? UIBarButtonItem(title: L10n.selectAll, style: .plain, target: self, action: #selector(selectAllTapped)) : nil, animated: true)
        navigationItem.setHidesBackButton(isMultiSelectEnabled, animated: true)
    }

    @objc private func menuTapped(_ sender: UIBarButtonItem) {
        Analytics.track(.uploadedFilesOptionsButtonTapped)

        let optionsPicker = OptionsPicker(title: nil)

        let addFileAction = OptionAction(label: L10n.fileUploadAddFile, icon: "filter_add") { [weak self] in
            Analytics.track(.uploadedFilesOptionsModalOptionTapped, properties: ["option": "add_file"])
            self?.addFile()
        }
        optionsPicker.addAction(action: addFileAction)

        let MultiSelectAction = OptionAction(label: L10n.selectEpisodes, icon: "option-multiselect") { [weak self] in
            Analytics.track(.uploadedFilesOptionsModalOptionTapped, properties: ["option": "select_episodes"])
            self?.isMultiSelectEnabled = true
        }
        optionsPicker.addAction(action: MultiSelectAction)

        let currentSort = UploadedSort(rawValue: Settings.userEpisodeSortBy())
        let sortAction = OptionAction(label: L10n.sortBy, secondaryLabel: currentSort?.description ?? "", icon: "podcastlist_sort") {
            Analytics.track(.uploadedFilesOptionsModalOptionTapped, properties: ["option": "sort_by"])
        }
        sortAction.submenu = { [weak self] in self?.makeSortByPicker() }
        optionsPicker.addAction(action: sortAction)

        let settingsAction = OptionAction(label: L10n.settingsFiles, icon: "podcast-settings") { [weak self] in
            Analytics.track(.uploadedFilesOptionsModalOptionTapped, properties: ["option": "files_settings"])
            self?.navigationController?.pushViewController(UploadedSettingsViewController(), animated: true)
        }
        optionsPicker.addAction(action: settingsAction)

        optionsPicker.present(from: self)
    }

    private func handleReloadFromNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.reloadLocalFiles()
        }
    }

    func reloadLocalFiles() {
        let dataManager = PocketCastsUtils.UncheckedSendable(episodesDataManager)
        // latest-wins: the many change notifications collapse into one fetch+apply
        reloadQueue.cancelAllOperations()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled != true else { return }
            let groupsBox = PocketCastsUtils.UncheckedSendable(dataManager.value.uploadedEpisodeGroups())

            Task { @MainActor in
                self?.applyUploadedGroups(groupsBox.value)
            }
        }
        reloadQueue.addOperation(operation)
    }

    private func applyUploadedGroups(_ groups: [(group: String, episodes: [UserEpisode])]) {
        hasLoadedOnce = true

        var itemsByUuid = [String: UserEpisode]()
        var fingerprints = [String: Int]()
        for group in groups {
            for episode in group.episodes {
                itemsByUuid[episode.uuid] = episode
                fingerprints[episode.uuid] = episode.renderFingerprint
            }
        }
        let changedUuids = DiffableHelpers.changedIDs(old: fingerprintsByUuid, new: fingerprints)
        episodesByUuid = itemsByUuid
        fingerprintsByUuid = fingerprints

        uploadsTable.isHidden = itemsByUuid.isEmpty
        refreshContentUnavailable()

        var snapshot = DiffableHelpers.snapshot(sections: groups.map { group in
            (section: group.group.isEmpty ? UploadedFilesSection.root : .group(group.group),
             items: group.episodes.map(\.uuid))
        })
        snapshot.reconfigureItems(changedUuids)
        apply(snapshot)
        syncSelectionAfterApply()
        updateHeaderView()
    }

    private func apply(_ snapshot: NSDiffableDataSourceSnapshot<UploadedFilesSection, String>) {
        guard hasAppliedSnapshot, view.window != nil else {
            hasAppliedSnapshot = true
            dataSource.applySnapshotUsingReloadData(snapshot)
            return
        }
        do {
            // animated applies can throw ObjC exceptions if UIKit state is mid-flight
            // (e.g. an open SwipeCellKit swipe); fall back to a plain reload
            try SJCommonUtils.catchException { [dataSource] in
                dataSource?.apply(snapshot, animatingDifferences: true)
            }
        } catch {
            FileLog.shared.addMessage("UploadedViewController: diffable apply failed, falling back to reload: \(error)")
            dataSource.applySnapshotUsingReloadData(snapshot)
        }
    }

    /// Re-selects the still-present selected rows after an animated apply and
    /// prunes selections whose episodes left the list.
    private func syncSelectionAfterApply() {
        guard isMultiSelectEnabled else { return }
        selectedEpisodes.removeAll { episodesByUuid[$0.uuid] == nil }
        for episode in selectedEpisodes {
            if let indexPath = dataSource.indexPath(for: episode.uuid) {
                uploadsTable.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        }
    }

    private func reloadAllFiles() {
        Task { [weak self] in
            await FileSyncManager.shared.syncNow()
            self?.reloadLocalFiles()
        }
        updateHeaderView()
    }

    func howTo() {
        Analytics.track(.uploadedFilesHelpButtonTapped)

        let howToView = HowToUploadView { [weak self] in self?.dismiss(animated: true) }.environmentObject(Theme.sharedTheme)
        let navController = SJUIUtils.navController(for: UIHostingController(rootView: howToView))
        present(navController, animated: true, completion: nil)
    }

    func addFile() {
        Analytics.track(.uploadedFilesAddButtonTapped)

        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: FileTypeUtil.supportedUserFileTypes, asCopy: true)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .overFullScreen
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }

    func makeSortByPicker() -> OptionsPicker {
        let optionsPicker = OptionsPicker(title: L10n.sortBy.localizedUppercase)

        UploadedSort.allCases.forEach { sort in
            optionsPicker.addAction(action: createSortAction(sort: sort))
        }

        return optionsPicker
    }

    private func createSortAction(sort: UploadedSort) -> OptionAction {
        let action = OptionAction(label: sort.description, selected: sort.rawValue == Settings.userEpisodeSortBy()) {
            Settings.setUserEpisodeSortBy(sort.rawValue)
            Analytics.track(.uploadedFilesSortByChanged, properties: ["sort_order": sort])

            self.reloadLocalFiles()
        }

        return action
    }

    @objc func updateHeaderView() {
        headerView.update()
    }

    // NARK :- UserEpisodeDetailViewControllerDelegate
    func showEdit(userEpisode: UserEpisode) {
        let editVC = AddCustomViewController(episode: userEpisode)
        navigationController?.pushViewController(editVC, animated: true)
    }

    func showDeleteConfirmation(userEpisode: UserEpisode) {
        Analytics.track(.userFileDeleteShown)
        UserEpisodeManager.presentDeleteOptions(episode: userEpisode, from: self, dismissCallback: {
            Analytics.track(.userFileDeleteDismissed)
        }) { deletedLocal, deletedEverywhere in
            Analytics.track(.userFileDeleted, properties: ["local": deletedLocal, "everywhere": deletedEverywhere])

            if deletedEverywhere {
                self.removeFromUploadTable(userEpisode: userEpisode)
            }
            if deletedLocal {
                self.reloadLocalFiles()
            }
        }
    }

    func userEpisodeDetailClosed() {
        userEpisodeDetailVC = nil
    }

    func closeAllChildrenViewControllers() {
        if let openAddFilesVC = presentedViewController?.children.first as? AddCustomViewController {
            openAddFilesVC.cancelTapped()
        }
        if let openUserEpiosdeDetails = userEpisodeDetailVC {
            openUserEpiosdeDetails.close()
        }
    }

    private func removeFromUploadTable(userEpisode _: UserEpisode) {
        reloadLocalFiles()
    }

    override func handleThemeChanged() {
        guard let dataSource else { return }
        // re-populate every visible cell with the new theme colours
        dataSource.applySnapshotUsingReloadData(dataSource.snapshot())
    }
}

// MARK: - Analytics

extension UploadedViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource {
        .files
    }
}

private extension UploadedViewController {
    func listenForChangedBookmarks() {
        let manager = PlaybackManager.shared.bookmarkManager

        // receive(on:) must precede the filter: the manager sends off-main and under
        // default MainActor isolation these operator closures are @MainActor, which
        // traps a main-queue assertion if they run on the sending thread.
        manager.onBookmarkCreated
            .receive(on: DispatchQueue.main)
            .filter { $0.podcast == nil }
            .sink { [weak self] _ in
                self?.handleReloadFromNotification()
            }
            .store(in: &cancellables)

        manager.onBookmarksDeleted
            .receive(on: DispatchQueue.main)
            .filter { $0.items.contains(where: { $0.podcast == nil }) }
            .sink { [weak self] _ in
                self?.handleReloadFromNotification()
            }
            .store(in: &cancellables)
    }
}

extension UploadedViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        let addCustomVC = AddCustomViewController(fileUrl: url)
        present(SJUIUtils.popupNavController(for: addCustomVC), animated: true, completion: nil)
    }
}
