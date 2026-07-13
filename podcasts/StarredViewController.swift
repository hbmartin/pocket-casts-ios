import DifferenceKit
import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import UIKit
import PocketCastsUtils

class StarredViewController: PCViewController {
    private let episodesDataManager = EpisodesDataManager()

    @IBOutlet var starredTable: UITableView! {
        didSet {
            registerCells()
            starredTable.estimatedRowHeight = 80
            starredTable.rowHeight = UITableView.automaticDimension
            starredTable.allowsMultipleSelectionDuringEditing = true
            registerLongPress()
        }
    }

    @IBOutlet var loadingIndicator: UIActivityIndicatorView!

    var episodes = [ListEpisode]() {
        didSet {
            refreshContentUnavailable()
        }
    }
    private let refreshQueue = OperationQueue()
    var cellHeights: [IndexPath: CGFloat] = [:]
    @MainActor
    var isMultiSelectEnabled: Bool = false {
        didSet {
            setupNavBar()
            setEnclosingTabBarHidden(isMultiSelectEnabled, animated: false)
            starredTable.beginUpdates()
            starredTable.setEditing(isMultiSelectEnabled, animated: true)
            starredTable.endUpdates()
            insetAdjuster.isMultiSelectEnabled = isMultiSelectEnabled
            if isMultiSelectEnabled {
                Analytics.track(.starredMultiSelectEntered)
                multiSelectFooter.setSelectedCount(count: selectedEpisodes.count)
                multiSelectFooterBottomConstraint.constant = Constants.effectiveFooterViewPadding
                if let selectedIndexPath = longPressMultiSelectIndexPath {
                    starredTable.selectIndexPath(selectedIndexPath)
                    longPressMultiSelectIndexPath = nil
                }
            } else {
                Analytics.track(.starredMultiSelectExited)
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

    override func viewDidLoad() {
        super.viewDidLoad()

        refreshQueue.maxConcurrentOperationCount = 1
        self.title = L10n.statusStarred
        setupNavBar()
        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: starredTable)
        if SyncManager.isUserLoggedIn() {
            refreshEpisodesFromServer(animated: false)
        } else {
            refreshEpisodesFromDatabase(animated: false)
        }
        addEventObservers()
        Analytics.track(.starredShown)
    }

    func refreshEpisodesFromServer(animated: Bool) {
        loadingIndicator.isHidden = false
        loadingIndicator.startAnimating()
        refreshQueue.addOperation {
            ApiServerHandler.shared.retrieveStarred { episodes in
                // The completion arrives off-main; hand the episodes to the main actor
                // and do all state reads and mutations there
                let episodesBox = PocketCastsUtils.UncheckedSendable(episodes)
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    self.loadingIndicator.stopAnimating()
                    guard let episodes = episodesBox.value else { return }

                    let oldData = self.episodes
                    let newData = episodes.map { ListEpisode(episode: $0, tintColor: AppTheme.appTintColor()) }

                    self.starredTable.isHidden = (newData.isEmpty)
                    if animated {
                        let changeSet = StagedChangeset(source: oldData, target: newData)
                        self.starredTable.reload(using: changeSet, with: .none, setData: { data in
                            self.episodes = data
                        })
                    } else {
                        self.episodes = newData
                        self.starredTable.reloadData()
                    }
                }
            }
        }
    }

    func refreshEpisodesFromDatabase(animated: Bool) {
        let dataManager = PocketCastsUtils.UncheckedSendable(episodesDataManager)
        refreshQueue.addOperation { [weak self] in
            let newDataBox = PocketCastsUtils.UncheckedSendable(dataManager.value.starredEpisodes())

            Task { @MainActor in
                guard let self else { return }

                let oldData = self.episodes
                let newData = newDataBox.value

                self.starredTable.isHidden = (newData.isEmpty)
                if animated {
                    let changeSet = StagedChangeset(source: oldData, target: newData)
                    self.starredTable.reload(using: changeSet, with: .none, setData: { data in
                        self.episodes = data
                    })
                } else {
                    self.episodes = newData
                    self.starredTable.reloadData()
                }
            }
        }
    }

    private func addEventObservers() {
        addCustomObserver(EpisodeStarredChanged.self) { [weak self] _ in
            self?.refreshEpisodesFromDatabase(animated: true)
        }
        addCustomObserver(EpisodeDownloaded.self) { [weak self] _ in
            self?.refreshEpisodesFromDatabase(animated: true)
        }
        addCustomObserver(EpisodeDownloadStatusChanged.self) { [weak self] _ in
            self?.refreshEpisodesFromDatabase(animated: true)
        }
        addCustomObserver(EpisodeArchiveStatusChanged.self) { [weak self] _ in
            self?.refreshEpisodesFromDatabase(animated: true)
        }
        addCustomObserver(EpisodePlayStatusChanged.self) { [weak self] _ in
            self?.refreshEpisodesFromDatabase(animated: true)
        }
        addCustomObserver(ManyEpisodesChanged.self) { [weak self] _ in
            self?.refreshEpisodesFromDatabase(animated: true)
        }
    }

    func setupNavBar() {
        super.customRightBtn = isMultiSelectEnabled ? UIBarButtonItem(title: L10n.cancel, style: .plain, target: self, action: #selector(cancelTapped)) : UIBarButtonItem(title: L10n.select, style: .plain, target: self, action: #selector(selectTapped))
        super.customRightBtn?.accessibilityLabel = isMultiSelectEnabled ? L10n.accessibilityCancelMultiselect : L10n.select

        navigationItem.leftBarButtonItem = isMultiSelectEnabled ? UIBarButtonItem(title: L10n.selectAll, style: .done, target: self, action: #selector(selectAllTapped)) : nil
        navigationItem.backBarButtonItem = isMultiSelectEnabled ? nil : UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    }

    override func handleThemeChanged() {
        starredTable.reloadData()
        view.backgroundColor = ThemeColor.primaryUi02()
        refreshContentUnavailable()
    }

    private func refreshContentUnavailable() {
        var config: UIContentConfiguration?

        if episodes.isEmpty {
            let title = L10n.profileStarredNoEpisodesTitle
            let message = L10n.profileStarredNoEpisodesDesc
            config = ContentUnavailableConfiguration.nativeEmptyState(
                title: title,
                message: message,
                image: UIImage(named: "star_empty")
            )
        }

        self.contentUnavailableConfiguration = config
    }
}

// MARK: - Analytics

extension StarredViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource {
        .starred
    }
}
