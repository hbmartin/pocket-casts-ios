import PocketCastsDataModel
import UIKit

@MainActor
protocol UserEpisodeDetailProtocol: AnyObject {
    func showEdit(userEpisode: UserEpisode)
    func showDeleteConfirmation(userEpisode: UserEpisode)
    func userEpisodeDetailClosed()
    func showBookmarks(userEpisode: UserEpisode)
}

extension UserEpisodeDetailProtocol where Self: UIViewController {
    func showBookmarks(userEpisode: UserEpisode) {
        let controller = BookmarkEpisodeListController(episode: userEpisode, displayMode: .standalone)
        present(controller, animated: true)
    }
}

class UserEpisodeDetailViewController: UIViewController {
    @IBOutlet var containerView: ThemeableView! {
        didSet {
            containerView.style = .primaryUi01
        }
    }

    @IBOutlet var titleLabel: ThemeableLabel! {
        didSet {
            titleLabel.style = .primaryText01
        }
    }

    @IBOutlet var imageView: PodcastImageView!

    @IBOutlet var infoLabel: ThemeableLabel! {
        didSet {
            infoLabel.style = .primaryText02
        }
    }

    @IBOutlet var downloadingIndicator: UIActivityIndicatorView!
    @IBOutlet var downloadStatusImage: UIImageView!

    @IBOutlet var upNextStatusImage: UIImageView!
    @IBOutlet var dividerView: ThemeableView! {
        didSet {
            dividerView.style = .primaryUi05
        }
    }

    @IBOutlet var playPauseButton: PlayPauseButton!

    @IBOutlet var errorContainerHeight: NSLayoutConstraint!
    @IBOutlet var containerViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet var actionTable: ThemeableTable! {
        didSet {
            actionTable.themeStyle = .primaryUi01
        }
    }

    @IBOutlet var greyBackgroundView: UIView!
    @IBOutlet var barView: ThemeableView! {
        didSet {
            barView.style = .primaryUi05
            barView.layer.cornerRadius = 4
        }
    }

    @IBOutlet var errorContainerView: ThemeableSelectionView! {
        didSet {
            errorContainerView.unselectedStyle = .primaryUi05
            errorContainerView.style = .primaryUi06
            errorContainerView.layer.cornerRadius = 8
            errorContainerView.layer.borderWidth = 1
        }
    }

    @IBOutlet var errorExclaimationImageView: UIImageView!
    @IBOutlet var errorStatusImage: UIImageView!
    @IBOutlet var errorTypeLabel: ThemeableLabel!
    @IBOutlet var errorMessageLabel: ThemeableLabel! {
        didSet {
            errorMessageLabel.style = .primaryText02
        }
    }

    @IBOutlet var containerViewToErrorViewConstraint: NSLayoutConstraint!
    @IBOutlet var containerViewToImageViewConstraint: NSLayoutConstraint!

    var episode: UserEpisode
    weak var delegate: UserEpisodeDetailProtocol?

    var themeOverride: Theme.ThemeType?

    var playlist: AutoplayHelper.Playlist?

    /// Height of the error banner when shown. The sheet's own height is derived
    /// from the content, so this is the only fixed dimension we toggle.
    private static let errorBannerHeight: CGFloat = 100

    enum TableRow { case download, bookmarks, upNext, markAsPlayed, editDetails, delete, cancelDownload }
    let actionCellId = "UserEpisodeActionCell"

    // MARK: - Init

    init(episodeUuid: String) {
        episode = DataManager.sharedManager.findUserEpisode(uuid: episodeUuid)! // TODO: consider making this optional
        super.init(nibName: "UserEpisodeDetailViewController", bundle: nil)
    }

    init(episode: UserEpisode) {
        self.episode = episode

        super.init(nibName: "UserEpisodeDetailViewController", bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppTheme.defaultStatusBarStyle()
    }

    private var hasError = false
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = episode.title
        imageView.setUserEpisode(uuid: episode.uuid, size: .list)
        downloadStatusImage.image = UIImage(named: "episode-downloaded")
        registerCells()

        playPauseButton.isPlaying = PlaybackManager.shared.isActivelyPlaying(episodeUuid: episode.uuid)

        actionTable.backgroundColor = UIColor.clear

        greyBackgroundView.isHidden = true
        barView.isHidden = true

        hasError = episode.playbackError() || episode.downloadFailed()
        errorContainerView.isHidden = !hasError
        errorContainerHeight.constant = hasError ? UserEpisodeDetailViewController.errorBannerHeight : 0
        updateStatus()
        Analytics.track(.userFileDetailShown)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        actionTable.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: Constants.effectiveMiniPlayerOffset, right: 0)
        view.layoutIfNeeded()

