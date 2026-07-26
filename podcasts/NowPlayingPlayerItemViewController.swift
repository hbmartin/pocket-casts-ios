import Agrume
import AVKit
import SafariServices
import UIKit
import PocketCastsUtils
import SwiftUI
import PocketCastsServer

class NowPlayingPlayerItemViewController: PlayerItemViewController {
    var showingCustomImage = false
    var lastChapterIndexRendered = -1

    /// Low-res artwork handed over from the mini player when opening the full
    /// screen player.
    var placeholderArtwork: UIImage?

    private var bannerTask: Task<Void, Never>? = nil

    // Detect Display Zoom (zoomed display makes UI elements appear larger).
    // Scale controls down slightly when zoomed to avoid oversized buttons.
    private var isZoomed: Bool {
        A11y.isDisplayZoomed
    }

    var videoViewController: VideoViewController?

    @IBOutlet var skipBackBtn: SkipButton! {
        didSet {
            skipBackBtn.skipBack = true
        }
    }

    @IBOutlet var skipFwdBtn: SkipButton! {
        didSet {
            skipFwdBtn.skipBack = false
            skipFwdBtn.longPressed = { [weak self] in
                self?.skipForwardLongPressed()
            }
        }
    }

    @IBOutlet var playPauseBtn: PlayPauseButton!

    @IBOutlet var episodeImage: UIImageView! {
        didSet {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
            tapGesture.numberOfTapsRequired = 1
            tapGesture.numberOfTouchesRequired = 1
            episodeImage.addGestureRecognizer(tapGesture)
        }
    }

    /// Dims the artwork in the paused state. Lives inside `episodeImage` so it
    /// inherits the rounded-corner clipping and the paused scale transform.
    /// The image view's own alpha can't be used — it is the video-mode switch.
    lazy var artworkDimView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    @IBOutlet var episodeName: ThemeableLabel! {
        didSet {
            episodeName.style = .playerContrast01
            episodeName.adjustsFontForContentSizeCategory = true
            episodeName.font = .font(ofSize: 18, weight: .semibold, scalingWith: .largeTitle)
        }
    }

