import PocketCastsDataModel
import PocketCastsUtils
import UIKit
import SwiftUI

class FolderViewController: PCViewController {
    @IBOutlet var mainGrid: UICollectionView! {
        didSet {
            registerCells()
        }
    }

    var folder: Folder
    var podcasts: [Podcast] = []

    let gridHelper = GridHelper()

    var isEditingOrder = false
    var savedRightBarButtonItem: UIBarButtonItem?

    private var lastWillLayoutWidth: CGFloat = 0

    init(folder: Folder) {
        self.folder = folder
        super.init(nibName: "FolderViewController", bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        customRightBtn = UIBarButtonItem(image: UIImage(named: "more"), style: .plain, target: self, action: #selector(folderOptionsTapped(_:)))
        customRightBtn?.accessibilityLabel = L10n.accessibilityMoreActions
        super.viewDidLoad()

        title = folder.name

        mainGrid.dragDelegate = self
        mainGrid.dropDelegate = self
        mainGrid.dragInteractionEnabled = false
        mainGrid.reorderingCadence = .immediate

        miniPlayerStatusDidChange()

        gridHelper.configureLayout(collectionView: mainGrid)

        updateNavTintColor()
        reloadPodcasts()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if lastWillLayoutWidth != view.bounds.width {
            lastWillLayoutWidth = view.bounds.width
            updateFlowLayoutSize()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        reloadFolder()
        miniPlayerStatusDidChange()

        addCustomObserver(PodcastUpdated.self) { [weak self] _ in
            self?.reloadFolder()
        }
        addCustomObserver(FolderChanged.self) { [weak self] _ in
            self?.reloadFolder()
        }
        addCustomObserver(MiniPlayerDidAppear.self) { [weak self] _ in
            self?.miniPlayerStatusDidChange()
        }
        addCustomObserver(MiniPlayerDidDisappear.self) { [weak self] _ in
            self?.miniPlayerStatusDidChange()
        }

        Analytics.track(.folderShown, properties: ["number_of_podcasts": podcasts.count, "sort_order": folder.librarySort()])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if isEditingOrder {
            setEditingOrder(false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        removeAllCustomObservers()
    }

    private func updateNavTintColor() {
        let folderColor = AppTheme.folderColor(colorInt: folder.color)
        let titleColor = ThemeColor.filterText01(filterColor: folderColor)
        let iconColor = ThemeColor.filterIcon01(filterColor: folderColor)
        let backgroundColor = ThemeColor.filterUi01(filterColor: folderColor)

        if let themeableCollectionView = mainGrid as? ThemeableCollectionView {
            themeableCollectionView.style = ThemeStyle.primaryUi02
        }

        changeNavTint(titleColor: titleColor, iconsColor: iconColor, backgroundColor: backgroundColor)
    }

    @IBAction func addPodcastsTapped(_ sender: Any) {
        showPodcastSelectionDialog()
        Analytics.track(.folderAddPodcastsButtonTapped)
    }

    private func reloadFolder() {
        guard let updatedFolder = DataManager.sharedManager.findFolder(uuid: folder.uuid) else { return }

        folder = updatedFolder
        title = folder.name
        reloadPodcasts()

        updateNavTintColor()
    }

    @objc private func folderOptionsTapped(_ sender: UIBarButtonItem) {
        let optionsPicker = OptionsPicker(title: nil)

        let sortOption: LibrarySort = if !FeatureFlag.podcastsSortChanges.enabled, folder.librarySort() == .recentlyPlayed {
            .dateAddedNewestToOldest
        } else {
            folder.librarySort()
        }
        let sortAction = OptionAction(label: L10n.sortBy, secondaryLabel: sortOption.description, icon: "podcast-sort") {
            Analytics.track(.folderOptionsModalOptionTapped, properties: ["option": "sort_by"])
        }
        sortAction.submenu = { [weak self] in self?.makeSortOptions() }
        optionsPicker.addAction(action: sortAction)

        let editAction = OptionAction(label: L10n.folderEdit, icon: "folder-edit") { [weak self] in
            guard let folder = self?.folder else { return }

            let model = FolderModel(saveOnChange: true)
            model.name = folder.name
            model.colorInt = Int(folder.color)
            model.folderUuid = folder.uuid
            let editFolderView = EditFolderView(model: model) { [weak self] shouldCloseFolder in
                self?.dismiss(animated: true) {
                    if shouldCloseFolder {
                        self?.navigationController?.popViewController(animated: true)
                    }
                }
            }
            let hostingController = PCHostingController(rootView: editFolderView.environmentObject(Theme.sharedTheme))

            self?.present(hostingController, animated: true, completion: nil)

            Analytics.track(.folderOptionsModalOptionTapped, properties: ["option": "edit_folder"])
        }
        optionsPicker.addAction(action: editAction)

        let addRemoveAction = OptionAction(label: L10n.folderAddRemovePodcasts, icon: "folder-podcasts") { [weak self] in
            guard let self else { return }

            self.showPodcastSelectionDialog()

            Analytics.track(.folderOptionsModalOptionTapped, properties: ["option": "add_or_remove_podcasts"])
        }
        optionsPicker.addAction(action: addRemoveAction)

        let reorderAction = OptionAction(label: L10n.podcastsEdit, icon: "filter_manual_episode_order") { [weak self] in
            self?.setEditingOrder(true)
            Analytics.track(.folderOptionsModalOptionTapped, properties: ["option": "edit"])
        }
        optionsPicker.addAction(action: reorderAction)

        optionsPicker.present(from: self)

        Analytics.track(.folderOptionsButtonTapped)
    }

    private func showPodcastSelectionDialog() {
        let model = FolderModel(saveOnChange: true)
        model.name = folder.name
        model.colorInt = Int(folder.color)
        model.selectedPodcastUuids = podcasts.map(\.uuid)
        model.folderUuid = folder.uuid
        let editFoldersView = EditFolderPodcastsView(model: model) { [weak self] in
            self?.dismiss(animated: true)
        }
        let hostingController = PCHostingController(rootView: editFoldersView.environmentObject(Theme.sharedTheme))

        present(hostingController, animated: true, completion: nil)
    }

    private func makeSortOptions() -> OptionsPicker {
        let options = OptionsPicker(title: L10n.sortBy.localizedUppercase)

        if !FeatureFlag.podcastsSortChanges.enabled, folder.librarySort() == .recentlyPlayed {
            folder.sortType = Int32(LibrarySort.Old.dateAddedNewestToOldest.rawValue)
            folder.syncModified = TimeFormatter.currentUTCTimeInMillis()
            DataManager.sharedManager.save(folder: folder)
        }

        let sortOption = folder.librarySort()

        let podcastNameAction = OptionAction(label: LibrarySort.titleAtoZ.description, selected: sortOption == .titleAtoZ) { [weak self] in
            self?.changeSortOrder(.titleAtoZ)
        }

        let releaseDateAction = OptionAction(label: LibrarySort.episodeDateNewestToOldest.description, selected: sortOption == .episodeDateNewestToOldest) { [weak self] in
            self?.changeSortOrder(.episodeDateNewestToOldest)
        }

        let subscribedOrder = OptionAction(label: LibrarySort.dateAddedNewestToOldest.description, selected: sortOption == .dateAddedNewestToOldest) { [weak self] in
            self?.changeSortOrder(.dateAddedNewestToOldest)
        }

        let dragAndDropAction = OptionAction(label: LibrarySort.custom.description, selected: sortOption == .custom) { [weak self] in
            self?.changeSortOrder(.custom)
        }

        let recentlyPlayedOrder = OptionAction(label: LibrarySort.recentlyPlayed.description, selected: sortOption == .recentlyPlayed) { [weak self] in
            self?.changeSortOrder(.recentlyPlayed)
        }

        if FeatureFlag.podcastsSortChanges.enabled {
            options.addAction(action: subscribedOrder)
            options.addAction(action: releaseDateAction)
            options.addAction(action: recentlyPlayedOrder)
            options.addAction(action: podcastNameAction)
            options.addAction(action: dragAndDropAction)
        } else {
            options.addAction(action: podcastNameAction)
            options.addAction(action: releaseDateAction)
            options.addAction(action: subscribedOrder)
            options.addAction(action: dragAndDropAction)
        }

        return options
    }

    private func changeSortOrder(_ order: LibrarySort.Old) {
        folder.sortType = Int32(order.rawValue)
        folder.syncModified = TimeFormatter.currentUTCTimeInMillis()
        DataManager.sharedManager.save(folder: folder)

        NotificationCenter.postOnMainThread(FolderChanged(uuid: folder.uuid))

        Analytics.track(.folderSortByChanged, properties: ["sort_order": order])
    }

    private func miniPlayerStatusDidChange() {
        let horizontalMargin: CGFloat = Settings.libraryType() == .list ? 0 : 16
        let bottomMargin: CGFloat = Constants.effectiveMiniPlayerOffset + 8
        mainGrid.contentInset = UIEdgeInsets(top: mainGrid.contentInset.top, left: horizontalMargin, bottom: bottomMargin, right: horizontalMargin)
    }

    // TODO: change this to be diff based and see if we can use the new iOS diffable stuff
    private func reloadPodcasts() {
        podcasts = DataManager.sharedManager.allPodcastsInFolder(folder: folder)

        let badgeType = Settings.podcastBadgeType()
        // load the required badge information if the supplied badge type needs it
        // Podcast is a value type; mutate the badge count in place on the VC-owned array so the cells
        // (which read podcast.cachedUnreadCount) render the right value.
        if badgeType == .allUnplayed {
            let podcastCounts = DataManager.sharedManager.podcastUnfinishedCounts()
            for index in podcasts.indices {
                podcasts[index].cachedUnreadCount = Int(podcastCounts[podcasts[index].uuid] ?? 0)
            }
        } else if badgeType == .latestEpisode {
            for index in podcasts.indices {
                if let latestEpisode = DataManager.sharedManager.findLatestEpisode(podcast: podcasts[index]) {
                    podcasts[index].cachedUnreadCount = latestEpisode.unplayed() && !latestEpisode.archived ? 1 : 0
                } else {
                    podcasts[index].cachedUnreadCount = 0
                }
            }
        }

        mainGrid.reloadData()

        let shouldShowEmpty = podcasts.isEmpty
        refreshContentUnavailable(shouldShow: shouldShowEmpty)
    }

    override func handleThemeChanged() {
        mainGrid.reloadData()
        view.backgroundColor = ThemeColor.primaryUi02()
        refreshContentUnavailable(shouldShow: podcasts.isEmpty)
        updateNavTintColor()
    }

    private func refreshContentUnavailable(shouldShow: Bool) {
        var config: UIContentConfiguration?

        if shouldShow {
            let title = L10n.folderEmptyTitle
            let message = L10n.folderEmptyDescription
            config = ContentUnavailableConfiguration.nativeEmptyState(
                title: title,
                message: message,
                image: UIImage(named: "folder-empty"),
                action: .init(title: L10n.folderEmptyButtonTitle) { [weak self] in
                    guard let self else { return }
                    self.addPodcastsTapped(self)
                }
            )
        }

        self.contentUnavailableConfiguration = config
    }
}