        updateColors()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isAnimatingIn = false
        addObservers()
    }

    private var playStatusToken: NotificationCenter.ObservationToken?

    func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(updateFromNotification), name: Constants.Notifications.episodeDownloaded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateFromNotification), name: Constants.Notifications.episodeDownloadStatusChanged, object: nil)
        if playStatusToken == nil {
            playStatusToken = NotificationCenter.default.addObserver(for: EpisodePlayStatusChanged.self) { [weak self] _ in
                self?.updateFromNotification()
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updateDownloadProgress), name: Constants.Notifications.downloadProgress, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChanged), name: Constants.Notifications.themeChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let playStatusToken {
            NotificationCenter.default.removeObserver(playStatusToken)
        }
    }

    @objc private func handleThemeChanged() {
        updateColors()
    }

    @objc private func updateFromNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let oldEpisode = self.episode

            self.reloadEpisode()
            self.updateStatus()

            if oldEpisode.episodeStatus != self.episode.episodeStatus {
                self.actionTable.reloadData()
            }
        }
    }

    private func reloadEpisode() {
        guard let reloadedEpisode = DataManager.sharedManager.findUserEpisode(uuid: episode.uuid) else {
            return // episode no longer exists so nothing to reload
        }

        episode = reloadedEpisode
        let newHasError = episode.playbackError() || episode.downloadFailed()
        if !hasError, newHasError, !isAnimatingOut, !isAnimatingIn {
            hasError = newHasError
            animateInError()
        } else if hasError, !newHasError, !isAnimatingOut, !isAnimatingIn {
            hasError = newHasError
            animateOutError()
        }
    }

    private func updateColors() {
        view.backgroundColor = ThemeColor.primaryUi01(for: themeOverride)
        titleLabel.themeOverride = themeOverride
        containerView.themeOverride = themeOverride
        infoLabel.themeOverride = themeOverride
        dividerView.themeOverride = themeOverride
        actionTable.themeOverride = themeOverride
        errorTypeLabel.themeOverride = themeOverride
        errorMessageLabel.themeOverride = themeOverride
        errorContainerView.themeOverride = themeOverride

        playPauseButton.circleColor = ThemeColor.primaryIcon01(for: themeOverride)
        playPauseButton.playButtonColor = ThemeColor.primaryUi01(for: themeOverride)

        downloadStatusImage.tintColor = AppTheme.successGreen()
        upNextStatusImage.tintColor = ThemeColor.primaryIcon01(for: themeOverride)
    }

    private func updateStatus() {
        upNextStatusImage.isHidden = !PlaybackManager.shared.inUpNext(episode: episode)

        errorStatusImage.isHidden = !hasError
        infoLabel.text = hasError ? episode.displayableDuration(includeSize: true) : episode.displayableInfo(includeSize: true)

        if hasError {
            if episode.downloadFailed() {
                errorTypeLabel.text = L10n.playerUserEpisodeDownloadError
                errorMessageLabel.text = episode.downloadErrorDetails
            } else if episode.playbackError() {
                errorTypeLabel.text = L10n.playerUserEpisodePlaybackError
                errorMessageLabel.text = episode.playbackErrorDetails
            }
        }

        downloadStatusImage.isHidden = !episode.downloaded(pathFinder: DownloadManager.shared)
        downloadingIndicator.isHidden = !episode.downloading()

        updateDownloadProgress()
    }

    @objc func updateDownloadProgress() {
        guard let _ = DownloadManager.shared.progressManager.progressForEpisode(episode.uuid) else { return }

        if !episode.downloading() {
            reloadEpisode()
        }

        if episode.downloading() {
            infoLabel.text = episode.displayableInfo(includeSize: true)
        }

        if episode.downloading(), !downloadingIndicator.isAnimating {
            downloadingIndicator.isHidden = false
            downloadingIndicator.startAnimating()
        } else if !episode.downloading(), downloadingIndicator.isAnimating {
            downloadingIndicator.stopAnimating()
        }
    }

    // MARK: - Presentation

    private var isAnimatingIn = true
    private var isAnimatingOut = false

    /// Presents the detail options as a native sheet sized to fit its content.
    func present(from presenter: UIViewController) {
        modalPresentationStyle = .formSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [contentDetent()]
            sheet.prefersGrabberVisible = true
            sheet.delegate = self
        }
        presenter.present(self, animated: true)
    }

    /// A custom detent that sizes the sheet to fit the content. The container's
    /// height is driven by its content (Auto Layout), so we measure it rather
    /// than rely on a fixed value.
    private func contentDetent() -> UISheetPresentationController.Detent {
        .custom(identifier: .userEpisodeDetail) { [weak self] context in
            guard let self, let containerView else {
                return context.maximumDetentValue
            }
            let fittingHeight = containerView.systemLayoutSizeFitting(
                CGSize(width: self.view.bounds.width, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            return min(fittingHeight, context.maximumDetentValue)
        }
    }

    /// Dismisses the sheet. A follow-up screen may be presented from the
    /// delegate immediately after calling this; UIKit serializes the dismissal
    /// and the subsequent presentation. Pass `completion` to present something
    /// on the top-most controller once this sheet has fully left the hierarchy.
    func close(completion: (() -> Void)? = nil) {
        isAnimatingOut = true
        dismiss(animated: true, completion: completion)
        delegate?.userEpisodeDetailClosed()
    }

    // MARK: - Error state

    func animateInError() {
        errorContainerView.alpha = 0
        errorContainerView.isHidden = false
        errorContainerHeight.constant = UserEpisodeDetailViewController.errorBannerHeight

        sheetPresentationController?.animateChanges { [weak self] in
            self?.sheetPresentationController?.invalidateDetents()
            self?.view.layoutIfNeeded()
        }
        UIView.animate(withDuration: Constants.Animation.defaultAnimationTime) { [weak self] in
            self?.errorContainerView.alpha = 1
        }
    }

    func animateOutError() {
        errorContainerHeight.constant = 0

        UIView.animate(withDuration: Constants.Animation.defaultAnimationTime / 2, animations: { [weak self] in
            self?.errorContainerView.alpha = 0
        }) { [weak self] _ in
            self?.errorContainerView.isHidden = true
        }
        sheetPresentationController?.animateChanges { [weak self] in
            self?.sheetPresentationController?.invalidateDetents()
            self?.view.layoutIfNeeded()
        }
    }
}

extension UserEpisodeDetailViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Fired on interactive (swipe) dismissal only.
        Analytics.track(.userFileDetailDismissed)
        delegate?.userEpisodeDetailClosed()
    }
}

private extension UISheetPresentationController.Detent.Identifier {
    static let userEpisodeDetail = UISheetPresentationController.Detent.Identifier("userEpisodeDetail")
}

extension UserEpisodeDetailViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource { .userEpisode }
}