    @IBOutlet var podcastName: ThemeableLabel! {
        didSet {
            podcastName.style = .playerContrast02
            podcastName.adjustsFontForContentSizeCategory = true
            podcastName.font = .font(ofSize: 14, weight: .medium, scalingWith: .largeTitle)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(podcastNameTapped))
            podcastName.addGestureRecognizer(tapGesture)

            podcastName.accessibilityTraits = .button
            podcastName.accessibilityHint = L10n.accessibilityHintPlayerNavigateToPodcastLabel
        }
    }

    @IBOutlet var chapterName: ThemeableLabel! {
        didSet {
            chapterName.style = .playerContrast01
            chapterName.adjustsFontForContentSizeCategory = true
            chapterName.font = .font(ofSize: 18, weight: .semibold, scalingWith: .largeTitle)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(chapterNameTapped))
            chapterName.addGestureRecognizer(tapGesture)
        }
    }

    @IBOutlet var floatingVideoView: FloatingVideoView! {
        didSet {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(videoTapped))
            tapGesture.numberOfTapsRequired = 1
            tapGesture.numberOfTouchesRequired = 1
            floatingVideoView.addGestureRecognizer(tapGesture)
        }
    }

    // MARK: - Chapters

    @IBOutlet var chapterSkipBackBtn: UIButton! {
        didSet {
            chapterSkipBackBtn.tintColor = ThemeColor.playerContrast01()
        }
    }

    @IBOutlet var chapterSkipFwdBtn: UIButton! {
        didSet {
            chapterSkipFwdBtn.tintColor = ThemeColor.playerContrast01()
        }
    }

    @IBOutlet var chapterCounter: ThemeableLabel! {
        didSet {
            chapterCounter.style = .playerContrast02
            chapterCounter.adjustsFontForContentSizeCategory = true
            chapterCounter.font = .font(ofSize: 12, weight: .semibold, scalingWith: .largeTitle)
        }
    }

    @IBOutlet var chapterTimeLeftLabel: UILabel! {
        didSet {
            chapterTimeLeftLabel.adjustsFontForContentSizeCategory = true
            chapterTimeLeftLabel.font = .font(ofSize: 11, weight: .semibold, scalingWith: .largeTitle).monospaced()
        }
    }

    @IBOutlet var chapterProgress: ProgressCircleView! {
        didSet {
            chapterProgress.lineWidth = 2
            chapterProgress.lineColor = ThemeColor.playerContrast03()
        }
    }

    @IBOutlet var chapterLink: UIView! {
        didSet {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(chapterLinkTapped))
            chapterLink.addGestureRecognizer(tapGesture)
        }
    }

    @IBOutlet var chapterInfoView: UIView!
    @IBOutlet var episodeInfoView: UIView!

    @IBOutlet var shelfBg: ThemeableView! {
        didSet {
            shelfBg.style = .playerContrast06
        }
    }

    // MARK: - Time Slider

    @IBOutlet var timeSlider: TimeSlider! {
        didSet {
            timeSlider.accessibilityLabel = L10n.accessibilityEpisodePlayback
            timeSlider.delegate = self
        }
    }

    @IBOutlet var playerControlsStackView: UIStackView!

    @IBOutlet var timeSliderHolderView: UIView!

    @IBOutlet var timeElapsed: ThemeableLabel! {
        didSet {
            timeElapsed.style = .playerContrast02
            let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: UIFont.Weight.medium)
            let metrics = UIFontMetrics(forTextStyle: .largeTitle)
            timeElapsed.font = metrics.scaledFont(for: baseFont)
            timeElapsed.adjustsFontForContentSizeCategory = true
        }
    }

    @IBOutlet var timeRemaining: ThemeableLabel! {
        didSet {
            timeRemaining.style = .playerContrast02
            let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: UIFont.Weight.medium)
            let metrics = UIFontMetrics(forTextStyle: .largeTitle)
            timeRemaining.font = metrics.scaledFont(for: baseFont)
            timeRemaining.adjustsFontForContentSizeCategory = true
        }
    }

    @IBOutlet var playPauseHeightConstraint: NSLayoutConstraint!

    @IBOutlet weak var fillView: UIView!

    @IBOutlet weak var bottomControlsStackView: UIStackView!

    @IBOutlet weak var errorContainer: ThemeableView! {
        didSet {
            errorContainer.style = .playerContrast06
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(errorTapped))
            errorContainer.addGestureRecognizer(tapRecognizer)
        }
    }

    @IBOutlet weak var errorLabel: ThemeableLabel! {
        didSet {
            errorLabel.font = .font(ofSize: 14, weight: .medium, scalingWith: .subheadline)
            errorLabel.style = .playerContrast02
        }
    }

    @IBOutlet weak var playerBottomSpacing: NSLayoutConstraint!

    @IBOutlet weak var errorBottomSpacing: NSLayoutConstraint!

    var errorAutoDismissWork: DispatchWorkItem?

    let routePicker = PCRoutePickerView(frame: CGRect.zero)
    var isPresentingOverflowRoutePicker = false

    private lazy var upNextController = UpNextViewController(source: .nowPlaying)

    lazy var upNextViewController: UIViewController = {
        let controller = SJUIUtils.navController(for: upNextController, iconStyle: .secondaryText01, themeOverride: upNextController.themeOverride)
        controller.modalPresentationStyle = .pageSheet

        return controller
    }()

    var lastShelfLoadState = ShelfLoadState()

    private let analyticsPlaybackHelper = AnalyticsPlaybackHelper.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: NowPlayingPlayerItemViewController, _) in
            controller.preferredContentSizeCategoryDidChange()
        }

        let upNextPan = UIPanGestureRecognizer(target: self, action: #selector(panGestureRecognizerHandler(_:)))
        upNextPan.delegate = self
        view.addGestureRecognizer(upNextPan)

        routePicker.delegate = self

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        bannerTask?.cancel()
    }

    private var lastBoundsAdjustedFor = CGRect.zero

    var analyticsSource: AnalyticsSource {
        .player
    }

    var displayTranscript = false {
        didSet {
            toggleTranscript()
        }
    }

    private var playerContainer: PlayerContainerViewController? {
        parent as? PlayerContainerViewController
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // there's some expensive operations in resizeControls,
        // so only do them if the bounds has actually changed
        if lastBoundsAdjustedFor == view.bounds { return }
        lastBoundsAdjustedFor = view.bounds

        resizeControls()
    }

    private func resizeControls() {
        let spacing: CGFloat
        if view.bounds.width <= 320 {
            spacing = 8
        } else if view.bounds.width <= 375 {
            spacing = 20
        } else {
            spacing = 30
        }

        if playerControlsStackView.spacing != spacing { playerControlsStackView.spacing = spacing }

        // Base height for play/pause. If zoomed and not showing transcript, scale down a bit.
        let baseHeight: CGFloat = displayTranscript ? 40 : (view.bounds.height > 710 ? 100 : 80)
        let scaledHeight: CGFloat = (!displayTranscript && isZoomed) ? baseHeight * 0.9 : baseHeight
        if playPauseHeightConstraint.constant != scaledHeight { playPauseHeightConstraint.constant = scaledHeight }

        // Ensure skip buttons are not too large on zoomed displays.
        // Use small size either when showing transcript or when display is zoomed.
        let skipSize: SkipButton.Size = (displayTranscript || isZoomed) ? .small : .large
        skipBackBtn.changeSize(to: skipSize)
        skipFwdBtn.changeSize(to: skipSize)

        view.layoutIfNeeded()
    }

    override func willBeAddedToPlayer() {
        if episodeImage.image == nil, let placeholderArtwork {
            episodeImage.image = placeholderArtwork
            self.placeholderArtwork = nil
        }
        update()
        addObservers()
    }

    override func willBeRemovedFromPlayer() {
        removeAllCustomObservers()
    }

    override func themeDidChange() {
        lastShelfLoadState = ShelfLoadState()
        update()
    }

    private func preferredContentSizeCategoryDidChange() {
        updateSize()
    }

    var shelfIconSize: CGFloat {
        let metrics = UIFontMetrics(forTextStyle: .largeTitle)
        let iconSize = min(45, max(32, metrics.scaledValue(for: 32)))
        return iconSize
    }

    private func updateSize() {
        let iconSize = shelfIconSize
        for view in playerControlsStackView.subviews {
            view.updateSizeConstraints(to: iconSize)
        }
    }

    // MARK: - Interface Actions

    @IBAction func skipBackTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerSkipBackHaptic()
        PlaybackManager.shared.skipBack()
    }

    @IBAction func playPauseTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerPlayPauseHaptic()
        PlaybackManager.shared.playPause()
    }

    @IBAction func skipFwdTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerSkipForwardHaptic()
        PlaybackManager.shared.skipForward()
    }

    @IBAction func chapterSkipBackTapped(_ sender: Any) {
        PlaybackManager.shared.skipToPreviousChapter()
        PlaybackManager.shared.trackChapterEvent(.playerPreviousChapterTapped)
    }

    @IBAction func chapterSkipForwardTapped(_ sender: Any) {
        PlaybackManager.shared.skipToNextChapter()
        PlaybackManager.shared.trackChapterEvent(.playerNextChapterTapped)
    }

    @objc private func chapterLinkTapped() {
        let chapters = PlaybackManager.shared.currentChapters()
        guard let urlString = chapters.url, let url = URL(string: urlString) else { return }

            URLHelper.open(
                url,
                context: .externalContent,
                options: .init(
                    presenter: self,
                    prefersExternalBrowser: Settings.openLinks
                )
            )
    }

    @objc private func imageTapped() {
        guard let artwork = episodeImage.image else { return }

        let agrume = Agrume(image: artwork, background: .blurred(.regular))
        agrume.show(from: self)
    }

    @objc private func videoTapped() {
        guard let episode = PlaybackManager.shared.currentEpisode() else { return }

        if episode.videoPodcast() {
            let videoController = VideoViewController()
            videoViewController = videoController
            videoViewController?.modalTransitionStyle = .crossDissolve
            videoViewController?.modalPresentationStyle = .fullScreen
            videoViewController?.willAttachPlayer = { [weak self] in
                self?.floatingVideoView.player = nil
            }
            videoViewController?.willDeattachPlayer = { [weak self] in
                self?.floatingVideoView.player = PlaybackManager.shared.internalPlayerForVideoPlayback()
            }

            present(videoController, animated: true, completion: nil)
        }
    }

    @objc private func chapterNameTapped() {
        containerDelegate?.scrollToCurrentChapter()
    }

    @objc private func podcastNameTapped() {
        Analytics.track(.playerPodcastNameTapped)
        containerDelegate?.navigateToPodcast()
    }

    private func skipForwardLongPressed() {
        guard let episode = PlaybackManager.shared.currentEpisode() else { return }

        let options = OptionsPicker(title: nil, themeOverride: .dark)

        let markPlayedOption = OptionAction(label: L10n.markPlayedShort, icon: nil) {
            AnalyticsEpisodeHelper.shared.currentSource = .playerSkipForwardLongPress
            EpisodeManager.markAsPlayed(episode: episode, fireNotification: true)
        }
        options.addAction(action: markPlayedOption)

        if PlaybackManager.shared.upNextCount() > 0 {
            let skipToNextAction = OptionAction(label: L10n.nextEpisode, icon: nil) {
                let currentlyPlayingEpisode = PlaybackManager.shared.currentEpisode()
                PlaybackManager.shared.removeIfPlayingOrQueued(episode: currentlyPlayingEpisode, fireNotification: true, userInitiated: true)
            }
            options.addAction(action: skipToNextAction)
        }

        options.present(from: self)
    }

    private func toggleTranscript() {
        let isShowing = displayTranscript

        skipBackBtn.prepareForAnimateTransition(withBackground: view.backgroundColor)
        skipFwdBtn.prepareForAnimateTransition(withBackground: view.backgroundColor)
        playPauseBtn.prepareForAnimateTransition()

        playerContainer?.transcriptContainerView.layer.opacity = isShowing ? 0 : 1

        episodeImage.layer.opacity = 1

        if isShowing {
            playerContainer?.showTranscript()
        }

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 1, animations: { [weak self] in
            guard let self else { return }

            // Hide/show shelf
            shelfBg.isHidden = isShowing
            shelfBg.layer.opacity = isShowing ? 0 : 1

            // Show/hide transcript container view
            playerContainer?.transcriptContainerView.isHidden = false
            playerContainer?.transcriptContainerView.layer.opacity = isShowing ? 1 : 0

            // Change the stack view that contains the player button
            bottomControlsStackView.distribution = isShowing ? .fill : .equalSpacing
            bottomControlsStackView.spacing = isShowing ? 10 : 30

            // Display/hide the view that will fill the empty space
            fillView.isHidden = !isShowing

            // Change skip back and forward size (also keep small on zoomed displays)
            let skipButtonSize: SkipButton.Size = (isShowing || isZoomed) ? .small : .large
            skipBackBtn.changeSize(to: skipButtonSize)
            skipFwdBtn.changeSize(to: skipButtonSize)
            skipBackBtn.layoutIfNeeded()
            skipFwdBtn.layoutIfNeeded()

            // Ask parent VC to hide/show tabs
            playerContainer?.scrollView(isEnabled: !isShowing)

            resizeControls()
        }, completion: { [weak self] _ in
            guard let self else { return }

            playerContainer?.transcriptContainerView.isHidden = isShowing ? false : true

            if !isShowing {
                playerContainer?.hideTranscript()
            } else {
                episodeImage.layer.opacity = 0
            }

            playPauseBtn.finishedTransition()
            skipBackBtn.finishedTransition()
            skipFwdBtn.finishedTransition()
        })
    }
}
