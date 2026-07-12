import PocketCastsDataModel
import PocketCastsUtils
import PocketCastsServer
import SwiftUI
import TipKit
import UIKit

/// Tip anchored to the Up Next sort button, teaching that the queue can be reordered.
///
/// Shows at most once, and never once the user has used the sort button.
nonisolated struct UpNextSortTip: Tip {
    var title: Text {
        Text(L10n.upNextSortTipTitle)
    }

    var message: Text? {
        Text(L10n.upNextSortTipMessage)
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

class UpNextViewController: UIViewController, UIGestureRecognizerDelegate {
    static let playerCell = "PlayerCell"
    static let nowPlayingCell = "UpNextNowPlayingCell"
    static let emptyStateCell = "EmptyStateCell"
    static let upNextSection = 1
    static var upNextRowHeight: CGFloat = UITableView.automaticDimension

    static let nowPlayingRowHeight: CGFloat = UITableView.automaticDimension

    static var emptyStateRowHeight: CGFloat = UITableView.automaticDimension

    static let rearrangeWidth: CGFloat = 60
    static let bottomMargin: CGFloat = 8

    enum sections: Int { case nowPlayingSection = 0, upNextSection }

    var tableData = [sections]()

    var themeOverride: Theme.ThemeType? = nil

    lazy var contentInseter = {
        InsetAdjuster()
    }()

    @MainActor
    var isMultiSelectEnabled = false {
        didSet {
            guard oldValue != isMultiSelectEnabled else { return }

            updateNavBarButtons()
            setEnclosingTabBarHidden(isMultiSelectEnabled, animated: false)
            contentInseter.isMultiSelectEnabled = isMultiSelectEnabled
            if !isMultiSelectEnabled {
                multiSelectActionBar.isHidden = true
                selectedPlayListEpisodes.removeAll()
                track(.upNextMultiSelectExited)
            } else {
                track(.upNextMultiSelectEntered)
            }
            updateNavBarButtons(animated: true)
            if showingInTab {
                multiSelectActionBarBottomConstraint.constant = Constants.effectiveMiniPlayerOffset + Self.bottomMargin
            }
            animateMultiSelectChange()
        }
    }

    var changedViaSwipeToRemove = false

    let remainingLabel = ThemeableLabel()
    // Use HitTargetButton so these small header controls meet Apple's recommended 44x44pt minimum tap target without changing their visible size.
    let shuffleButton = HitTargetButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    let sortButton = HitTargetButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    let clearQueueButton = HitTargetButton(frame: CGRect(x: 0, y: 0, width: 93, height: 16))
    var selectedPlayListEpisodes = [PlaylistEpisode]() {
        didSet {
            multiSelectActionBar.setSelectedCount(count: selectedPlayListEpisodes.count)
            if selectedPlayListEpisodes.isEmpty {
                contentInseter.isMultiSelectEnabled = false
            } else {
                contentInseter.isMultiSelectEnabled = true
            }
            // While multi-select is being toggled the nav bar is updated (animated)
            // by `isMultiSelectEnabled`'s observer. Only react here to selection
            // changes that happen while multi-select is active, to switch between
            // the Select All / Deselect All buttons without fighting that animation.
            if isMultiSelectEnabled {
                updateNavBarButtons()
            }
        }
    }

    lazy var headerView: UIView = {
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 48))

        updateTimeRemainingLabel()
        headerView.addSubview(remainingLabel)
        NSLayoutConstraint.activate([
            remainingLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            remainingLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),
            remainingLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8)
        ])

        headerView.addSubview(sortButton)
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        sortButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            sortButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            sortButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            sortButton.widthAnchor.constraint(equalToConstant: 24),
            sortButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        // The shuffle/clear buttons sit to the sort button's left.
        let trailingButtonAnchor = sortButton.leadingAnchor
        let trailingButtonConstant: CGFloat = -16

        headerView.addSubview(shuffleButton)
        shuffleButton.translatesAutoresizingMaskIntoConstraints = false
        shuffleButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            shuffleButton.trailingAnchor.constraint(equalTo: trailingButtonAnchor, constant: trailingButtonConstant),
            shuffleButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            shuffleButton.leadingAnchor.constraint(greaterThanOrEqualTo: remainingLabel.trailingAnchor, constant: 10),
            shuffleButton.widthAnchor.constraint(equalToConstant: 24),
            shuffleButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        headerView.addSubview(clearQueueButton)
        clearQueueButton.translatesAutoresizingMaskIntoConstraints = false
        clearQueueButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            clearQueueButton.trailingAnchor.constraint(equalTo: trailingButtonAnchor, constant: trailingButtonConstant),
            clearQueueButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            clearQueueButton.leadingAnchor.constraint(greaterThanOrEqualTo: remainingLabel.trailingAnchor, constant: 10)
        ])

        clearQueueButton.isHidden = true
        shuffleButton.isHidden = PlaybackManager.shared.upNextCount() == 0
        sortButton.isHidden = PlaybackManager.shared.upNextCount() < 2
        updateSize()
        return headerView
    }()

    var multiSelectGestureInProgress = false
    var isReorderInProgress = false

    private var sortTipVC: UIViewController?

    @IBOutlet var upNextTable: ThemeableTable! {
        didSet {
            upNextTable.themeOverride = themeOverride
            upNextTable.register(UINib(nibName: "PlayerCell", bundle: nil), forCellReuseIdentifier: UpNextViewController.playerCell)
            upNextTable.register(UINib(nibName: "UpNextNowPlayingCell", bundle: nil), forCellReuseIdentifier: UpNextViewController.nowPlayingCell)
            upNextTable.register(EmptyStateCell.self, forCellReuseIdentifier: UpNextViewController.emptyStateCell)
            upNextTable.backgroundView = nil
            upNextTable.isEditing = true
            upNextTable.addGestureRecognizer(customLongPressGesture)
            upNextTable.allowsMultipleSelectionDuringEditing = true
            upNextTable.allowsMultipleSelection = true
        }
    }

    @IBOutlet var multiSelectActionBar: MultiSelectFooterView! {
        didSet {
            multiSelectActionBar.delegate = self
            multiSelectActionBar.getActionsFunc = Settings.upNextMultiSelectActions
            multiSelectActionBar.setActionsFunc = Settings.updateUpNextMultiSelectActions
            multiSelectActionBar.themeOverride = themeOverride
        }
    }

    @IBOutlet var multiSelectActionBarBottomConstraint: NSLayoutConstraint!

    lazy var customLongPressGesture: UILongPressGestureRecognizer = {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(tableLongPressed(_:)))
        longPressRecognizer.delegate = self

        return longPressRecognizer
    }()

    let source: UpNextViewSource
    let showingInTab: Bool

    init(source: UpNextViewSource, themeOverride: Theme.ThemeType? = nil, showingInTab: Bool = false) {
        self.source = source
        self.themeOverride = !showingInTab && Settings.darkUpNextTheme ? .dark : themeOverride
        self.showingInTab = showingInTab
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForPreferredContentSizeCategoryChanges { $0.updateSize() }

        title = L10n.upNext

        (view as? ThemeableView)?.style = .primaryUi04
        (view as? ThemeableView)?.themeOverride = themeOverride

        NotificationCenter.default.addObserver(self, selector: #selector(upNextChanged), name: Constants.Notifications.playbackTrackChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(upNextChanged), name: Constants.Notifications.playbackEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(upNextChanged), name: Constants.Notifications.upNextQueueChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(upNextChanged), name: Constants.Notifications.upNextEpisodeAdded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(upNextChanged), name: Constants.Notifications.upNextEpisodeRemoved, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTimeRemainingLabel), name: Constants.Notifications.playbackProgress, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reorderingDidBegin), name: .tableViewReorderWillBegin, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reorderingDidEnd), name: .tableViewReorderDidEnd, object: nil)

        if showingInTab {
            NotificationCenter.default.addObserver(self, selector: #selector(updateShuffleButtonState), name: Constants.Notifications.upNextShuffleToggle, object: nil)
        }

        remainingLabel.font = UIFont.font(ofSize: 14, weight: .medium, scalingWith: .footnote)
        remainingLabel.adjustsFontSizeToFitWidth = true
        remainingLabel.adjustsFontForContentSizeCategory = true
        remainingLabel.minimumScaleFactor = 0.8
        remainingLabel.numberOfLines = 3
        remainingLabel.style = .primaryText02
        remainingLabel.themeOverride = themeOverride
        remainingLabel.translatesAutoresizingMaskIntoConstraints = false

        setupActionButtonsIfNecessary()

        contentInseter.setupInsetAdjustmentsForMiniPlayer(scrollView: upNextTable)

        refreshSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavBarButtons()
        setupActionButtonsIfNecessary()
        themeDidChange()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // fix issues with the now playing cell not animating by reloading it on appear
        reloadTable()

        track(.upNextShown, properties: ["source": source])

        AnalyticsHelper.upNextOpened()

        showUpNextSortTipIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        guard isViewLoaded else { return } // This method was called as a result of `setSelectedIndex` on UITabBarController. The view is not loaded at this point so we don't need to do anything to reset.
        selectedPlayListEpisodes.removeAll()
        isMultiSelectEnabled = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        track(.upNextDismissed)
    }

    @objc func clearQueueTapped() {
        let queueCount = PlaybackManager.shared.upNextCount()

        let alert = UIAlertController(title: L10n.clearUpNext, message: L10n.clearUpNextMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: actionLabelText(queueCount), style: .destructive) { [weak self] _ in
            self?.performClearAll()
        })
        present(alert, animated: true)

        selectedPlayListEpisodes.removeAll()
        isMultiSelectEnabled = false
    }

    @objc private func shuffleButtonTapped() {
        if !SyncManager.isUserLoggedIn() {
            // Shuffle still requires an account so the order can sync. Send the
            // user to the login/onboarding flow instead of a paywall.
            let onboardingController = OnboardingFlow.shared.begin(flow: .loggedOut, source: .upNextShuffle)
            if let mainTabBar = presentingViewController?.presentingViewController, presentingViewController is PlayerContainerViewController {
                dismiss(animated: true) {
                    mainTabBar.present(onboardingController, animated: true)
                }
            } else {
                present(onboardingController, animated: true)
            }
            return
        }
        Settings.upNextShuffleToggle()
        if !showingInTab {
            updateShuffleButtonState()
        }
        let upNextShuffleEnabled = Settings.upNextShuffleEnabled()
        if upNextShuffleEnabled {
            Toast.show(L10n.upNextShuffleToastMessage)
        }
        track(.upNextShuffleEnabled, properties: ["value": upNextShuffleEnabled])
    }

    @objc private func themeDidChange() {
        if !SyncManager.isUserLoggedIn() {
            shuffleButton.setImage(UIImage(named: "shuffle-plus"), for: .normal)
            shuffleButton.isSelected = false
        } else {
            let unselected = UIImage(named: "shuffle")?.withTintColor(AppTheme.colorForStyle(.primaryIcon02, themeOverride: themeOverride), renderingMode: .alwaysOriginal)
            let selected = UIImage(named: "shuffle-enabled")?.withTintColor(AppTheme.colorForStyle(.primaryIcon01, themeOverride: themeOverride), renderingMode: .alwaysOriginal)
            shuffleButton.setImage(unselected, for: .normal)
            shuffleButton.setImage(selected, for: .selected)
            updateShuffleButtonState()
        }
        shuffleButton.imageView?.adjustsImageSizeForAccessibilityContentSizeCategory = true
        shuffleButton.imageView?.contentMode = .scaleAspectFit
        shuffleButton.imageView?.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func subscriptionStatusDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Update UI
            setupActionButtonsIfNecessary()
            themeDidChange()
            updateNavBarButtons()
            reloadTable()
        }
    }

    private func setupActionButtonsIfNecessary() {
        if shuffleButton.allTargets.isEmpty {
            NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Constants.Notifications.themeChanged, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(subscriptionStatusDidChange), name: ServerNotifications.subscriptionStatusChanged, object: nil)
            themeDidChange()
            shuffleButton.addTarget(self, action: #selector(shuffleButtonTapped), for: .touchUpInside)
        }
        setupSortButtonIfNecessary()
    }

    private func setupSortButtonIfNecessary() {
        guard sortButton.allTargets.isEmpty else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(updateSortButtonImage), name: Constants.Notifications.themeChanged, object: nil)
        updateSortButtonImage()
        sortButton.addTarget(self, action: #selector(sortButtonTapped), for: .touchUpInside)
    }

    @objc private func updateSortButtonImage() {
        let image = UIImage(named: "podcast-sort")?
            .withTintColor(AppTheme.colorForStyle(.primaryIcon02, themeOverride: themeOverride), renderingMode: .alwaysOriginal)
        sortButton.setImage(image, for: .normal)
        sortButton.imageView?.adjustsImageSizeForAccessibilityContentSizeCategory = true
        sortButton.imageView?.contentMode = .scaleAspectFit
        sortButton.accessibilityLabel = L10n.upNextSortTitle
    }

    @objc private func sortButtonTapped() {
        guard PlaybackManager.shared.upNextCount() >= 2 else { return }

        // The user found the sort button; no need to keep teaching it.
        UpNextSortTip().invalidate(reason: .actionPerformed)

        let optionsPicker = makeSortOptionsPicker()
        optionsPicker.present(from: self)
    }

    private func showUpNextSortTipIfNeeded() {
        guard
            PlaybackManager.shared.upNextCount() >= 2,
            !sortButton.isHidden,
            sortButton.window != nil,
            !isMultiSelectEnabled,
            sortTipVC == nil,
            presentedViewController == nil
        else {
            return
        }

        let tip = UpNextSortTip()
        guard tip.shouldDisplay else { return }

        let tipVC = TipUIPopoverViewController(tip, sourceItem: sortButton)
        sortTipVC = tipVC
        present(tipVC, animated: true)

        // Dismiss the popover once the tip is invalidated (close button, sort
        // button used, or its single allowed display ending).
        Task { [weak self] in
            for await shouldDisplay in tip.shouldDisplayUpdates where !shouldDisplay {
                self?.dismissUpNextSortTip()
                break
            }
        }
    }

    private func dismissUpNextSortTip() {
        guard let sortTipVC else { return }
        self.sortTipVC = nil
        sortTipVC.dismiss(animated: true)
    }

    private func makeSortOptionsPicker() -> OptionsPicker {
        let optionsPicker = OptionsPicker(title: L10n.upNextSortTitle.localizedUppercase, themeOverride: themeOverride)
        for option in UpNextSortOption.allCases {
            let action = OptionAction(label: option.description) { [weak self] in
                let playbackManager = PlaybackManager.shared
                playbackManager.reorderUpNext(sortedEpisodes: option.sort(playbackManager.allUpNextEpisodes(includeNowPlaying: false)))
                self?.reloadTable()
                self?.track(.upNextSort, properties: ["sort_type": option.analyticsDescription])
            }
            optionsPicker.addAction(action: action)
        }
        return optionsPicker
    }

    @objc private func updateShuffleButtonState() {
        shuffleButton.isSelected = Settings.upNextShuffleEnabled()
    }

    private func actionLabelText(_ queueCount: Int) -> String {
        if queueCount == 1 {
            return L10n.queueClearEpisodeQueueSingular
        }
        return L10n.queueClearEpisodeQueuePlural(queueCount.localized())
    }

    private func performClearAll() {
        PlaybackManager.shared.clearUpNextList()
        reloadTable()
        track(.upNextQueueCleared)
    }

    var userEpisodeDetailVC: UserEpisodeDetailViewController?

    func showEpisodeDetailViewController(for episode: BaseEpisode?) {
        if let episode = episode as? Episode, let parentPodcast = episode.parentPodcast() {
            let episodeController = EpisodeDetailViewController(episode: episode, podcast: parentPodcast, source: .upNext)
            episodeController.modalPresentationStyle = .formSheet
            episodeController.themeOverride = themeOverride
            present(episodeController, animated: true, completion: nil)
        } else if let userEpisode = episode as? UserEpisode {
            if let fullEpisode = DataManager.sharedManager.findUserEpisode(uuid: userEpisode.uuid) {
                userEpisodeDetailVC = UserEpisodeDetailViewController(episode: fullEpisode)
                userEpisodeDetailVC?.delegate = self
                userEpisodeDetailVC?.themeOverride = themeOverride
                userEpisodeDetailVC?.present(from: self)
            }
        }
    }

    @objc func updateTimeRemainingLabel() {
        var totalDuration = PlaybackManager.shared.upNextTotalDuration(includePlayingEpisode: false)
        if let episode = PlaybackManager.shared.currentEpisode() {
            totalDuration += episode.duration.seconds - PlaybackManager.shared.currentTime()
        }
        remainingLabel.text = L10n.queueTotalTimeRemaining(TimeFormatter.shared.multipleUnitFormattedShortTime(time: totalDuration))
    }

    // MARK: - UIGestureRecongizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer != customLongPressGesture { return true }

        let touchPoint = gestureRecognizer.location(in: upNextTable)
        return touchPoint.x < (view.bounds.width - UpNextViewController.rearrangeWidth)
    }

    // MARK: - Nav bar actions

    @objc func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc func selectTapped() {
        isMultiSelectEnabled = true
    }

    @objc func selectAllTapped() {
        guard DataManager.sharedManager.allUpNextEpisodes().count > 1 else { return }
        upNextTable.selectAllBelow(fromIndexPath: IndexPath(row: 0, section: sections.upNextSection.rawValue))

        track(.upNextSelectAllButtonTapped, properties: ["select_all": true])
        updateNavBarButtons()
    }

    @objc func cancelTapped() {
        isMultiSelectEnabled = false
    }

    @objc func deselectAllTapped() {
        upNextTable.deselectAll()
        track(.upNextSelectAllButtonTapped, properties: ["select_all": false])
    }

    func updateNavBarButtons(animated: Bool = false) {
        navigationController?.navigationBar.tintColor = AppTheme.navBarIconsColor(themeOverride: themeOverride)

        let leftButton: UIBarButtonItem?
        let rightButton: UIBarButtonItem?

        if isMultiSelectEnabled {
            if MultiSelectHelper.shouldSelectAll(onCount: selectedPlayListEpisodes.count, totalCount: PlaybackManager.shared.upNextCount()) {
                rightButton = UIBarButtonItem(title: L10n.selectAll, style: .plain, target: self, action: #selector(selectAllTapped))
            } else {
                rightButton = UIBarButtonItem(title: L10n.deselectAll, style: .plain, target: self, action: #selector(deselectAllTapped))
            }
            leftButton = UIBarButtonItem(title: L10n.cancel, style: .plain, target: self, action: #selector(cancelTapped))
        } else if !isMultiSelectEnabled, PlaybackManager.shared.upNextCount() > 0 {
            rightButton = UIBarButtonItem(title: L10n.select, style: .plain, target: self, action: #selector(selectTapped))
            if showingInTab {
                if PlaybackManager.shared.upNextCount() > 0 {
                    leftButton = UIBarButtonItem(title: L10n.clear, style: .plain, target: self, action: #selector(clearQueueTapped))
                } else {
                    leftButton = nil
                }
            } else {
                leftButton = UIBarButtonItem(title: L10n.done, style: .plain, target: self, action: #selector(doneTapped))
            }
        } else {
            rightButton = nil
            if showingInTab {
                leftButton = nil
            } else {
                leftButton = UIBarButtonItem(title: L10n.done, style: .plain, target: self, action: #selector(doneTapped))
            }
        }

        navigationItem.setRightBarButton(rightButton, animated: animated)
        navigationItem.setLeftBarButton(leftButton, animated: animated)
    }

    private func animateMultiSelectChange() {
        if !isMultiSelectEnabled {
            upNextTable.indexPathsForSelectedRows?.forEach {
                upNextTable.deselectRow(at: $0, animated: false)
            }
        }

        for case let cell as PlayerCell in upNextTable.visibleCells {
            cell.shouldShowSelect(show: isMultiSelectEnabled, animate: true)
        }
    }

    // MARK: - Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }
}

// MARK: - Reordering Notifications

extension UpNextViewController {
    @objc func reorderingDidBegin() {
        isReorderInProgress = true
        PlaybackManager.shared.recordUpNextUserInteraction()
    }

    @objc func reorderingDidEnd() {
        isReorderInProgress = false
    }
}

// MARK: - Analytics

extension UpNextViewController {
    func track(_ event: AnalyticsEvent, properties: [String: Any]? = nil) {
        // Default keys win, matching the previous merging behaviour
        var props: [String: any Sendable] = ["source": source]
        for (key, value) in properties ?? [:] where props[key] == nil {
            switch value {
            case let v as String: props[key] = v
            case let v as Int: props[key] = v
            case let v as Double: props[key] = v
            case let v as Bool: props[key] = v
            case let v as AnalyticsDescribable: props[key] = v.analyticsDescription
            default: props[key] = String(describing: value)
            }
        }

        Analytics.track(event, properties: props)
    }
}

enum UpNextViewSource: String, AnalyticsDescribable {
    case miniPlayer = "mini_player"
    case nowPlaying = "now_playing"
    case player
    case lockScreenWidget = "lock_screen_widget"
    case tabBar = "tab_bar"
    case unknown

    var analyticsDescription: String { rawValue }
}

/// Sort orders offered by the Up Next sort button; a one-off reorder, so there's no persisted "current" option.
nonisolated enum UpNextSortOption: CaseIterable, AnalyticsDescribable {
    case newestToOldest
    case oldestToNewest
    case shortestToLongest
    case longestToShortest

    /// User facing label shown in the options picker.
    var description: String {
        switch self {
        case .newestToOldest:
            return L10n.upNextSortNewestToOldest
        case .oldestToNewest:
            return L10n.upNextSortOldestToNewest
        case .shortestToLongest:
            return L10n.upNextSortShortestToLongest
        case .longestToShortest:
            return L10n.upNextSortLongestToShortest
        }
    }

    var analyticsDescription: String {
        switch self {
        case .newestToOldest:
            return "newest_to_oldest"
        case .oldestToNewest:
            return "oldest_to_newest"
        case .shortestToLongest:
            return "shortest_to_longest"
        case .longestToShortest:
            return "longest_to_shortest"
        }
    }

    /// Returns the episodes reordered for this option. Both publish-date and time-remaining sorts break ties by added date so the order is deterministic; for time-remaining sorts, episodes with unknown duration also sink to the bottom.
    func sort(_ episodes: [BaseEpisode]) -> [BaseEpisode] {
        switch self {
        case .newestToOldest:
            return sortedByPublishedDate(episodes, ascending: false)
        case .oldestToNewest:
            return sortedByPublishedDate(episodes, ascending: true)
        case .shortestToLongest:
            return sortedByTimeRemaining(episodes, ascending: true)
        case .longestToShortest:
            return sortedByTimeRemaining(episodes, ascending: false)
        }
    }

    private func sortedByPublishedDate(_ episodes: [BaseEpisode], ascending: Bool) -> [BaseEpisode] {
        // Missing dates sort last: to the future when ascending, to the past when descending.
        let fallback: Date = ascending ? .distantFuture : .distantPast
        return episodes.sorted { lhs, rhs in
            let lhsDate = lhs.publishedDate ?? fallback
            let rhsDate = rhs.publishedDate ?? fallback

            // Same published date (including both missing): keep the order they were added.
            if lhsDate == rhsDate {
                return (lhs.addedDate ?? .distantPast) < (rhs.addedDate ?? .distantPast)
            }

            return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
        }
    }

    private func sortedByTimeRemaining(_ episodes: [BaseEpisode], ascending: Bool) -> [BaseEpisode] {
        episodes.sorted { lhs, rhs in
            let lhsHasDuration = lhs.duration > 0
            let rhsHasDuration = rhs.duration > 0

            // Episodes with no known duration always sink to the bottom.
            if lhsHasDuration != rhsHasDuration {
                return lhsHasDuration
            }

            // Compare by the episodes time remaining.
            let lhsRemaining = lhs.duration - lhs.playedUpTo
            let rhsRemaining = rhs.duration - rhs.playedUpTo

            // Same time remaining (including both unknown): keep the order they were added.
            if lhsRemaining == rhsRemaining {
                return (lhs.addedDate ?? .distantPast) < (rhs.addedDate ?? .distantPast)
            }

            return ascending ? lhsRemaining < rhsRemaining : lhsRemaining > rhsRemaining
        }
    }
}

extension UpNextViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource {
        .upNext
    }
}

// MARK: - Dynamic Type support
extension UpNextViewController {

    func updateSize() {
        let metric = UIFontMetrics(forTextStyle: .largeTitle)
        let buttonSize = max(24, metric.scaledValue(for: 24))
        shuffleButton.updateSizeConstraints(to: buttonSize)
        sortButton.updateSizeConstraints(to: buttonSize)
    }
}
