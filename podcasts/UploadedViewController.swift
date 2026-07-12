import Combine
import SwiftUI
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

class UploadedViewController: PCViewController, UserEpisodeDetailProtocol {
    private let episodesDataManager = EpisodesDataManager()
    private var cancellables = Set<AnyCancellable>()

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

    var uploadedEpisodes = [UserEpisode]() {
        didSet {
            refreshContentUnavailable()
        }
    }

    var uploadedGroups: [(group: String, episodes: [UserEpisode])] = []

    func episodeAt(_ indexPath: IndexPath) -> UserEpisode? {
        uploadedGroups[safe: indexPath.section]?.episodes[safe: indexPath.row]
    }

    let headerView = UploadedStorageHeaderView()

    private var tableRefreshController: UploadedFilesRefreshController?
    var userEpisodeDetailVC: UserEpisodeDetailViewController?

    private func refreshContentUnavailable() {
        var config: UIContentConfiguration?

        if uploadedEpisodes.isEmpty {
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

        reloadAllFiles()
        addUIObservers()

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
        reloadAllFiles()
        addUIObservers()
    }

    override func handleAppDidEnterBackground() {
        // we don't need to keep our UI up to date while backgrounded, so remove all the notification observers we have
        removeAllCustomObservers()
    }

    private func addUIObservers() {
        // TODO: a table diff might be more efficient here (and have nicer animations)

        addCustomObserver(Constants.Notifications.userEpisodeDeleted, selector: #selector(handleReloadFromNotification))
        addCustomObserver(Constants.Notifications.playbackFailed, selector: #selector(handleReloadFromNotification))
        addCustomObserver(Constants.Notifications.episodePlayStatusChanged, selector: #selector(handleReloadFromNotification))
        addCustomObserver(Constants.Notifications.episodeDownloadStatusChanged, selector: #selector(handleReloadFromNotification))
        addCustomObserver(Constants.Notifications.manyEpisodesChanged, selector: #selector(handleReloadFromNotification))
        addCustomObserver(Constants.Notifications.fileSyncUploadsChanged, selector: #selector(handleReloadFromNotification))
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

    @objc private func handleReloadFromNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.reloadLocalFiles()
        }
    }

    func reloadLocalFiles() {
        uploadedEpisodes = episodesDataManager.uploadedEpisodes()
        uploadedGroups = episodesDataManager.uploadedEpisodeGroups()
        uploadsTable.isHidden = (uploadedEpisodes.isEmpty)

        uploadsTable.reloadData()
        updateHeaderView()
    }

    private func reloadAllFiles() {
        Task { await FileSyncManager.shared.syncNow() }
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

    private func removeFromUploadTable(userEpisode: UserEpisode) {
        reloadLocalFiles()
    }

    override func handleThemeChanged() {
        uploadsTable.reloadData()
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
